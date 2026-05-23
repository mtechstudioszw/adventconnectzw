import 'package:flutter/material.dart';
import '../../models/post_model.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// One card in the home feed. Stateless — the parent owns the Post and
/// receives optimistic-update callbacks for like/comment/menu taps.
class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.viewerId,
    required this.onLikeToggled,
    required this.onCommentsTapped,
    required this.onImageTapped,
    this.onAuthorTapped,
    this.onEdit,
    this.onDelete,
    this.onToggleVisibility,
    this.onReport,
    this.onSaveImage,
  });

  final Post post;
  final String? viewerId;
  final VoidCallback onLikeToggled;
  final VoidCallback onCommentsTapped;
  final VoidCallback onImageTapped;
  final VoidCallback? onAuthorTapped;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleVisibility;
  final VoidCallback? onReport;
  // Owner menu shows "Save to gallery" when this is wired AND the
  // post actually has an image. Non-owner cards get the same option
  // via the viewer menu.
  final VoidCallback? onSaveImage;

  bool get _isOwner => viewerId != null && viewerId == post.authorId;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          if ((post.body ?? '').isNotEmpty) _buildBody(),
          if ((post.imageUrl ?? '').isNotEmpty) _buildImage(),
          if (post.likeCount > 0 || post.commentCount > 0) _buildCounts(),
          const Divider(height: 1, color: Color.fromRGBO(26, 26, 46, 0.06)),
          _buildActions(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: onAuthorTapped,
            child: _Avatar(
              name: post.authorName,
              photoUrl: post.authorPhotoUrl,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: onAuthorTapped,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          post.authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.titleMedium.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        post.visibility == PostVisibility.friendsOnly
                            ? Icons.people_alt_outlined
                            : Icons.public,
                        size: 12,
                        color: const Color.fromRGBO(26, 26, 46, 0.45),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatTimeAgo(post.createdAt),
                    style: AppTextStyles.labelSmall.copyWith(
                      color: const Color.fromRGBO(26, 26, 46, 0.55),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isOwner)
            _OwnerMenu(
              isFriendsOnly: post.visibility == PostVisibility.friendsOnly,
              onEdit: onEdit,
              onDelete: onDelete,
              onToggleVisibility: onToggleVisibility,
              onSaveImage: (post.imageUrl ?? '').isNotEmpty ? onSaveImage : null,
            )
          else if (onReport != null)
            _ViewerMenu(
              onReport: onReport!,
              onSaveImage: (post.imageUrl ?? '').isNotEmpty ? onSaveImage : null,
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text(
        post.body!,
        style: AppTextStyles.bodyMedium.copyWith(
          color: const Color.fromRGBO(26, 26, 46, 0.88),
          height: 1.45,
          fontSize: 14.5,
        ),
      ),
    );
  }

  Widget _buildImage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: GestureDetector(
        onTap: onImageTapped,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 1.0,
            child: Hero(
              tag: 'post_image_${post.id}',
              child: Image.network(
                post.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: AppColors.lightGrey,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.broken_image_outlined,
                    color: AppColors.primaryBlue,
                  ),
                ),
                loadingBuilder: (ctx, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    color: AppColors.lightGrey,
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(
                      color: AppColors.primaryBlue,
                      strokeWidth: 2,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCounts() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          if (post.likeCount > 0) ...[
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.favorite,
                size: 12,
                color: AppColors.white,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${post.likeCount}',
              style: AppTextStyles.labelSmall.copyWith(
                color: const Color.fromRGBO(26, 26, 46, 0.7),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const Spacer(),
          if (post.commentCount > 0)
            Text(
              post.commentCount == 1
                  ? '1 comment'
                  : '${post.commentCount} comments',
              style: AppTextStyles.labelSmall.copyWith(
                color: const Color.fromRGBO(26, 26, 46, 0.55),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: post.viewerLiked
                ? Icons.favorite
                : Icons.favorite_border,
            label: 'Like',
            highlighted: post.viewerLiked,
            onTap: onLikeToggled,
          ),
        ),
        Expanded(
          child: _ActionButton(
            icon: Icons.mode_comment_outlined,
            label: 'Comment',
            onTap: onCommentsTapped,
          ),
        ),
      ],
    );
  }

  static String _formatTimeAgo(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    final weeks = (diff.inDays / 7).floor();
    if (weeks < 5) return '${weeks}w';
    final months = (diff.inDays / 30).floor();
    if (months < 12) return '${months}mo';
    final years = (diff.inDays / 365).floor();
    return '${years}y';
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.photoUrl});

  final String name;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    final initial = name.trim().isEmpty
        ? '?'
        : name.trim().substring(0, 1).toUpperCase();
    return Container(
      width: 42,
      height: 42,
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
                fontSize: 17,
              ),
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              width: 42,
              height: 42,
              errorBuilder: (_, _, _) => Text(
                initial,
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color = highlighted
        ? AppColors.primaryBlue
        : const Color.fromRGBO(26, 26, 46, 0.7);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppTextStyles.buttonText.copyWith(
                  color: color,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OwnerMenu extends StatelessWidget {
  const _OwnerMenu({
    required this.isFriendsOnly,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleVisibility,
    this.onSaveImage,
  });

  final bool isFriendsOnly;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleVisibility;
  final VoidCallback? onSaveImage;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(
        Icons.more_horiz,
        color: Color.fromRGBO(26, 26, 46, 0.55),
        size: 20,
      ),
      tooltip: 'Manage post',
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit?.call();
            break;
          case 'visibility':
            onToggleVisibility?.call();
            break;
          case 'save':
            onSaveImage?.call();
            break;
          case 'delete':
            onDelete?.call();
            break;
        }
      },
      itemBuilder: (ctx) => [
        if (onEdit != null)
          PopupMenuItem(
            value: 'edit',
            child: Row(
              children: const [
                Icon(Icons.edit_outlined, size: 18,
                    color: AppColors.primaryBlue),
                SizedBox(width: 10),
                Text('Edit post'),
              ],
            ),
          ),
        if (onToggleVisibility != null)
          PopupMenuItem(
            value: 'visibility',
            child: Row(
              children: [
                Icon(
                  isFriendsOnly ? Icons.public : Icons.people_alt_outlined,
                  size: 18,
                  color: AppColors.primaryBlue,
                ),
                const SizedBox(width: 10),
                Text(isFriendsOnly ? 'Make public' : 'Show friends only'),
              ],
            ),
          ),
        if (onSaveImage != null)
          PopupMenuItem(
            value: 'save',
            child: Row(
              children: const [
                Icon(Icons.download_outlined, size: 18,
                    color: AppColors.primaryBlue),
                SizedBox(width: 10),
                Text('Save to gallery'),
              ],
            ),
          ),
        if (onDelete != null)
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: const [
                Icon(Icons.delete_outline, size: 18, color: AppColors.red),
                SizedBox(width: 10),
                Text('Delete post', style: TextStyle(color: AppColors.red)),
              ],
            ),
          ),
      ],
    );
  }
}

class _ViewerMenu extends StatelessWidget {
  const _ViewerMenu({required this.onReport, this.onSaveImage});

  final VoidCallback onReport;
  final VoidCallback? onSaveImage;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(
        Icons.more_horiz,
        color: Color.fromRGBO(26, 26, 46, 0.55),
        size: 20,
      ),
      tooltip: 'More',
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (value) {
        switch (value) {
          case 'save':
            onSaveImage?.call();
            break;
          case 'report':
            onReport();
            break;
        }
      },
      itemBuilder: (ctx) => [
        if (onSaveImage != null)
          PopupMenuItem(
            value: 'save',
            child: Row(
              children: const [
                Icon(Icons.download_outlined, size: 18,
                    color: AppColors.primaryBlue),
                SizedBox(width: 10),
                Text('Save image to gallery'),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'report',
          child: Row(
            children: const [
              Icon(Icons.flag_outlined, size: 18, color: AppColors.red),
              SizedBox(width: 10),
              Text('Report post', style: TextStyle(color: AppColors.red)),
            ],
          ),
        ),
      ],
    );
  }
}
