import 'storage_service.dart';
import 'e2ee/story_crypto.dart';
import 'e2ee/media_crypto.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/friendship_model.dart';
import '../models/post_comment_model.dart';
import '../models/post_model.dart';
import '../models/story_model.dart';
import 'cache_service.dart';
import 'messaging_service.dart';
import 'post_limit_error.dart';
import '../utils/require_changed.dart';

/// All Supabase calls behind the Facebook-style home feed:
///   - posts            (CRUD + likes + comments)
///   - stories          (24h ephemeral)
///   - friendships      (request / accept / decline)
/// What happened to a post, for screens that show the same post (Home,
/// Profile) to stay in step without refetching.
enum PostChangeKind { created, updated, deleted }

class PostChange {
  const PostChange(this.kind, this.id, [this.post]);
  final PostChangeKind kind;
  final String id;

  /// The post as the server now has it; null for [PostChangeKind.deleted].
  final Post? post;
}

class FeedService {
  FeedService._();

  /// Every create / edit / delete of a post, emitted only after the server
  /// confirmed it. Home and Profile are separate kept-alive tabs: a post
  /// made from Profile never reached Home, and a post deleted on one stayed
  /// on the other until a manual refresh.
  static final _postChanges = StreamController<PostChange>.broadcast();
  static Stream<PostChange> get postChanges => _postChanges.stream;

  static final SupabaseClient _client = Supabase.instance.client;

  static const _postsTable = 'posts';
  static const _likesTable = 'post_likes';
  static const _commentsTable = 'post_comments';
  static const _storiesTable = 'stories';
  static const _friendshipsTable = 'friendships';

  static String? get _viewerId => _client.auth.currentUser?.id;

  // ===================================================================
  // POSTS
  // ===================================================================

  /// Personalised home-feed page. We OVER-fetch from the server in
  /// chronological order, then re-rank client-side by a composite
  /// score so two users on the same content pool don't see the same
  /// feed order. No ML — just transparent weights:
  ///
  ///   score = recency_decay                          (1.0 → 0, ~0.5 at 24h)
  ///         + min(log(1 + likes + 2*comments) * 0.30, 0.55)   (engagement)
  ///         + 0.50 if the author is a friend
  ///         + 0.35 if the post is from a church you follow
  ///         + 0.40 if the author is someone you follow (not a friend)
  ///         + 0.35 if the post is from a Page you follow
  ///         + up to 0.25 for the author's / Page's follower count (log)
  ///         + viewer-specific jitter (0..0.20)
  ///         - 0.70 if already seen (sinks, never hides)
  ///         + own_post penalty (-1, so your own post sinks)
  ///
  /// The engagement CAP is load-bearing. Uncapped it reached ~1.2 while
  /// recency maxes at 1.0, so a 3-day-old post with 50 likes (0.25 + 1.18)
  /// outranked a brand-new one (1.00 + 0) and the feed felt stale. Capped at
  /// 0.55 popularity can promote a post but never beat freshness outright.
  ///
  /// [friendIds] and [followedChurchIds] are passed in rather than fetched
  /// here — Home already loads both, and re-querying them per page would
  /// cost two extra round-trips on every scroll.
  ///
  /// Pagination is KEYSET, not offset: pass the oldest `createdAt` you
  /// already hold as [before]. Offset paging is unsafe under this ranking
  /// because page 2 would re-rank a different window and duplicate or drop
  /// posts. The trade-off is that ranking is per-page rather than global,
  /// which is how real feeds do it anyway.
  ///
  /// The optional [refreshNonce] reshuffles the jitter component on
  /// each pull-to-refresh so the same user sees a different ordering
  /// the next time they refresh — without changing the underlying
  /// content pool. Caller passes `DateTime.now().millisecondsSinceEpoch`
  /// (or any monotonically-changing int) from their refresh handler.
  static Future<List<Post>> fetchFeed({
    int limit = 15,
    int refreshNonce = 0,
    Set<String> friendIds = const {},
    Set<String> followedChurchIds = const {},
    Set<String> followedUserIds = const {},
    Set<String> followedPageIds = const {},
    DateTime? before,
    /// The viewer's ISO 3166-1 alpha-2 country. Used to RANK, not to
    /// filter: posts from here rise, posts from elsewhere still appear.
    /// See the countryBoost note in [_personalisedScore].
    String? viewerCountry,

    /// Hard country filter — a deliberate "show me only my country", not
    /// the default.
    ///
    /// Nothing in the app passes this today; the feed shows everyone and
    /// leans local through [viewerCountry]. It exists because the founder
    /// may want an explicit local-only view, and because the query shape
    /// (an indexed `posts.country`, patch_218) should be proven before it
    /// is needed rather than after.
    String? onlyCountry,
  }) async {
    final viewer = _viewerId;
    // Over-fetch so the re-rank has actual signal to work with.
    final overfetch = limit * 2;
    final response = await _readPosts((cols) {
      var query = _client.from(_postsTable).select(cols);
      if (onlyCountry != null && onlyCountry.isNotEmpty) {
        query = query.eq('country', onlyCountry);
      }
      if (before != null) {
        query = query.lt('created_at', before.toUtc().toIso8601String());
      }
      return query.order('created_at', ascending: false).limit(overfetch);
    });
    final posts = (response as List)
        .map((row) => Post.fromJson(
              row as Map<String, dynamic>,
              viewerId: viewer,
            ))
        .toList();
    if (viewer == null || posts.length <= 1) {
      return posts.take(limit).toList();
    }
    final reach = await _authorReach(posts);
    double score(Post p) => _personalisedScore(
          p,
          viewer,
          refreshNonce,
          friendIds: friendIds,
          followedChurchIds: followedChurchIds,
          followedUserIds: followedUserIds,
          followedPageIds: followedPageIds,
          viewerCountry: viewerCountry,
          followers: p.pageId != null
              ? reach['page:${p.pageId}']
              : reach['user:${p.authorId}'],
        );
    posts.sort((a, b) => score(b).compareTo(score(a)));
    return _diversify(posts).take(limit).toList();
  }

  /// How many posts newer than [after] the viewer can see, not counting
  /// their own — for Home's "↑ N new posts" pill. Ids only, at most
  /// [cap], so it is a cheap call. Null on any failure (the pill just
  /// doesn't show).
  static Future<int?> countNewerThan(DateTime after, {int cap = 20}) async {
    try {
      var query = _client
          .from(_postsTable)
          .select('id')
          .gt('created_at', after.toUtc().toIso8601String());
      final viewer = _viewerId;
      if (viewer != null) query = query.neq('author_id', viewer);
      final rows = await query.limit(cap);
      return (rows as List).length;
    } catch (_) {
      return null;
    }
  }

