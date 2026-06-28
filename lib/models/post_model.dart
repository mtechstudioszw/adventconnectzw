/// A community post from the home feed. Permanent unless the author
/// deletes it. Mirrors public.posts (patch_011 + patch_012 visibility).
enum PostVisibility { public, friendsOnly }

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
    this.visibility = PostVisibility.public,
    this.likeCount = 0,
    this.commentCount = 0,
    this.viewerLiked = false,
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
  final String? imageUrl;
  final PostVisibility visibility;
  final DateTime createdAt;
  final int likeCount;
  final int commentCount;
  final bool viewerLiked;

  Post copyWith({
    int? likeCount,
    int? commentCount,
    bool? viewerLiked,
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
      visibility: visibility,
      createdAt: createdAt,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      viewerLiked: viewerLiked ?? this.viewerLiked,
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
    bool viewerLiked = false;
    if (likesRaw is List) {
      likeCount = likesRaw.length;
      if (viewerId != null) {
        viewerLiked = likesRaw.any((row) {
          if (row is Map<String, dynamic>) {
            return row['user_id']?.toString() == viewerId;
          }
          return false;
        });
      }
    } else if (likesRaw is Map<String, dynamic>) {
      // Aggregated count form from the offline cache: { count, viewer_liked }.
      // viewer_liked MUST be restored here — without it, a cache-first
      // paint showed every post as unliked until the network embed
      // landed, so a like the user just made "forgot" itself for a few
      // seconds on the next load.
      likeCount = (likesRaw['count'] as int?) ?? 0;
      viewerLiked = likesRaw['viewer_liked'] == true;
    }

    final commentsRaw = json['post_comments'];
    int commentCount = 0;
    if (commentsRaw is List) {
      commentCount = commentsRaw.length;
    } else if (commentsRaw is Map<String, dynamic>) {
      commentCount = (commentsRaw['count'] as int?) ?? 0;
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
      imageUrl: json['image_url'] as String?,
      visibility: visibilityStr == 'friends_only'
          ? PostVisibility.friendsOnly
          : PostVisibility.public,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      likeCount: likeCount,
      commentCount: commentCount,
      viewerLiked: viewerLiked,
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
        'visibility': visibility == PostVisibility.friendsOnly
            ? 'friends_only'
            : 'public',
        'created_at': createdAt.toIso8601String(),
        // Aggregate form so fromJson reads counts from the
        // { count, viewer_liked } branch. viewer_liked is persisted so
        // the cache-first paint keeps the heart filled for posts the
        // viewer already liked.
        'post_likes': {'count': likeCount, 'viewer_liked': viewerLiked},
        'post_comments': {'count': commentCount},
      };
}
