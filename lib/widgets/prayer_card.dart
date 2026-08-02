import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/prayer_model.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';
import 'verified_tick.dart';
import 'motion/pressable.dart';

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
    this.onToggleAnswered,
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

  /// Owner-only "mark answered" / "mark unanswered". Null for non-owners.
  /// Only the author can say a prayer was answered — nobody else is in a
  /// position to know.
  final VoidCallback? onToggleAnswered;

  @override
  Widget build(BuildContext context) {
    final answered = prayer.isAnswered;
    return PressEffect(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            clipBehavior: Clip.antiAlias,
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
            // Stack, NOT a Row with CrossAxisAlignment.stretch. A stretched
            // Row hands its own cross-axis extent to its children as a TIGHT
            // constraint, and inside a ListView that extent is infinite — so
            // every card threw "BoxConstraints forces an infinite height"
            // during layout and the whole prayer list painted nothing. Here
            // the content is the only unpositioned child, so it sizes the
            // card, and the rail stretches to whatever height that turns out
            // to be. No IntrinsicHeight — this is a scrolling list.
            child: Stack(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(answered ? 13 : 16, 16, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeaderRow(context),
                      const SizedBox(height: 12),
                      Text(
                        prayer.content,
                        maxLines: answered ? 3 : 4,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: context.palette.text,
                          fontSize: 14.5,
                          height: 1.5,
                          // The request is context once it's answered;
                          // the testimony below is the headline.
                          fontStyle:
                              answered ? FontStyle.italic : FontStyle.normal,
                        ),
                      ),
                      if (answered && prayer.testimony != null) ...[
                        const SizedBox(height: 10),
                        _buildTestimony(context, prayer.testimony!),
                      ],
                      const SizedBox(height: 14),
                      _buildActionRow(context),
                      ?_buildPrayedBySummary(context),
                    ],
                  ),
                ),
                // Answered prayers carry a green rail down the left edge —
                // the one visual that reads as "this one resolved" while
                // scrolling, before any text is parsed.
                if (answered)
                  const Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 3,
                    child: ColoredBox(color: AppColors.successGreen),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderRow(BuildContext context) {
    return Row(
      children: [
        _AuthorTapTarget(
          onTap: onAuthorTap,
          child: PrayerAvatar(
            name: prayer.authorName,
            photoUrl: prayer.authorPhotoUrl,
            size: 42,
            anonymous: prayer.isAnonymous,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _AuthorTapTarget(
            onTap: onAuthorTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        prayer.authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (prayer.authorIsVerified) const VerifiedTick(size: 14),
                    const SizedBox(width: 6),
                    // Category and answered-state read as one row of
                    // metadata beside the name, so the card announces what
                    // kind of prayer it is without spending a line on it.
                    if (prayer.isAnswered)
                      const _MetaChip(
                        label: 'ANSWERED',
                        tint: AppColors.successGreen,
                      )
                    else
                      _MetaChip(
                        label: prayer.category.label.toUpperCase(),
                        tint: context.palette.textMuted,
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  // Once answered, "when" means when it was answered.
                  prayer.isAnswered && prayer.answeredAt != null
                      ? 'Answered ${formatTimeAgo(prayer.answeredAt!)}'
                      : formatTimeAgo(prayer.createdAt),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: context.palette.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (onDelete != null || onEdit != null)
          _OwnerMenu(
            onEdit: onEdit,
            onDelete: onDelete,
            onToggleAnswered: onToggleAnswered,
            isAnswered: prayer.isAnswered,
          ),
      ],
    );
  }

  Widget _buildTestimony(BuildContext context, String testimony) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.successGreen.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.auto_awesome,
            size: 15,
            color: AppColors.successGreen,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              testimony,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyMedium.copyWith(
                color: context.palette.text,
                fontSize: 13.5,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow(BuildContext context) {
    return Row(
      children: [
        // "I prayed" is the primary action and takes the width — a
        // prayer request exists to be prayed for, so the button that
        // does that shouldn't be the same size as the comment count.
        Expanded(
          child: PrayingButton(
            isPraying: isPraying,
            busy: busy,
            count: prayer.prayerCount,
            onTap: onTogglePray,
            expanded: true,
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: context.palette.chipBg,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 14,
                color: context.palette.textMuted,
              ),
              const SizedBox(width: 5),
              Text(
                '${prayer.commentCount}',
                style: AppTextStyles.labelSmall.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// "Rutendo, Blessing and 41 others prayed" — the whole reason someone
  /// posts a request is to learn they weren't shouting into a void. A
  /// bare count can't carry that. Null (and the row disappears) until the
  /// batch name load resolves, or when nobody has prayed yet.
  Widget? _buildPrayedBySummary(BuildContext context) {
    final summary = prayer.prayedBySummary();
    if (summary == null) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          _PrayedByFaces(people: prayer.prayedBy),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall.copyWith(
                color: context.palette.textMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small uppercase pill for category / ANSWERED beside the author name.
class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.tint});

  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: tint,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Overlapping avatars of the first people who prayed. Caps at two —
/// beyond that the names in the summary do the work and more circles
/// just cost width.
class _PrayedByFaces extends StatelessWidget {
  const _PrayedByFaces({required this.people});

  final List<PrayingUserRef> people;

  @override
  Widget build(BuildContext context) {
    final shown = people.take(2).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    const size = 18.0;
    return SizedBox(
      width: size + (shown.length - 1) * (size * 0.65),
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * (size * 0.65),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: context.palette.card, width: 1.5),
                ),
                child: PrayerAvatar(
                  name: shown[i].fullName,
                  photoUrl: shown[i].photoUrl,
                  size: size,
                ),
              ),
            ),
        ],
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
    this.anonymous = false,
  });

  final String name;

  /// Profile photo to render. When null/empty (or anonymous prayer)
  /// the avatar falls back to a gradient circle with initials.
  final String? photoUrl;
  final double size;

  /// Anonymous posts get a neutral masked avatar rather than an "A" from
  /// the literal name "Anonymous" — an initial implies an identity, which
  /// is exactly what anonymity is meant to withhold.
  final bool anonymous;

  String _initials() {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (anonymous) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.textMuted.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.visibility_off_outlined,
          size: size * 0.46,
          color: AppColors.textMuted,
        ),
      );
    }
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
  const _OwnerMenu({
    this.onEdit,
    this.onDelete,
    this.onToggleAnswered,
    this.isAnswered = false,
  });

  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleAnswered;
  final bool isAnswered;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_horiz, color: AppColors.textMuted),
      onSelected: (value) {
        if (value == 'edit') onEdit?.call();
        if (value == 'delete') onDelete?.call();
        if (value == 'answered') onToggleAnswered?.call();
      },
      itemBuilder: (ctx) => [
        if (onToggleAnswered != null)
          PopupMenuItem<String>(
            value: 'answered',
            child: Row(
              children: [
                Icon(
                  isAnswered
                      ? Icons.remove_done_rounded
                      : Icons.auto_awesome_outlined,
                  color: AppColors.successGreen,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  isAnswered ? 'Mark unanswered' : 'Mark answered',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: ctx.palette.text,
                  ),
                ),
              ],
            ),
          ),
        if (onEdit != null)
          PopupMenuItem<String>(
            value: 'edit',
            child: Row(
              children: [
                const Icon(
                  Icons.edit_outlined,
                  color: AppColors.primaryBlue,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Edit',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: AppColors.text,
                  ),
                ),
              ],
            ),
          ),
        if (onDelete != null)
          PopupMenuItem<String>(
            value: 'delete',
            child: Row(
              children: [
                const Icon(
                  Icons.delete_outline,
                  color: AppColors.red,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Delete',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: AppColors.red,
                  ),
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
    this.expanded = false,
  });

  final bool isPraying;
  final bool busy;
  final int count;
  final VoidCallback onTap;

  /// Fills the width and centres its label — how the list card renders it,
  /// where "I prayed" is the primary action. The details screen keeps the
  /// compact intrinsic-width form.
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final filled = isPraying;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(expanded ? 100 : 12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: expanded ? 10 : 8,
          ),
          decoration: BoxDecoration(
            gradient: filled ? AppColors.primaryGradient : null,
            color: filled
                ? null
                : AppColors.primaryBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(expanded ? 100 : 12),
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
            mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment:
                expanded ? MainAxisAlignment.center : MainAxisAlignment.start,
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
                  // Praying, not liking — hands, never a heart.
                  filled
                      ? Icons.volunteer_activism
                      : Icons.volunteer_activism_outlined,
                  size: 16,
                  color: filled ? AppColors.white : AppColors.primaryBlue,
                ),
              const SizedBox(width: 6),
              Text(
                filled ? 'You prayed  •  $count' : 'I prayed  •  $count',
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
