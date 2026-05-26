import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/friendship_model.dart';
import '../models/post_comment_model.dart';
import '../models/post_model.dart';
import '../models/story_model.dart';

/// All Supabase calls behind the Facebook-style home feed:
///   - posts            (CRUD + likes + comments)
///   - stories          (24h ephemeral)
///   - friendships      (request / accept / decline)
class FeedService {
  FeedService._();

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
  ///   score = recency_decay
  ///         + log(1 + likes + 2*comments) * 0.30   (engagement)
  ///         + viewer-specific jitter (0..0.20)
  ///         + own_post penalty (-1, so your own post sinks)
  ///
  /// After scoring we apply a diversity pass that prevents 3+
  /// consecutive posts from the same author — splits clusters by
  /// pushing later posts down the list.
  static Future<List<Post>> fetchFeed({int limit = 40}) async {
    final viewer = _viewerId;
    // Over-fetch so the re-rank has actual signal to work with.
    final overfetch = limit * 2;
    final response = await _client
        .from(_postsTable)
        .select(
          '*, '
          'profiles!posts_author_id_fkey(id, full_name, profile_photo_url), '
          'post_likes(user_id), '
          'post_comments(id)',
        )
        .order('created_at', ascending: false)
        .limit(overfetch);
    final posts = (response as List)
        .map((row) => Post.fromJson(
              row as Map<String, dynamic>,
              viewerId: viewer,
            ))
        .toList();
    if (viewer == null || posts.length <= 1) {
      return posts.take(limit).toList();
    }
    posts.sort(
      (a, b) => _personalisedScore(b, viewer).compareTo(
        _personalisedScore(a, viewer),
      ),
    );
    return _diversify(posts).take(limit).toList();
  }

  /// Composite ranking score — higher = nearer the top of the feed.
  /// Pure function of post + viewer id; no DB call, no state.
  static double _personalisedScore(Post p, String viewerId) {
    final ageHours =
        DateTime.now().difference(p.createdAt).inHours.toDouble();
    // Smooth decay: 1.0 at 0h, ~0.5 at 24h, ~0.25 at 72h.
    final recency = 1.0 / (1.0 + (ageHours / 24.0));
    final engagement =
        math.log(1 + p.likeCount + (p.commentCount * 2)) * 0.30;
    // Deterministic per-viewer jitter so the order is stable within
    // a session but different between accounts. Two different users
    // looking at the same 40 posts see meaningfully different orders.
    final seed = '${viewerId}_${p.id}'.hashCode.abs();
    final jitter = ((seed % 1000) / 1000.0) * 0.20;
    final ownPenalty = p.authorId == viewerId ? -1.0 : 0.0;
    return recency + engagement + jitter + ownPenalty;
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

  static Future<Post> createPost({
    String? body,
    String? imageUrl,
    PostVisibility visibility = PostVisibility.public,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to post.');
    }
    final cleanBody = body?.trim();
    if ((cleanBody == null || cleanBody.isEmpty) &&
        (imageUrl == null || imageUrl.isEmpty)) {
      throw ArgumentError('Either body or imageUrl must be non-empty.');
    }
    final inserted = await _client
        .from(_postsTable)
        .insert({
          'author_id': user.id,
          if (cleanBody != null && cleanBody.isNotEmpty) 'body': cleanBody,
          if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
          'visibility': visibility == PostVisibility.friendsOnly
              ? 'friends_only'
              : 'public',
        })
        .select(
          '*, '
          'profiles!posts_author_id_fkey(id, full_name, profile_photo_url), '
          'post_likes(user_id), '
          'post_comments(id)',
        )
        .single();
    return Post.fromJson(inserted, viewerId: _viewerId);
  }

  static Future<void> deletePost(String postId) async {
    await _client.from(_postsTable).delete().eq('id', postId);
  }

  /// Body-text search across the feed. Respects visibility via RLS so
  /// friends-only posts are only returned to friends / the author.
  static Future<List<Post>> searchPosts(String query, {int limit = 20}) async {
    final term = query.trim();
    if (term.isEmpty) return const [];
    final response = await _client
        .from(_postsTable)
        .select(
          '*, '
          'profiles!posts_author_id_fkey(id, full_name, profile_photo_url), '
          'post_likes(user_id), '
          'post_comments(id)',
        )
        .ilike('body', '%$term%')
        .order('created_at', ascending: false)
        .limit(limit);
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
          '*, '
          'profiles!posts_author_id_fkey(id, full_name, profile_photo_url), '
          'post_likes(user_id), '
          'post_comments(id)',
        )
        .single();
    return Post.fromJson(updated, viewerId: _viewerId);
  }

  // ---- Likes --------------------------------------------------------

