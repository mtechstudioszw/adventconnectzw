import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/prayer_model.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';

class PrayerCard extends StatelessWidget {
  const PrayerCard({
    super.key,
    required this.prayer,
    required this.isPraying,
    required this.busy,
    required this.onTogglePray,
    required this.onTap,
    this.onAuthorTap,
    this.onEdit,
    this.onDelete,
  });

  final Prayer prayer;
  final bool isPraying;
  final bool busy;
  final VoidCallback onTogglePray;
  final VoidCallback onTap;

  /// Tap on the author's avatar or name. Null for anonymous prayers
  /// (the prayer screen passes null when `prayer.authorId` is empty).
  final VoidCallback? onAuthorTap;

  /// Owner-only edit action. Null for non-owners.
  final VoidCallback? onEdit;

  /// Owner-only delete action. Null for non-owners — the overflow
  /// menu only renders when this is non-null.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.palette.card,
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _AuthorTapTarget(
                    onTap: onAuthorTap,
                    child: PrayerAvatar(
                      name: prayer.authorName,
                      photoUrl: prayer.authorPhotoUrl,
                      size: 42,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _AuthorTapTarget(
                      onTap: onAuthorTap,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            prayer.authorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.titleMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            formatTimeAgo(prayer.createdAt),
                            style: AppTextStyles.bodySmall.copyWith(
                              color: const Color.fromRGBO(26, 26, 46, 0.55),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (onDelete != null || onEdit != null)
                    _OwnerMenu(onEdit: onEdit, onDelete: onDelete),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                prayer.content,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.text,
                  fontSize: 14.5,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  PrayingButton(
                    isPraying: isPraying,
                    busy: busy,
                    count: prayer.prayerCount,
                    onTap: onTogglePray,
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: context.palette.chipBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.chat_bubble_outline,
                          size: 14,
                          color: Color.fromRGBO(26, 26, 46, 0.55),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${prayer.commentCount}',
                          style: AppTextStyles.labelSmall.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: const Color.fromRGBO(26, 26, 46, 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String formatTimeAgo(DateTime then) {
  final diff = DateTime.now().difference(then);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
  return '${(diff.inDays / 30).floor()}mo ago';
}

class PrayerAvatar extends StatelessWidget {
  const PrayerAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.size = 40,
  });

  final String name;

  /// Profile photo to render. When null/empty (or anonymous prayer)
  /// the avatar falls back to a gradient circle with initials.
  final String? photoUrl;
  final double size;

  String _initials() {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final url = photoUrl?.trim();
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          // Show the initials placeholder while the photo loads or
          // if it fails — never flash an empty white circle.
          placeholder: (context, _) => _initialsCircle(),
          errorWidget: (context, _, e) => _initialsCircle(),
        ),
      );
    }
    return _initialsCircle();
  }

  Widget _initialsCircle() {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
        shape: BoxShape.circle,
      ),
      child: Text(
        _initials(),
        style: AppTextStyles.titleMedium.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.34,
        ),
      ),
    );
  }
}

/// Wraps the avatar / name with an InkWell when `onTap` is non-null.
/// Anonymous prayers pass `onTap: null`, so the tap target is inert
/// — the surrounding card's tap still opens the prayer details.
class _AuthorTapTarget extends StatelessWidget {
  const _AuthorTapTarget({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: child,
      ),
    );
  }
}

class _OwnerMenu extends StatelessWidget {
  const _OwnerMenu({this.onEdit, this.onDelete});

  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(
        Icons.more_horiz,
        color: Color.fromRGBO(26, 26, 46, 0.55),
      ),
      onSelected: (value) {
        if (value == 'edit') onEdit?.call();
        if (value == 'delete') onDelete?.call();
      },
      itemBuilder: (ctx) => [
        if (onEdit != null)
          PopupMenuItem<String>(
            value: 'edit',
            child: Row(
              children: [
                const Icon(Icons.edit_outlined,
                    color: AppColors.primaryBlue, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Edit',
                  style: AppTextStyles.labelMedium
                      .copyWith(color: AppColors.text),
                ),
              ],
            ),
          ),
        if (onDelete != null)
          PopupMenuItem<String>(
            value: 'delete',
            child: Row(
              children: [
                const Icon(Icons.delete_outline,
                    color: AppColors.red, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Delete',
                  style:
                      AppTextStyles.labelMedium.copyWith(color: AppColors.red),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class PrayingButton extends StatelessWidget {
  const PrayingButton({
    super.key,
    required this.isPraying,
    required this.busy,
    required this.count,
    required this.onTap,
  });

  final bool isPraying;
  final bool busy;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final filled = isPraying;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            gradient: filled ? AppColors.primaryGradient : null,
            color: filled ? null : AppColors.primaryBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            boxShadow: filled
                ? [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: filled ? AppColors.white : AppColors.primaryBlue,
                  ),
                )
              else
                Icon(
                  filled ? Icons.favorite : Icons.favorite_outline,
                  size: 16,
                  color: filled ? AppColors.white : AppColors.primaryBlue,
                ),
              const SizedBox(width: 6),
              Text(
                filled ? 'Praying  •  $count' : "I'm praying  •  $count",
                style: AppTextStyles.labelMedium.copyWith(
                  color: filled ? AppColors.white : AppColors.primaryBlue,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
