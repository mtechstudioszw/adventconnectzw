import 'package:flutter/material.dart';
import '../../models/post_comment_model.dart';
import '../../services/feed_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../cached_image.dart';

/// Bottom sheet that opens when the user taps "Comment" on a feed post.
/// Loads comments lazily and lets the viewer post a new one, reply to
/// an existing one, and react with like / dislike. The parent receives
/// the total count (top-level + replies) via [onCommentCountChanged]
/// so it can update its in-memory Post without a refetch.
Future<void> showCommentsSheet(
  BuildContext context, {
  required String postId,
  required void Function(int newCommentCount) onCommentCountChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _CommentsSheet(
      postId: postId,
      onCommentCountChanged: onCommentCountChanged,
    ),
  );
}

class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({
    required this.postId,
    required this.onCommentCountChanged,
  });

  final String postId;
  final void Function(int newCommentCount) onCommentCountChanged;

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _controller = TextEditingController();
  final _composerFocus = FocusNode();
  List<PostComment> _flat = [];
  List<PostComment> _tree = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  // When the viewer taps "Reply" on a comment, we stash the target
  // here so the next send becomes a reply rather than a top-level
  // comment. Cleared after a successful send or when the user taps
  // the "X" in the reply chip.
  PostComment? _replyTo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await FeedService.fetchComments(widget.postId);
      if (!mounted) return;
      setState(() {
        _flat = list;
        _tree = PostComment.buildTree(list);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load comments.';
        _loading = false;
      });
    }
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final created = await FeedService.addComment(
        postId: widget.postId,
        body: body,
        parentCommentId: _replyTo?.id,
      );
      if (!mounted) return;
      final newFlat = [..._flat, created];
      setState(() {
        _flat = newFlat;
        _tree = PostComment.buildTree(newFlat);
        _controller.clear();
        _replyTo = null;
        _sending = false;
      });
      widget.onCommentCountChanged(newFlat.length);
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      _toast('Could not post comment. Try again.');
    }
  }

  Future<void> _react(PostComment comment, int next) async {
    // Tapping the same vote again withdraws it (Reddit-style toggle).
    final value = comment.viewerVote == next ? 0 : next;
    int likeDelta = 0;
    int dislikeDelta = 0;
    if (comment.viewerVote == 1) likeDelta -= 1;
    if (comment.viewerVote == -1) dislikeDelta -= 1;
    if (value == 1) likeDelta += 1;
    if (value == -1) dislikeDelta += 1;

    final updated = comment.copyWith(
      viewerVote: value,
      likeCount: (comment.likeCount + likeDelta).clamp(0, 1 << 30),
      dislikeCount: (comment.dislikeCount + dislikeDelta).clamp(0, 1 << 30),
    );
    setState(() {
      _flat = _flat.map((c) => c.id == comment.id ? updated : c).toList();
      _tree = PostComment.buildTree(_flat);
    });

    try {
      await FeedService.reactToComment(
        commentId: comment.id,
        value: value,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _flat = _flat.map((c) => c.id == comment.id ? comment : c).toList();
        _tree = PostComment.buildTree(_flat);
      });
      _toast('Could not save your vote. Try again.');
    }
  }

  void _startReply(PostComment target) {
    setState(() => _replyTo = target);
    _composerFocus.requestFocus();
  }

  void _cancelReply() {
    setState(() => _replyTo = null);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) {
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(26, 26, 46, 0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Comments',
                  style: AppTextStyles.titleLarge.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                const Divider(height: 24),
                Expanded(child: _buildList(scrollController)),
                if (_replyTo != null) _buildReplyBanner(),
                const Divider(height: 1),
                _buildComposer(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildList(ScrollController controller) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryBlue),
      );
    }
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.red),
        ),
      );
    }
    if (_tree.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Be the first to comment.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.55),
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      controller: controller,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: _tree.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (ctx, i) {
        final root = _tree[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CommentRow(
              comment: root,
              onReply: () => _startReply(root),
              onLike: () => _react(root, 1),
              onDislike: () => _react(root, -1),
            ),
            if (root.replies.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 30, top: 10),
                child: Column(
                  children: [
                    for (final reply in root.replies) ...[
                      _CommentRow(
                        comment: reply,
                        onReply: () => _startReply(root),
                        onLike: () => _react(reply, 1),
                        onDislike: () => _react(reply, -1),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildReplyBanner() {
    final target = _replyTo!;
    return Container(
      color: AppColors.primaryBlue.withValues(alpha: 0.06),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          const Icon(
            Icons.subdirectory_arrow_right,
            size: 16,
            color: AppColors.primaryBlue,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Replying to ${target.authorName}',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: _cancelReply,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.close,
                size: 16,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.lightGrey,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: const Color.fromRGBO(26, 26, 46, 0.06),
                  ),
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: _composerFocus,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  style: AppTextStyles.bodyMedium.copyWith(fontSize: 14.5),
                  decoration: InputDecoration(
                    hintText: _replyTo == null
                        ? 'Write a comment…'
                        : 'Write a reply…',
                    hintStyle: AppTextStyles.bodyMedium.copyWith(
                      color: const Color.fromRGBO(26, 26, 46, 0.45),
                      fontSize: 14.5,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed:
                    _sending || _controller.text.trim().isEmpty ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.white,
                        ),
                      )
                    : const Icon(
                        Icons.send,
                        color: AppColors.white,
                        size: 18,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({
    required this.comment,
    required this.onReply,
    required this.onLike,
    required this.onDislike,
  });

  final PostComment comment;
  final VoidCallback onReply;
  final VoidCallback onLike;
  final VoidCallback onDislike;

  @override
  Widget build(BuildContext context) {
    final url = comment.authorPhotoUrl;
    final initial = comment.authorName.trim().isEmpty
        ? '?'
        : comment.authorName.trim().substring(0, 1).toUpperCase();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.primaryGradient,
          ),
          alignment: Alignment.center,
          child: url == null || url.isEmpty
              ? Text(
                  initial,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                )
              : CachedImage(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Text(
                    initial,
                    style: AppTextStyles.titleMedium.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.lightGrey,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comment.authorName,
                      style: AppTextStyles.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      comment.body,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Row(
                  children: [
                    _VoteButton(
                      icon: comment.viewerVote == 1
                          ? Icons.thumb_up
                          : Icons.thumb_up_outlined,
                      count: comment.likeCount,
                      highlighted: comment.viewerVote == 1,
                      onTap: onLike,
                    ),
                    const SizedBox(width: 14),
                    _VoteButton(
                      icon: comment.viewerVote == -1
                          ? Icons.thumb_down
                          : Icons.thumb_down_outlined,
                      count: comment.dislikeCount,
                      highlighted: comment.viewerVote == -1,
                      onTap: onDislike,
                    ),
                    const SizedBox(width: 14),
                    GestureDetector(
                      onTap: onReply,
                      child: Text(
                        'Reply',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: const Color.fromRGBO(26, 26, 46, 0.65),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VoteButton extends StatelessWidget {
  const _VoteButton({
    required this.icon,
    required this.count,
    required this.highlighted,
    required this.onTap,
  });

  final IconData icon;
  final int count;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = highlighted
        ? AppColors.primaryBlue
        : const Color.fromRGBO(26, 26, 46, 0.55);
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          if (count > 0) ...[
            const SizedBox(width: 4),
            Text(
              '$count',
              style: AppTextStyles.labelSmall.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
