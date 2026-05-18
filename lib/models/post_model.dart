/// A community post from the home feed. Permanent unless the author
/// deletes it. Mirrors public.posts (patch_011).
class Post {
  const Post({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.createdAt,
    this.authorPhotoUrl,
    this.body,
    this.imageUrl,
    this.likeCount = 0,
    this.commentCount = 0,
    this.viewerLiked = false,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String? authorPhotoUrl;
  final String? body;
  final String? imageUrl;
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
      body: body,
      imageUrl: imageUrl,
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
      // Aggregated count form: { count: N }.
      likeCount = (likesRaw['count'] as int?) ?? 0;
    }

    final commentsRaw = json['post_comments'];
    int commentCount = 0;
    if (commentsRaw is List) {
      commentCount = commentsRaw.length;
    } else if (commentsRaw is Map<String, dynamic>) {
      commentCount = (commentsRaw['count'] as int?) ?? 0;
    }

    return Post(
      id: json['id'].toString(),
      authorId: (json['author_id'] ?? '').toString(),
      authorName: (authorMap?['full_name'] as String?) ?? 'Member',
      authorPhotoUrl: authorMap?['profile_photo_url'] as String?,
      body: json['body'] as String?,
      imageUrl: json['image_url'] as String?,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      likeCount: likeCount,
      commentCount: commentCount,
      viewerLiked: viewerLiked,
    );
  }
}