  static Future<void> likePost(String postId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to like.');
    }
    await _client.from(_likesTable).upsert(
      {'post_id': postId, 'user_id': user.id},
      onConflict: 'post_id,user_id',
      ignoreDuplicates: true,
    );
  }

  static Future<void> unlikePost(String postId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from(_likesTable)
        .delete()
        .eq('post_id', postId)
        .eq('user_id', user.id);
  }

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
          'profiles!post_comments_author_id_fkey(id, full_name, profile_photo_url), '
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
          'profiles!post_comments_author_id_fkey(id, full_name, profile_photo_url), '
          'post_comment_reactions(user_id, value)',
        )
        .single();
    return PostComment.fromJson(inserted, viewerId: _viewerId);
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
          'profiles!stories_author_id_fkey(id, full_name, profile_photo_url)',
        )
        .gt('expires_at', nowIso)
        .order('created_at', ascending: false)
        .limit(200);
    return (response as List)
        .map((row) => Story.fromJson(row as Map<String, dynamic>))
        .where((s) => !s.isExpired)
        .toList();
  }

  static Future<Story> createStory({
    required String mediaUrl,
    String? caption,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to post a story.');
    }
    final inserted = await _client
        .from(_storiesTable)
        .insert({
          'author_id': user.id,
          'media_url': mediaUrl,
          if (caption != null && caption.trim().isNotEmpty)
            'caption': caption.trim(),
        })
        .select(
          '*, '
          'profiles!stories_author_id_fkey(id, full_name, profile_photo_url)',
        )
        .single();
    return Story.fromJson(inserted);
  }

  /// Delete a story. RLS gates this to the author only (per the
  /// stories_delete_author policy created in schema.sql); failures
  /// throw a PostgrestException the caller can surface.
  static Future<void> deleteStory(String storyId) async {
    await _client.from(_storiesTable).delete().eq('id', storyId);
  }

  /// Record that the current viewer has watched [storyId]. Idempotent
  /// — re-watching the same story is a no-op (PK collision on the
  /// (story_id, viewer_id) pair is silently swallowed). Authors
  /// don't get marked as viewing their own stories.
  static Future<void> markStoryViewed(String storyId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
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

  // ===================================================================
  // FRIENDSHIPS
  // ===================================================================

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
    final rows = await _client
        .from(_friendshipsTable)
        .select('id, requester_id, created_at')
        .eq('addressee_id', user.id)
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return const [];

    final requesterIds = list
        .map((r) => (r['requester_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    Map<String, Map<String, dynamic>> profilesById = const {};
    if (requesterIds.isNotEmpty) {
      try {
        final profileRows = await _client
            .from('profiles')
            .select('id, full_name, profile_photo_url, church_name')
            .inFilter('id', requesterIds);
        profilesById = {
          for (final row in (profileRows as List).cast<Map<String, dynamic>>())
            row['id'].toString(): row,
        };
      } catch (_) {
        // If the profiles table isn't readable for some reason (RLS),
        // we still want the requests to surface — just without the
        // pretty name + photo.
      }
    }

    return list.map((r) {
      final requesterId = (r['requester_id'] ?? '').toString();
      final profile = profilesById[requesterId];
      final name = (profile?['full_name'] as String?)?.trim();
      return PendingFriendRequest(
        friendshipId: r['id'].toString(),
        requesterId: requesterId,
        requesterName: (name == null || name.isEmpty) ? 'Member' : name,
        requesterPhotoUrl: profile?['profile_photo_url'] as String?,
        requesterChurchName: profile?['church_name'] as String?,
        createdAt: r['created_at'] != null
            ? (DateTime.tryParse(r['created_at'].toString()) ??
                DateTime.now())
            : DateTime.now(),
      );
    }).toList();
  }

  static Future<Friendship> sendRequest(String addresseeId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to send a friend request.');
    }
    if (user.id == addresseeId) {
      throw ArgumentError('Cannot friend yourself.');
    }
    final inserted = await _client
        .from(_friendshipsTable)
        .insert({
          'requester_id': user.id,
          'addressee_id': addresseeId,
          'status': 'pending',
        })
        .select()
        .single();
    return Friendship.fromJson(inserted);
  }

  static Future<void> acceptRequest(String friendshipId) async {
    await _client
        .from(_friendshipsTable)
        .update({'status': 'accepted'}).eq('id', friendshipId);
  }

  static Future<void> declineRequest(String friendshipId) async {
    await _client
        .from(_friendshipsTable)
        .update({'status': 'declined'}).eq('id', friendshipId);
  }

  static Future<void> removeFriendship(String friendshipId) async {
    await _client.from(_friendshipsTable).delete().eq('id', friendshipId);
  }
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
