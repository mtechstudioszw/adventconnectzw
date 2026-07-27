/// A community post from the home feed. Permanent unless the author
/// deletes it. Mirrors public.posts (patch_011 + patch_012 visibility).
enum PostVisibility { public, friendsOnly }

/// How a viewer responded to a post.
///
/// A plain heart is a secular gesture; this community reaches for "Amen" and
/// "I'm praying". Stored in `post_likes.reaction` — the composite
/// (post_id, user_id) primary key means one reaction per person per post, so
/// picking a new one replaces the old.
enum PostReaction { like, amen, praying }

extension PostReactionX on PostReaction {
  String get wire => switch (this) {
        PostReaction.like => 'like',
        PostReaction.amen => 'amen',
        PostReaction.praying => 'praying',
      };

  String get label => switch (this) {
        PostReaction.like => 'Like',
        PostReaction.amen => 'Amen',
        PostReaction.praying => 'Praying',
      };

  static PostReaction? fromWire(String? value) => switch (value) {
        'like' => PostReaction.like,
        'amen' => PostReaction.amen,
        'praying' => PostReaction.praying,
        _ => null,
      };
}

/// Sentinel so `copyWith` can distinguish "leave unchanged" from "set null".
const Object _unset = Object();

class Post {
  const Post({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.createdAt,
    this.authorPhotoUrl,
    this.authorIsVerified = false,
    this.churchId,
    this.churchName,
    this.churchPhotoUrl,
    this.body,
    this.imageUrl,
    this.imageUrls = const [],
    this.visibility = PostVisibility.public,
    this.likeCount = 0,
    this.commentCount = 0,
    this.viewerReaction,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String? authorPhotoUrl;

  /// Cosmetic gold tick (super admin / approved church admin, patch_134).
  final bool authorIsVerified;

  /// When set, this post is branded as a church update (patch_141) — shows the
  /// church's name + gold tick instead of the individual author.
  final String? churchId;
  final String? churchName;

  /// The church's logo (profile photo). Replaces the church icon on church
  /// posts once an admin uploads it.
  final String? churchPhotoUrl;

  bool get isChurchPost => (churchName ?? '').trim().isNotEmpty;
  final String? body;

  /// First photo. Kept authoritative even for multi-photo posts, because
  /// `posts_check` requires `body IS NOT NULL OR image_url IS NOT NULL`, and
  /// because clients still on v1.3.0 only know about this column.
  final String? imageUrl;

  /// Every photo on the post, first-first. Falls back to `[imageUrl]` for
  /// rows written before the `image_urls` column existed.
  final List<String> imageUrls;

  final PostVisibility visibility;
  final DateTime createdAt;

  /// Total reactions of every kind.
  final int likeCount;
  final int commentCount;

  /// The viewer's own reaction, or null if they haven't reacted.
  final PostReaction? viewerReaction;

  /// True when the viewer reacted at all, whichever kind. Kept so the
  /// profile screens' like toggles keep reading naturally.
  bool get viewerLiked => viewerReaction != null;

  Post copyWith({
    int? likeCount,
    int? commentCount,
    Object? viewerReaction = _unset,
  }) {
    return Post(
      id: id,
      authorId: authorId,
      authorName: authorName,
      authorPhotoUrl: authorPhotoUrl,
      authorIsVerified: authorIsVerified,
      churchId: churchId,
      churchName: churchName,
      churchPhotoUrl: churchPhotoUrl,
      body: body,
      imageUrl: imageUrl,
      imageUrls: imageUrls,
      visibility: visibility,
      createdAt: createdAt,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      viewerReaction: identical(viewerReaction, _unset)
          ? this.viewerReaction
          : viewerReaction as PostReaction?,
    );
  }

  factory Post.fromJson(
    Map<String, dynamic> json, {
    String? viewerId,
  }) {
    final author = json['profiles'];
    final authorMap = author is Map<String, dynamic> ? author : null;

    final likesRaw = json['post_likes'];
    int likeCount = 0;
    PostReaction? viewerReaction;
    if (likesRaw is List) {
      likeCount = likesRaw.length;
      if (viewerId != null) {
        for (final row in likesRaw) {
          if (row is Map<String, dynamic> &&
              row['user_id']?.toString() == viewerId) {
            // Rows written before the reaction column default to 'like'.
            viewerReaction =
                PostReactionX.fromWire(row['reaction']?.toString()) ??
                    PostReaction.like;
            break;
          }
        }
      }
    } else if (likesRaw is Map<String, dynamic>) {
      // Aggregated count form from the offline cache:
      // { count, viewer_reaction }. The viewer's own reaction MUST be
      // restored here — without it, a cache-first paint showed every post as
      // unreacted until the network embed landed, so a reaction the user just
      // made "forgot" itself for a few seconds on the next load.
      likeCount = (likesRaw['count'] as int?) ?? 0;
      viewerReaction =
          PostReactionX.fromWire(likesRaw['viewer_reaction']?.toString());
      // Back-compat with caches written before reactions existed.
      if (viewerReaction == null && likesRaw['viewer_liked'] == true) {
        viewerReaction = PostReaction.like;
      }
    }

    final commentsRaw = json['post_comments'];
    int commentCount = 0;
    if (commentsRaw is List) {
      commentCount = commentsRaw.length;
    } else if (commentsRaw is Map<String, dynamic>) {
      commentCount = (commentsRaw['count'] as int?) ?? 0;
    }

    final firstImage = json['image_url'] as String?;
    final rawUrls = json['image_urls'];
    final images = <String>[
      if (rawUrls is List)
        for (final u in rawUrls)
          if (u != null && u.toString().trim().isNotEmpty) u.toString(),
    ];
    if (images.isEmpty && (firstImage ?? '').trim().isNotEmpty) {
      images.add(firstImage!);
    }

    final visibilityStr = (json['visibility'] ?? 'public').toString();
    return Post(
      id: json['id'].toString(),
      authorId: (json['author_id'] ?? '').toString(),
      authorName: (authorMap?['full_name'] as String?) ?? 'Member',
      authorPhotoUrl: authorMap?['profile_photo_url'] as String?,
      authorIsVerified: authorMap?['is_verified'] == true ||
          authorMap?['is_verified_admin'] == true,
      churchId: json['church_id']?.toString(),
      churchName: (json['churches'] is Map<String, dynamic>)
          ? (json['churches'] as Map<String, dynamic>)['name'] as String?
          : json['church_name'] as String?,
      churchPhotoUrl: (json['churches'] is Map<String, dynamic>)
          ? (json['churches'] as Map<String, dynamic>)['profile_photo_url']
              as String?
          : json['church_photo_url'] as String?,
      body: json['body'] as String?,
      imageUrl: firstImage ?? (images.isEmpty ? null : images.first),
      imageUrls: images,
      visibility: visibilityStr == 'friends_only'
          ? PostVisibility.friendsOnly
          : PostVisibility.public,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      likeCount: likeCount,
      commentCount: commentCount,
      viewerReaction: viewerReaction,
    );
  }

  /// Round-trip JSON for offline cache. The wire format from Supabase
  /// uses joined sub-objects (`profiles`, `post_likes`, `post_comments`)
  /// — we collapse those into simple counts + a fake `profiles` map so
  /// `fromJson` can re-hydrate without special-casing cached payloads.
  Map<String, dynamic> toJson() => {
        'id': id,
        'author_id': authorId,
        'profiles': {
          'full_name': authorName,
          'profile_photo_url': authorPhotoUrl,
          'is_verified_admin': authorIsVerified,
        },
        'church_id': churchId,
        if (churchName != null) 'church_name': churchName,
        'body': body,
        'image_url': imageUrl,
        'image_urls': imageUrls,
        'visibility': visibility == PostVisibility.friendsOnly
            ? 'friends_only'
            : 'public',
        'created_at': createdAt.toIso8601String(),
        // Aggregate form so fromJson reads counts from the
        // { count, viewer_reaction } branch. The viewer's reaction is
        // persisted so the cache-first paint keeps it filled in.
        'post_likes': {
          'count': likeCount,
          'viewer_reaction': viewerReaction?.wire,
        },
        'post_comments': {'count': commentCount},
      };
}
