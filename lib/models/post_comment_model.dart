/// A comment on a feed post. Mirrors public.post_comments (patch_011),
/// extended with threading + like/dislike in patch_017:
///   - parent_comment_id  → top-level vs reply
///   - post_comment_reactions(value)
///       +1 = like, -1 = dislike (per voter, per comment)
class PostComment {
  const PostComment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.authorName,
    required this.body,
    required this.createdAt,
    this.authorPhotoUrl,
    this.authorIsVerified = false,
    this.parentCommentId,
    this.likeCount = 0,
    this.dislikeCount = 0,
    this.viewerVote = 0,
    this.replies = const [],
  });

  final String id;
  final String postId;
  final String authorId;
  final String authorName;
  final String? authorPhotoUrl;
  final bool authorIsVerified;
  final String body;
  final DateTime createdAt;
  final String? parentCommentId;
  final int likeCount;
  final int dislikeCount;

  /// -1 = the viewer disliked, 0 = no vote, +1 = the viewer liked.
  final int viewerVote;

  /// Populated by [PostComment.buildTree] — direct children only.
  /// The UI flattens any deeper nesting into this same list.
  final List<PostComment> replies;

  bool get isReply => parentCommentId != null;

  PostComment copyWith({
    int? likeCount,
    int? dislikeCount,
    int? viewerVote,
    List<PostComment>? replies,
  }) {
    return PostComment(
      id: id,
      postId: postId,
      authorId: authorId,
      authorName: authorName,
      authorPhotoUrl: authorPhotoUrl,
      authorIsVerified: authorIsVerified,
      body: body,
      createdAt: createdAt,
      parentCommentId: parentCommentId,
      likeCount: likeCount ?? this.likeCount,
      dislikeCount: dislikeCount ?? this.dislikeCount,
      viewerVote: viewerVote ?? this.viewerVote,
      replies: replies ?? this.replies,
    );
  }

  factory PostComment.fromJson(
    Map<String, dynamic> json, {
    String? viewerId,
  }) {
    final author = json['profiles'];
    final authorMap = author is Map<String, dynamic> ? author : null;

    int likeCount = 0;
    int dislikeCount = 0;
    int viewerVote = 0;
    final reactionsRaw = json['post_comment_reactions'];
    if (reactionsRaw is List) {
      for (final r in reactionsRaw) {
        if (r is! Map) continue;
        final value = (r['value'] is num) ? (r['value'] as num).toInt() : 0;
        if (value == 1) {
          likeCount += 1;
        } else if (value == -1) {
          dislikeCount += 1;
        }
        if (viewerId != null && r['user_id']?.toString() == viewerId) {
          viewerVote = value;
        }
      }
    }

    return PostComment(
      id: json['id'].toString(),
      postId: (json['post_id'] ?? '').toString(),
      authorId: (json['author_id'] ?? '').toString(),
      authorName: (authorMap?['full_name'] as String?) ?? 'Member',
      authorPhotoUrl: authorMap?['profile_photo_url'] as String?,
      authorIsVerified: authorMap?['is_verified'] == true ||
          authorMap?['is_verified_admin'] == true,
      body: (json['body'] ?? '') as String,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      parentCommentId: json['parent_comment_id']?.toString(),
      likeCount: likeCount,
      dislikeCount: dislikeCount,
      viewerVote: viewerVote,
    );
  }

  /// Re-shape a flat comment list into a 1-level tree:
  ///   top-level comments stay in order; every reply (parent_comment_id
  ///   not null) is grouped under its top-level ancestor's `replies`.
  /// Deeper nesting is flattened — replies-to-replies show up next to
  /// their sibling replies, which matches how the user thinks about it.
  static List<PostComment> buildTree(List<PostComment> flat) {
    final byId = {for (final c in flat) c.id: c};
    final repliesByRoot = <String, List<PostComment>>{};
    final roots = <PostComment>[];

    String? rootIdOf(PostComment c) {
      var cursor = c;
      var hops = 0;
      while (cursor.parentCommentId != null && hops < 16) {
        final parent = byId[cursor.parentCommentId];
        if (parent == null) return null;
        if (parent.parentCommentId == null) return parent.id;
        cursor = parent;
        hops += 1;
      }
      return null;
    }

    for (final c in flat) {
      if (c.parentCommentId == null) {
        roots.add(c);
      } else {
        final root = rootIdOf(c);
        if (root == null) {
          // Parent missing (deleted?) — treat as top level.
          roots.add(c);
        } else {
          repliesByRoot.putIfAbsent(root, () => []).add(c);
        }
      }
    }

    return roots
        .map((r) => r.copyWith(replies: repliesByRoot[r.id] ?? const []))
        .toList();
  }
}
