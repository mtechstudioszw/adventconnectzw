/// A comment on a feed post. Mirrors public.post_comments (patch_011).
class PostComment {
  const PostComment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.authorName,
    required this.body,
    required this.createdAt,
    this.authorPhotoUrl,
  });

  final String id;
  final String postId;
  final String authorId;
  final String authorName;
  final String? authorPhotoUrl;
  final String body;
  final DateTime createdAt;

  factory PostComment.fromJson(Map<String, dynamic> json) {
    final author = json['profiles'];
    final authorMap = author is Map<String, dynamic> ? author : null;
    return PostComment(
      id: json['id'].toString(),
      postId: (json['post_id'] ?? '').toString(),
      authorId: (json['author_id'] ?? '').toString(),
      authorName: (authorMap?['full_name'] as String?) ?? 'Member',
      authorPhotoUrl: authorMap?['profile_photo_url'] as String?,
      body: (json['body'] ?? '') as String,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