  /// The posts [countNewerThan] counted — same filter, same cap, newest
  /// first — so tapping "↑ 3 new posts" shows exactly those three. The
  /// ranked feed alone could not promise that: new posts are scored like
  /// any other and can land lower down or past the first page (3 Nov 2026
  /// report: "you click it and you don't see the new posts").
  static Future<List<Post>> fetchNewerThan(
    DateTime after, {
    int cap = 20,
  }) async {
    try {
      final viewer = _viewerId;
      final response = await _readPosts((cols) {
        var query = _client
            .from(_postsTable)
            .select(cols)
            .gt('created_at', after.toUtc().toIso8601String());
        if (viewer != null) query = query.neq('author_id', viewer);
        return query.order('created_at', ascending: false).limit(cap);
      });
      return (response as List)
          .map((row) => Post.fromJson(
                row as Map<String, dynamic>,
                viewerId: viewer,
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static const String _basePostCols =
      '*, '
      'profiles!posts_author_id_fkey(id, full_name, profile_photo_url, is_verified, is_verified_admin, who_can_follow), '
      'churches(name, profile_photo_url), '
      'post_likes(user_id, reaction), '
      'post_comments(id)';

  /// Whether `posts.page_id` → `pages` exists (patch_275). Null = not
  /// known yet. Reads find out by trying; writes only use the Page embed
  /// once a read has confirmed it, so a write is never retried.
  static bool? _pagesInSchema;

  static String get _pageCols =>
      '$_basePostCols, pages(id, name, logo_url, is_verified)';

  static String get _mutationCols =>
      _pagesInSchema == true ? _pageCols : _basePostCols;

  /// Runs a posts READ with the Page embed, falling back once — for the
  /// rest of the session — if the database doesn't have Pages yet. Before
  /// patch_275 an unknown embed would otherwise fail every feed.
  static Future<dynamic> _readPosts(
    Future<dynamic> Function(String cols) run,
  ) async {
    if (_pagesInSchema == false) return run(_basePostCols);
    try {
      final rows = await run(_pageCols);
      _pagesInSchema = true;
      return rows;
    } on PostgrestException catch (e) {
      final m = '${e.code} ${e.message} ${e.details}';
      if (!m.contains('pages') &&
          !m.contains('PGRST200') &&
          !m.contains('page_id')) {
        rethrow;
      }
      _pagesInSchema = false;
      return run(_basePostCols);
    }
  }

  @visibleForTesting
  static void debugResetPagesSchema() => _pagesInSchema = null;

  /// A single author's posts, strictly newest-first (for profile Posts
  /// tabs). Unlike [fetchFeed] this is NOT reshuffled by the personalised
  /// ranking — a profile should read latest → oldest as you scroll down.
  static Future<List<Post>> fetchPostsByAuthor(
    String authorId, {
    int limit = 100,
  }) async {
    final response = await _readPosts(
      (cols) => _client
          .from(_postsTable)
          .select(cols)
          .eq('author_id', authorId)
          .order('created_at', ascending: false)
          .limit(limit),
    );
    return (response as List)
        .map((row) =>
            Post.fromJson(row as Map<String, dynamic>, viewerId: _viewerId))
        .toList();
  }

  /// An organization Page's posts, newest first (patch_275). Only called
  /// once Pages exist, so it always asks for the Page embed.
  static Future<List<Post>> fetchPagePosts(
    String pageId, {
    int limit = 50,
  }) async {
    final response = await _client
        .from(_postsTable)
        .select(_pageCols)
        .eq('page_id', pageId)
        .order('created_at', ascending: false)
        .limit(limit);
    _pagesInSchema = true;
    return (response as List)
        .map((row) =>
            Post.fromJson(row as Map<String, dynamic>, viewerId: _viewerId))
        .toList();
  }

  /// Follower counts for the authors and Pages in [posts] (patch_283),
  /// keyed `user:ID` / `page:ID`. One round trip per feed page. Empty
  /// before the patch or on any failure — reach is a nudge, never a reason
  /// for the feed not to load.
  static Future<Map<String, int>> _authorReach(List<Post> posts) async {
    final users = <String>{};
    final pages = <String>{};
    for (final p in posts) {
      if (p.pageId != null) {
        pages.add(p.pageId!);
      } else if (p.authorId.isNotEmpty) {
        users.add(p.authorId);
      }
    }
    try {
      final rows = await _client.rpc(
        'author_reach',
        params: {'p_users': users.toList(), 'p_pages': pages.toList()},
      );
      return {
        for (final r in rows as List)
          '${(r as Map)['kind']}:${r['id']}':
              (r['followers'] as num?)?.toInt() ?? 0,
      };
    } catch (_) {
      return const {};
    }
  }

  /// Composite ranking score — higher = nearer the top of the feed.
  /// Pure function of post + viewer id + refresh nonce + social sets.
  static double _personalisedScore(
    Post p,
    String viewerId,
    int nonce, {
    Set<String> friendIds = const {},
    Set<String> followedChurchIds = const {},
    Set<String> followedUserIds = const {},
    Set<String> followedPageIds = const {},
    String? viewerCountry,
    int? followers,
  }) {
    final ageHours =
        DateTime.now().difference(p.createdAt).inHours.toDouble();
    // Smooth decay: 1.0 at 0h, ~0.5 at 24h, ~0.25 at 72h.
    final recency = 1.0 / (1.0 + (ageHours / 24.0));
    // CAPPED. Uncapped this reached ~1.2 while recency maxes at 1.0, so a
    // 72h-old post with 50 likes (0.25 + 1.18 = 1.43) beat a brand-new one
    // (1.00 + 0) — the measured reason the feed felt stale. At 0.55,
    // popularity can promote a post but never outrank freshness outright.
    final engagement = math.min(
      math.log(1 + p.likeCount + (p.commentCount * 2)) * 0.30,
      0.55,
    );
    // Social signal. Previously absent entirely — a friend's post ranked
    // identically to a stranger's, which is the biggest single reason the
    // feed felt impersonal. Both sets are passed in by the caller.
    final friendBoost = friendIds.contains(p.authorId) ? 0.50 : 0.0;
    final churchId = p.churchId;
    final churchBoost =
        (churchId != null && followedChurchIds.contains(churchId)) ? 0.35 : 0.0;
    // Following (patch_274/275). Before this a follow changed nothing on
    // Home — it was a notification and a number. A followed person sits
    // just under a friend (you chose them, but you're not mutual); a
    // followed Page ranks like a followed church. A friend you also follow
    // gets the friend boost only — the two don't stack.
    final followBoost =
        friendBoost == 0 && followedUserIds.contains(p.authorId) ? 0.40 : 0.0;
    final pageId = p.pageId;
    final pageBoost =
        (pageId != null && followedPageIds.contains(pageId)) ? 0.35 : 0.0;
    // Reach (owner, 29 Oct 2026: "more followers more visibility in home
    // screen only"). Logarithmic and capped at 0.25: 10 followers ≈ 0.10,
    // 100 ≈ 0.20, ~300+ = 0.25. Below a followed Page (0.35) and a friend
    // (0.50) on purpose, so a big account lifts in everyone's feed but
    // never buries the people you actually know. Home only — nothing else
    // calls this ranking.
    final reachBoost = followers == null || followers <= 0
        ? 0.0
        : math.min(math.log(1 + followers) / math.ln10 * 0.10, 0.25);
    // Already scrolled past: SINK it, don't hide it. -0.7 is enough to lose
    // to almost any unseen post, but a seen post with real engagement can
    // still resurface — which is what you want when a thread gets busy after
    // you first saw it.
    // Country is a BOOST, never a filter.
    //
    // The obvious implementation was to scope the feed to the viewer's
    // country the way the marketplace is scoped. It is wrong here, and the
    // difference is worth stating: a sofa in Harare genuinely cannot be
    // collected from Boston, but a post from Harare reads perfectly well
    // there. Scoping the feed would cut a Zimbabwean in Texas off from the
    // exact people they installed this app to stay near — and with every
    // post today coming from Zimbabwe, it would greet every new overseas
    // member with an empty Home.
    //
    // 0.30 sits below churchBoost (0.35) and friendBoost (0.50) on purpose:
    // someone you know abroad still outranks a stranger next door.
    final countryBoost =
        (viewerCountry != null && p.country == viewerCountry) ? 0.30 : 0.0;
    final seenPenalty = seenPostIdsCached().contains(p.id) ? -0.70 : 0.0;
    // Including the nonce in the seed means a fresh refresh hands
    // the user a different jittered order, even on identical content.
    // Two different users still see different orders too (viewerId
    // is part of the seed).
    final seed = '${viewerId}_${p.id}_$nonce'.hashCode.abs();
    final jitter = ((seed % 1000) / 1000.0) * 0.20;
    // Your own posts rank like anyone's, with a short lift while they are
    // new so the one you just published stays near the top after a
    // refresh. It used to be a flat -1.0 — together with a filter in Home,
    // the author never saw their own post in their feed.
    final ownBoost = p.authorId == viewerId &&
            DateTime.now().difference(p.createdAt) < const Duration(hours: 6)
        ? 0.6
        : 0.0;
    return recency +
        engagement +
        friendBoost +
        churchBoost +
        followBoost +
        pageBoost +
        reachBoost +
        countryBoost +
        jitter +
        seenPenalty +
        ownBoost;
  }

  /// Prevent the top of the feed from being dominated by a single
  /// author. Walks the sorted list and demotes a post by N slots
  /// whenever it'd make a third consecutive run from the same
  /// authorId. Cheap, deterministic, no allocation per item.
  static List<Post> _diversify(List<Post> sorted) {
    if (sorted.length < 3) return sorted;
    final out = <Post>[];
    final deferred = <Post>[];
    String? prev1;
    String? prev2;
    for (final p in sorted) {
      if (p.authorId == prev1 && prev1 == prev2) {
        deferred.add(p);
        continue;
      }
      out.add(p);
      prev2 = prev1;
      prev1 = p.authorId;
    }
    out.addAll(deferred);
    return out;
  }

  /// Creates a post.
  ///
  /// [imageUrls] carries every photo, first-first. `image_url` is ALWAYS
  /// written with the first one as well, for two reasons: `posts_check`
  /// requires `body IS NOT NULL OR image_url IS NOT NULL`, so a photo-only
  /// post would be rejected outright without it; and clients still on v1.3.0
  /// only know about that column, so this is what keeps new posts visible to
  /// them. Never drop it.
  static Future<Post> createPost({
    String? body,
    String? imageUrl,
    List<String> imageUrls = const [],
    PostVisibility visibility = PostVisibility.public,
    String? churchId,

    /// Post AS this organization Page (patch_275). The database refuses it
    /// unless the viewer is one of the Page's admins.
    String? pageId,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to post.');
    }
    final cleanBody = body?.trim();
    // Collapse the single + multi arguments into one ordered, de-duped list.
    final photos = <String>{
      if (imageUrl != null && imageUrl.trim().isNotEmpty) imageUrl.trim(),
      for (final u in imageUrls)
        if (u.trim().isNotEmpty) u.trim(),
    }.toList();
    if ((cleanBody == null || cleanBody.isEmpty) && photos.isEmpty) {
      throw ArgumentError('Either body or a photo must be provided.');
    }
    final inserted = await PostLimitError.guard(
      PostSection.feedPost,
      () => _client
          .from(_postsTable)
          .insert({
            'author_id': user.id,
            if (cleanBody != null && cleanBody.isNotEmpty) 'body': cleanBody,
            if (photos.isNotEmpty) 'image_url': photos.first,
            if (photos.isNotEmpty) 'image_urls': photos,
            'visibility': visibility == PostVisibility.friendsOnly
                ? 'friends_only'
                : 'public',
            // Church-branded post: validated server-side (patch_141 trigger)
            // so only an approved admin of the church can attribute to it.
            if (churchId != null)
              'church_id': int.tryParse(churchId) ?? churchId,
            'page_id': ?pageId,
          })
          .select(
            // A Page post needs the Page embed to show as the Page.
            pageId != null ? _pageCols : _mutationCols,
          )
          .single(),
    );
    final post = Post.fromJson(inserted, viewerId: _viewerId);
    _postChanges.add(PostChange(PostChangeKind.created, post.id, post));
    return post;
  }

  static Future<void> deletePost(String postId) async {
    requireChanged(
      await _client.from(_postsTable).delete().eq('id', postId).select('id'),
      'post $postId',
    );
    _postChanges.add(PostChange(PostChangeKind.deleted, postId));
  }

  // ---- Saved and hidden posts (patch_273) -------------------------------

  /// Posts the member saved / hid. The post card reads these directly, so
  /// Save and Hide behave the same on every surface that shows a post.
  static final ValueNotifier<Set<String>> savedPostIds = ValueNotifier({});
  static final ValueNotifier<Set<String>> hiddenPostIds = ValueNotifier({});

  /// True once patch_273's tables answered; false while they don't exist,
  /// so the menu can say so instead of pretending to save.
  static bool savedPostsAvailable = true;

  /// Loads both sets. Safe to call repeatedly; failures leave them as they
  /// were (and mark the feature unavailable if the tables are missing).
  static Future<void> loadSavedAndHidden() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final rows = await Future.wait([
        _client.from('saved_posts').select('post_id').eq('user_id', uid),
        _client.from('hidden_posts').select('post_id').eq('user_id', uid),
      ]);
      savedPostsAvailable = true;
      savedPostIds.value = {
        for (final r in rows[0] as List) (r as Map)['post_id'].toString(),
      };
      hiddenPostIds.value = {
        for (final r in rows[1] as List) (r as Map)['post_id'].toString(),
      };
    } catch (e) {
      if (_isMissingTable(e)) savedPostsAvailable = false;
    }
  }

  static bool _isMissingTable(Object e) {
    final s = e.toString();
    return s.contains('saved_posts') || s.contains('hidden_posts') ||
        s.contains('42P01') || s.contains('PGRST205');
  }

  /// Save or unsave. Optimistic; reverts and rethrows if the server refuses.
  static Future<void> setSaved(String postId, bool saved) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthException('Sign in to save posts.');
    final before = savedPostIds.value;
    savedPostIds.value = saved
        ? {...before, postId}
        : ({...before}..remove(postId));
    try {
      if (saved) {
        await _client
            .from('saved_posts')
            .upsert({'user_id': uid, 'post_id': postId});
      } else {
        await _client
            .from('saved_posts')
            .delete()
            .eq('user_id', uid)
            .eq('post_id', postId);
      }
    } catch (e) {
      savedPostIds.value = before;
      if (_isMissingTable(e)) savedPostsAvailable = false;
      rethrow;
    }
  }

  /// Hide a post from your own feed ("see less"), or bring it back.
  static Future<void> setHidden(String postId, bool hidden) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthException('Sign in first.');
    final before = hiddenPostIds.value;
    hiddenPostIds.value = hidden
        ? {...before, postId}
        : ({...before}..remove(postId));
    try {
      if (hidden) {
        await _client
            .from('hidden_posts')
            .upsert({'user_id': uid, 'post_id': postId});
      } else {
        await _client
            .from('hidden_posts')
            .delete()
            .eq('user_id', uid)
            .eq('post_id', postId);
      }
    } catch (e) {
      hiddenPostIds.value = before;
      if (_isMissingTable(e)) savedPostsAvailable = false;
      rethrow;
    }
  }

  /// The member's saved posts, newest save first. Posts they can no longer
  /// see (deleted, made private, moderated) simply don't come back.
  static Future<List<Post>> fetchSavedPosts() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];
    final saved = await _client
        .from('saved_posts')
        .select('post_id, created_at')
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(200);
    final ids = [for (final r in saved as List) (r as Map)['post_id'].toString()];
    if (ids.isEmpty) return const [];
    final rows = await _readPosts(
      (cols) => _client.from(_postsTable).select(cols).inFilter('id', ids),
    );
    final byId = {
      for (final r in rows as List)
        (r as Map)['id'].toString():
            Post.fromJson(r as Map<String, dynamic>, viewerId: _viewerId),
    };
    return [for (final id in ids) ?byId[id]];
  }

  /// Super admin: hide a post from everyone but its author (or restore it)
  /// and notify the author with a way to appeal. Backed by
  /// `admin_set_post_hidden` (patch_272), which refuses non-admins.
  static Future<void> adminSetPostHidden(
    String postId, {
    required bool hidden,
    String? reason,
  }) async {
    await _client.rpc('admin_set_post_hidden', params: {
      'p_post_id': postId,
      'p_hidden': hidden,
      'p_reason': reason,
    });
  }

  /// Body-text search across the feed. Respects visibility via RLS so
  /// friends-only posts are only returned to friends / the author.
  static Future<List<Post>> searchPosts(String query, {int limit = 20}) async {
    final term = query.trim();
    if (term.isEmpty) return const [];
    final response = await _readPosts(
      (cols) => _client
          .from(_postsTable)
          .select(cols)
          .ilike('body', '%$term%')
          .order('created_at', ascending: false)
          .limit(limit),
    );
    return (response as List)
        .map((row) => Post.fromJson(
              row as Map<String, dynamic>,
              viewerId: _viewerId,
            ))
        .toList();
  }

  /// Update the body and/or visibility of a post the viewer owns.
  /// RLS already restricts updates to the author so we don't have to
  /// guard client-side. Returns the refreshed Post.
  static Future<Post> updatePost(
    String postId, {
    String? body,
    PostVisibility? visibility,
  }) async {
    final patch = <String, dynamic>{};
    if (body != null) patch['body'] = body.trim().isEmpty ? null : body.trim();
    if (visibility != null) {
      patch['visibility'] = visibility == PostVisibility.friendsOnly
          ? 'friends_only'
          : 'public';
    }
    if (patch.isEmpty) {
      throw ArgumentError('Nothing to update.');
    }
    final updated = await _client
        .from(_postsTable)
        .update(patch)
        .eq('id', postId)
        .select(
          _mutationCols,
        )
        .single();
    final post = Post.fromJson(updated, viewerId: _viewerId);
    _postChanges.add(PostChange(PostChangeKind.updated, post.id, post));
    return post;
  }

  // ---- Likes --------------------------------------------------------

  // ---- Seen tracking ------------------------------------------------------
  //
  // Without this the feed re-served the same posts every open, and because
  // `refreshNonce` re-jitters on each pull the user met them in a NEW order
  // every time — which reads as "the app is random" rather than "the app is
  // fresh". Seen posts now sink instead of disappearing, so nothing is ever
  // unreachable; they just stop competing for the top.

  static const String _viewsTable = 'post_views';

  /// Ids buffered on the client until [flushSeen] writes them.
  static final Set<String> _pendingSeen = <String>{};

  /// Recently-seen ids, held in memory so ranking doesn't hit the network.
  static Set<String> _seenCache = <String>{};

  static Set<String> seenPostIdsCached() => _seenCache;

  /// Loads the viewer's recent history. Bounded deliberately — a heavy user
  /// could accumulate thousands of rows, and ranking only needs enough to
  /// recognise "I've already scrolled past this".
  static Future<Set<String>> fetchSeenPostIds({int limit = 400}) async {
    final viewer = _viewerId;
    if (viewer == null) return <String>{};
    try {
      final rows = await _client
          .from(_viewsTable)
          .select('post_id')
          .eq('viewer_id', viewer)
          .order('viewed_at', ascending: false)
          .limit(limit);
      _seenCache = {
        for (final r in rows as List) (r as Map)['post_id'].toString(),
      };
      return _seenCache;
    } catch (_) {
      // Offline or RLS hiccup — an empty set just means nothing sinks.
      return _seenCache;
    }
  }

  /// Buffers a post as seen. Cheap and synchronous; call it freely from a
  /// scroll callback. Nothing hits the network until [flushSeen].
  static void markSeen(String postId) {
    if (_viewerId == null) return;
    if (_seenCache.contains(postId)) return;
    _pendingSeen.add(postId);
  }

  /// Writes the buffer in ONE request. Batched on purpose: a naive
  /// per-card insert would fire a write for every row that scrolls by.
  static Future<void> flushSeen() async {
    final viewer = _viewerId;
    if (viewer == null || _pendingSeen.isEmpty) return;
    final batch = List<String>.of(_pendingSeen);
    _pendingSeen.clear();
    // Optimistic: treat them as seen locally even if the write loses, so we
    // don't re-buffer the same ids on the next scroll.
    _seenCache.addAll(batch);
    try {
      await _client.from(_viewsTable).upsert(
            [
              for (final id in batch) {'post_id': id, 'viewer_id': viewer},
            ],
            onConflict: 'post_id,viewer_id',
            ignoreDuplicates: true,
          );
    } catch (_) {
      // Best-effort. Losing a batch costs a slightly staler feed, nothing more.
    }
  }

  /// Sets the viewer's reaction on a post, replacing any previous one.
  ///
  /// `post_likes` has a (post_id, user_id) primary key, so one row per person
  /// per post — switching from Like to Amen updates in place rather than
  /// adding a second row. `ignoreDuplicates` must stay FALSE here or the
  /// upsert would silently keep the old reaction.
  static Future<void> reactToPost(String postId, PostReaction reaction) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to react.');
    }
    await _client.from(_likesTable).upsert(
      {'post_id': postId, 'user_id': user.id, 'reaction': reaction.wire},
      onConflict: 'post_id,user_id',
    );
  }

  /// Removes the viewer's reaction entirely.
  static Future<void> removeReaction(String postId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from(_likesTable)
        .delete()
        .eq('post_id', postId)
        .eq('user_id', user.id);
  }

  /// Back-compat wrappers so the profile screens' plain like toggles keep
  /// working without knowing about reaction types.
  static Future<void> likePost(String postId) =>
      reactToPost(postId, PostReaction.like);

  static Future<void> unlikePost(String postId) => removeReaction(postId);

  // ---- Comments -----------------------------------------------------

  /// All comments on a post, flat, oldest first. The bottom sheet calls
  /// [PostComment.buildTree] to nest replies under their parents before
  /// rendering. Reactions are joined so we can compute like/dislike
  /// counts + the viewer's own vote without a second round-trip.
  static Future<List<PostComment>> fetchComments(String postId) async {
    final response = await _client
        .from(_commentsTable)
        .select(
          '*, '
          'profiles!post_comments_author_id_fkey(id, full_name, profile_photo_url, is_verified, is_verified_admin), '
          'post_comment_reactions(user_id, value)',
        )
        .eq('post_id', postId)
        .order('created_at', ascending: true);
    return (response as List)
        .map((row) => PostComment.fromJson(
              row as Map<String, dynamic>,
              viewerId: _viewerId,
            ))
        .toList();
  }

  static Future<PostComment> addComment({
    required String postId,
    required String body,
    String? parentCommentId,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to comment.');
    }
    final clean = body.trim();
    if (clean.isEmpty) {
      throw ArgumentError('Comment body cannot be empty.');
    }
    final inserted = await _client
        .from(_commentsTable)
        .insert({
          'post_id': postId,
          'author_id': user.id,
          'body': clean,
          'parent_comment_id': ?parentCommentId,
        })
        .select(
          '*, '
          'profiles!post_comments_author_id_fkey(id, full_name, profile_photo_url, is_verified, is_verified_admin), '
          'post_comment_reactions(user_id, value)',
        )
        .single();
    return PostComment.fromJson(inserted, viewerId: _viewerId);
  }

  /// Delete a comment. RLS (patch_044) permits this when the caller
  /// authored the comment OR owns the post it's on, so the same call
  /// serves both "delete my comment" and "remove a comment from my
  /// post". A no-op server-side if neither applies.
  static Future<void> deleteComment(String commentId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to delete comments.');
    }
    requireChanged(
      await _client
          .from(_commentsTable)
          .delete()
          .eq('id', commentId)
          .select('id'),
      'comment $commentId',
    );
  }

  /// Cast / change / clear the viewer's vote on a comment.
  ///   value =  1 → like
  ///   value = -1 → dislike
  ///   value =  0 → withdraw any existing vote
  /// Idempotent — re-sending the same value upserts the same row.
  static Future<void> reactToComment({
    required String commentId,
    required int value,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to vote on comments.');
    }
    if (value == 0) {
      await _client
          .from('post_comment_reactions')
          .delete()
          .eq('comment_id', commentId)
          .eq('user_id', user.id);
      return;
    }
    if (value != 1 && value != -1) {
      throw ArgumentError('value must be -1, 0 or 1');
    }
    await _client.from('post_comment_reactions').upsert(
      {
        'comment_id': commentId,
        'user_id': user.id,
        'value': value,
      },
      onConflict: 'comment_id,user_id',
    );
  }

  // ===================================================================
  // STORIES
  // ===================================================================

  /// All active stories. RLS filters expired rows server-side, but we
  /// add an explicit `expires_at > now()` filter + a client-side
  /// dedupe so a misconfigured policy or an old row with a bogus
  /// expires_at can't keep stale content on the rail.
  static Future<List<Story>> fetchStories() async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final response = await _client
        .from(_storiesTable)
        .select(
          '*, '
          'profiles!stories_author_id_fkey(id, full_name, profile_photo_url, is_verified, is_verified_admin)',
        )
        .gt('expires_at', nowIso)
        .order('created_at', ascending: false)
        .limit(200);
    final stories = (response as List)
        .map((row) => Story.fromJson(row as Map<String, dynamic>))
        .where((s) => !s.isExpired)
        .toList();
    // Encrypted stories (patch_300): open the ones this phone can.
    return StoryCrypto.openAll(stories);
  }

  static Future<Story> createStory({
    String? mediaUrl,
    String? localPhotoPath,
    String? caption,
    String kind = 'photo',
    String? textContent,
    String? backgroundColor,
    String? textFont,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to post a story.');
    }

    // End-to-end encrypted story (patch_300). The row gets no readable
    // text; the photo is sealed; friends get the envelope per phone.
    StoryEnvelope? envelope;
    if (StoryCrypto.shouldEncrypt) {
      MediaKey? key;
      if (localPhotoPath != null) {
        final sealed = MediaCrypto.encrypt(
          await File(localPhotoPath).readAsBytes(),
        );
        key = sealed.key;
        mediaUrl = await StorageService.uploadStoryBytes(
          sealed.bytes,
          ext: 'jpg',
          sealed: true,
        );
      }
      envelope = StoryEnvelope(
        text: (textContent ?? '').trim().isEmpty ? null : textContent!.trim(),
        caption: (caption ?? '').trim().isEmpty ? null : caption!.trim(),
        key: key,
      );
      textContent = null;
      caption = null;
    } else if (localPhotoPath != null) {
      final path = localPhotoPath;
      mediaUrl = await StorageService.uploadStoryBytes(
        await File(path).readAsBytes(),
        ext: path.contains('.') ? path.split('.').last : 'jpg',
      );
    }

    final inserted = await PostLimitError.guard(
      PostSection.story,
      () => _client
          .from(_storiesTable)
          .insert({
            'author_id': user.id,
            'kind': kind,
            if (mediaUrl != null && mediaUrl.isNotEmpty) 'media_url': mediaUrl,
            if (textContent != null && textContent.trim().isNotEmpty)
              'text_content': textContent.trim(),
            'background_color': ?backgroundColor,
            if (textFont != null && textFont.isNotEmpty) 'text_font': textFont,
            if (caption != null && caption.trim().isNotEmpty)
              'caption': caption.trim(),
            if (envelope != null) 'e2ee_version': 1,
          })
          .select(
            '*, '
            'profiles!stories_author_id_fkey(id, full_name, profile_photo_url, is_verified, is_verified_admin)',
          )
          .single(),
    );
    final story = Story.fromJson(inserted);
    if (envelope == null) return story;
    await StoryCrypto.rememberOwn(story.id, envelope);
    // Friends' keys. Not awaited past a short wait: a slow network must
    // not hold the composer open; friends who load before it lands see
    // the story a moment later.
    await StoryCrypto.distribute(story.id, envelope)
        .timeout(const Duration(seconds: 20), onTimeout: () => 0);
    return story.opened(
      textContent: envelope.text,
      caption: envelope.caption,
      mediaKey: envelope.key,
    );
  }

  /// Fetch a single story by id (for opening a status-reply's tagged
  /// story). Returns null if it's gone or expired (statuses last 24h), so
  /// the caller can fall back to showing the saved image.
  static Future<Story?> fetchStoryById(String storyId) async {
    try {
      final row = await _client
          .from(_storiesTable)
          .select(
            '*, '
            'profiles!stories_author_id_fkey(id, full_name, profile_photo_url, is_verified, is_verified_admin)',
          )
          .eq('id', storyId)
          .maybeSingle();
      if (row == null) return null;
      final s = Story.fromJson(row);
      if (s.isExpired) return null;
      return (await StoryCrypto.openAll([s])).first;
    } catch (_) {
      return null;
    }
  }

  /// Delete a story. RLS gates this to the author only (per the
  /// stories_delete_author policy created in schema.sql); failures
  /// throw a PostgrestException the caller can surface.
  static Future<void> deleteStory(String storyId) async {
    // No row check here, unlike posts: `stories_select_active` hides an
    // expired story even from its author, and a delete that selects its
    // rows back would then skip it — deleting your own old story would
    // quietly stop working.
    await _client.from(_storiesTable).delete().eq('id', storyId);
  }

  // --- Shared viewed-story cache ---------------------------------------
  // Every "story ring" surface (home rail, chat inbox, contact sheet, and
  // the post-card avatar) reads from the SAME persisted set, so a story
  // watched from ANY entry point greys its ring everywhere immediately and
  // the state survives navigation + app restarts. This is what stops the
  // ring "forgetting then remembering" that you'd already watched a story.
  // Keyed per-user so accounts don't bleed into each other.
  static Set<String>? _viewedCache;
  static String? _viewedCacheKey;

  static String get _viewedKey => 'pref:viewed_story_ids:${_viewerId ?? 'anon'}';

  static Set<String> _loadViewedCache() {
    final key = _viewedKey;
    if (_viewedCache != null && _viewedCacheKey == key) return _viewedCache!;
    _viewedCacheKey = key;
    final raw = CacheService.readPref(key);
    _viewedCache = (raw == null || raw.isEmpty)
        ? <String>{}
        : raw.split(',').where((s) => s.isNotEmpty).toSet();
    return _viewedCache!;
  }

  static Future<void> _persistViewedCache() async {
    final list = (_viewedCache ?? <String>{}).toList();
    // Bound the list (stories expire in 24h anyway) so it can't grow forever.
    final capped =
        list.length > 800 ? list.sublist(list.length - 800) : list;
    await CacheService.writePref(_viewedKey, capped.join(','));
  }

  /// Synchronous, app-wide set of story ids the viewer has watched, seeded
  /// from the persistent cache. Surfaces union this into their fetched set
  /// so freshly-watched stories grey instantly everywhere.
  static Set<String> viewedStoryIdsCached() => <String>{..._loadViewedCache()};

  /// Story ids the current user has already viewed — used to grey out
  /// viewed status rings and order unviewed first. Merges the server rows
  /// with the local cache so optimistic (just-watched) views are never lost
  /// to replication lag, and falls back to the cache entirely when offline.
  static Future<Set<String>> fetchMyViewedStoryIds() async {
    final user = _client.auth.currentUser;
    if (user == null) return <String>{};
    final cache = _loadViewedCache();
    try {
      final rows = await _client
          .from('story_views')
          .select('story_id')
          .eq('viewer_id', user.id);
      cache.addAll(
        (rows as List).map((r) => (r as Map)['story_id'].toString()),
      );
      unawaited(_persistViewedCache());
      return <String>{...cache};
    } catch (_) {
      return <String>{...cache};
    }
  }

  /// Record that the current viewer has watched [storyId]. Idempotent
  /// — re-watching the same story is a no-op (PK collision on the
  /// (story_id, viewer_id) pair is silently swallowed). Authors
  /// don't get marked as viewing their own stories.
  static Future<void> markStoryViewed(String storyId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    // Update the shared cache FIRST so every ring greys instantly, even
    // before (or without) the server round-trip.
    _loadViewedCache().add(storyId);
    unawaited(_persistViewedCache());
    try {
      await _client.from('story_views').insert({
        'story_id': storyId,
        'viewer_id': user.id,
      });
    } catch (_) {
      // duplicate-key (already viewed) is fine — swallow all errors
      // so a flaky network never blocks the viewer UI.
    }
  }

  /// Fetch the viewer list for a story the current user owns. Returns
  /// a list of {user_id, full_name, profile_photo_url, viewed_at}
  /// tuples ordered by most-recent view first. RLS only returns rows
  /// when the caller is the story's author.
  static Future<List<Map<String, dynamic>>> fetchStoryViewers(
    String storyId,
  ) async {
    try {
      final response = await _client
          .from('story_views')
          .select(
            'viewed_at, profiles!story_views_viewer_id_fkey('
            'id, full_name, profile_photo_url)',
          )
          .eq('story_id', storyId)
          .order('viewed_at', ascending: false);
      return (response as List).map((row) {
        final map = row as Map<String, dynamic>;
        final profile = map['profiles'] as Map<String, dynamic>?;
        return <String, dynamic>{
          'user_id': profile?['id']?.toString() ?? '',
          'full_name': profile?['full_name']?.toString() ?? 'Member',
          'profile_photo_url': profile?['profile_photo_url']?.toString(),
          'viewed_at': map['viewed_at']?.toString() ?? '',
        };
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Whether the current viewer has liked [storyId]. Reads back the
  /// caller's own like row (RLS permits self-reads). Swallows errors so
  /// a missing table / network blip just renders an empty heart.
  static Future<bool> isStoryLiked(String storyId) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    try {
      final rows = await _client
          .from('story_likes')
          .select('story_id')
          .eq('story_id', storyId)
          .eq('user_id', user.id)
          .limit(1);
      return (rows as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Toggle the current viewer's like on [storyId]. [currentlyLiked] is
  /// the caller's optimistic state; we persist the opposite. Returns the
  /// new state actually applied (falls back to [currentlyLiked] on
  /// failure so the UI can roll back).
  static Future<bool> toggleStoryLike(
    String storyId, {
    required bool currentlyLiked,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return currentlyLiked;
    try {
      if (currentlyLiked) {
        await _client
            .from('story_likes')
            .delete()
            .eq('story_id', storyId)
            .eq('user_id', user.id);
        return false;
      } else {
        // UPSERT (not insert) so re-liking never collides on the
        // (story_id, user_id) PK — the plain insert threw a duplicate-key
        // error when the local state was stale, which made likes appear to
        // "forget then remember".
        //
        // ignoreDuplicates is what makes that actually work.
        // `story_likes` has SELECT and INSERT policies but NO UPDATE
        // policy, so a bare upsert becomes ON CONFLICT DO UPDATE and RLS
        // rejects it with 42501 — meaning the precise stale-state case
        // this upsert was written for still failed, silently, because
        // the catch below just returns the old value. DO NOTHING needs
        // only the INSERT policy, and there is nothing to update anyway:
        // the row is the (story, user) pair and nothing else.
        await _client.from('story_likes').upsert(
          {'story_id': storyId, 'user_id': user.id},
          onConflict: 'story_id,user_id',
          ignoreDuplicates: true,
        );
        return true;
      }
    } catch (_) {
      return currentlyLiked;
    }
  }

  /// Who liked a story the current user owns. Returns
  /// {user_id, full_name, profile_photo_url, liked_at} tuples, newest
  /// first. RLS only returns rows when the caller authored the story.
  static Future<List<Map<String, dynamic>>> fetchStoryLikers(
    String storyId,
  ) async {
    try {
      final response = await _client
          .from('story_likes')
          .select(
            'created_at, profiles!story_likes_user_id_fkey('
            'id, full_name, profile_photo_url)',
          )
          .eq('story_id', storyId)
          .order('created_at', ascending: false);
      return (response as List).map((row) {
        final map = row as Map<String, dynamic>;
        final profile = map['profiles'] as Map<String, dynamic>?;
        return <String, dynamic>{
          'user_id': profile?['id']?.toString() ?? '',
          'full_name': profile?['full_name']?.toString() ?? 'Member',
          'profile_photo_url': profile?['profile_photo_url']?.toString(),
          'liked_at': map['created_at']?.toString() ?? '',
        };
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  // ===================================================================
  // FRIENDSHIPS
  // ===================================================================

  /// Bumped whenever a friendship is created, accepted or removed —
  /// anywhere in the app.
  ///
  /// Several screens cache "am I friends with this person?" in local
  /// state and only ever loaded it in initState, so a row could sit on
  /// "Requested" long after the request had been accepted somewhere else
  /// (Find people was the reported case). Listening to this and
  /// re-reading is a two-line fix per screen and, unlike a manual
  /// refresh, it can't be forgotten by the next screen that shows a
  /// friend button.
  static final ValueNotifier<int> friendshipsChanged = ValueNotifier<int>(0);

  static void _noteFriendshipChange() {
    friendshipsChanged.value++;
  }

  /// Every friendship row that involves the viewer, in either direction.
  /// The home screen uses this to decide which suggestion cards to show
  /// the right CTA on ("Add friend" / "Pending" / "Accept").
  static Future<List<Friendship>> fetchMyFriendships() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    final response = await _client
        .from(_friendshipsTable)
        .select()
        .or('requester_id.eq.${user.id},addressee_id.eq.${user.id}');
    return (response as List)
        .map((row) => Friendship.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Count of incoming pending requests for the badge on the chat
  /// bubble / bottom nav.
  static Future<int> pendingRequestCount() async {
    final user = _client.auth.currentUser;
    if (user == null) return 0;
    final response = await _client
        .from(_friendshipsTable)
        .select('id')
        .eq('addressee_id', user.id)
        .eq('status', 'pending');
    return (response as List).length;
  }

  /// Pending incoming friend requests + the requester's profile. Used
  /// by the Conversations "Requests" tab so users can find and act on
  /// incoming requests without having to hunt for the suggestion card
  /// on the home tab.
  ///
  /// Two round-trips: friendships first, then a single batched lookup
  /// of the requester profiles. We avoid relying on a Supabase FK
  /// embed (`profiles!friendships_requester_id_fkey(...)`) because the
  /// FK name varies across deployments — the two-step path works
  /// regardless of how the schema is named.
  static Future<List<PendingFriendRequest>>
      fetchPendingFriendRequests() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    // patch_043: go through the SECURITY DEFINER RPC so the requester's
    // name + photo come back even when their profile isn't
    // discoverable. Reading profiles directly was blocked by
    // profiles_select_discoverable_or_self for non-discoverable
    // requesters, which surfaced everyone as "Member".
    final rows = await _client.rpc('pending_friend_requests');
    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return const [];

    return list.map((r) {
      final name = (r['requester_name'] as String?)?.trim();
      return PendingFriendRequest(
        friendshipId: (r['friendship_id'] ?? '').toString(),
        requesterId: (r['requester_id'] ?? '').toString(),
        requesterName: (name == null || name.isEmpty) ? 'Member' : name,
        requesterPhotoUrl: r['requester_photo_url'] as String?,
        requesterChurchName: r['requester_church_name'] as String?,
        createdAt: r['created_at'] != null
            ? (DateTime.tryParse(r['created_at'].toString()) ??
                DateTime.now())
            : DateTime.now(),
      );
    }).toList();
  }

  /// The viewer's accepted friends, with display fields (patch_177).
  ///
  /// Goes through a SECURITY DEFINER RPC for the same reason
  /// [fetchPendingFriendRequests] does: reading `profiles` directly is
  /// gated by profiles_select_discoverable_or_self, so any friend who
  /// turned discoverability off would come back as "Member".
  ///
  /// `my_friends_detailed`, not patch_119's `my_friends` — that one is
  /// already live and read by DirectoryService, and Postgres can't widen
  /// a function's return type without a DROP that would break it.
  static Future<List<FriendSummary>> fetchMyFriends() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    final rows = await _client.rpc('my_friends_detailed');
    if (rows is! List) return const [];
    return rows
        .map((r) => FriendSummary.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  static Future<Friendship> sendRequest(String addresseeId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to send a friend request.');
    }
    if (user.id == addresseeId) {
      throw ArgumentError('Cannot friend yourself.');
    }
    // Idempotent server-side handling (patch_088): accepts an incoming
    // request, re-opens a declined one, and never creates reverse
    // duplicates — instead of a blind insert that failed with
    // "could not send" when any row already existed.
    final row = await _client
        .rpc('send_friend_request', params: {'p_addressee': addresseeId});
    final map = row is List ? (row.first as Map) : (row as Map);
    _noteFriendshipChange();
    return Friendship.fromJson(Map<String, dynamic>.from(map));
  }

  /// Accept a pending friend request. Beyond flipping `status` to
  /// 'accepted' this also seeds an empty conversation between the
  /// two users so the chat lands in both inboxes immediately — the
  /// user's spec: "once you accept a friend request that chat
  /// should get to your inbox." The notification to the requester
  /// ("X accepted your friend request") is fired server-side by the
  /// trg_friendships_notify_accepter trigger (patch_033).
  static Future<void> acceptRequest(String friendshipId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to accept friend requests.');
    }
    // Flip the friendship FIRST so the conversation insert's
    // auto-accept trigger sees an accepted friendship and lands the
    // thread in Inbox rather than Requests.
    final updated = await _client
        .from(_friendshipsTable)
        .update({'status': 'accepted'})
        .eq('id', friendshipId)
        .select('requester_id, addressee_id')
        .maybeSingle();
    if (updated == null) return;
    _noteFriendshipChange();
    final requesterId = updated['requester_id']?.toString() ?? '';
    final addresseeId = updated['addressee_id']?.toString() ?? '';
    // We can only seed the conversation if the caller is one of the
    // pair. Defensive — the RLS already ensures this, but skip if
    // somehow not.
    if (user.id != requesterId && user.id != addresseeId) return;
    final otherId = user.id == addresseeId ? requesterId : addresseeId;
    if (otherId.isEmpty) return;

    // Best-effort: open / reuse the conversation row. createConversation
    // is idempotent — it reuses an existing thread between the pair —
    // so this is safe to call even when the chat already exists.
    try {
      final profile = await _client
          .from('profiles')
          .select('full_name')
          .eq('id', otherId)
          .maybeSingle();
      final otherName =
          ((profile?['full_name'] as String?)?.trim().isNotEmpty == true)
              ? (profile!['full_name'] as String).trim()
              : 'Member';
      unawaited(
        MessagingService.createConversation(
          otherUserId: otherId,
          otherUserName: otherName,
          // Empty opener → WhatsApp-style: the conversation row
          // appears in both inboxes but no chat message is written.
        ),
      );
    } catch (_) {
      // Chat seeding is best-effort — the friendship update already
      // succeeded so don't surface a secondary failure.
    }
  }

  static Future<void> declineRequest(String friendshipId) async {
    await _client
        .from(_friendshipsTable)
        .update({'status': 'declined'}).eq('id', friendshipId);
    _noteFriendshipChange();
  }

  static Future<void> removeFriendship(String friendshipId) async {
    await _client.from(_friendshipsTable).delete().eq('id', friendshipId);
    _noteFriendshipChange();
  }
}

/// One row of the Friends screen (patch_177).
class FriendSummary {
  const FriendSummary({
    required this.friendshipId,
    required this.userId,
    required this.fullName,
    this.photoUrl,
    this.churchName,
    this.isVerified = false,
    this.friendsSince,
  });

  final String friendshipId;
  final String userId;
  final String fullName;
  final String? photoUrl;
  final String? churchName;
  final bool isVerified;
  final DateTime? friendsSince;

  factory FriendSummary.fromJson(Map<String, dynamic> json) => FriendSummary(
        friendshipId: (json['friendship_id'] ?? '').toString(),
        userId: (json['user_id'] ?? '').toString(),
        fullName: ((json['full_name'] as String?)?.trim().isNotEmpty == true)
            ? (json['full_name'] as String).trim()
            : 'Member',
        photoUrl: json['photo_url'] as String?,
        churchName: (json['church_name'] as String?)?.trim(),
        isVerified: json['is_verified'] == true,
        friendsSince:
            DateTime.tryParse(json['friends_since']?.toString() ?? '')
                ?.toLocal(),
      );
}

/// Lightweight DTO for a single pending friend request, joined with
/// the requester's profile so the Conversations Requests tab can
/// render a name + photo without a second round-trip.
class PendingFriendRequest {
  const PendingFriendRequest({
    required this.friendshipId,
    required this.requesterId,
    required this.requesterName,
    required this.createdAt,
    this.requesterPhotoUrl,
    this.requesterChurchName,
  });

  final String friendshipId;
  final String requesterId;
  final String requesterName;
  final String? requesterPhotoUrl;
  final String? requesterChurchName;
  final DateTime createdAt;
}
