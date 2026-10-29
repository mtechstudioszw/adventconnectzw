import 'package:flutter/material.dart';

import '../models/job_model.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';
import 'motion/pressable.dart';

/// One vacancy in a list (jobs redesign v2, 28 Oct 2026).
///
/// Read top to bottom the way a job hunter scans: what the job is and who
/// is hiring, then the PAY — the first thing a gardener and an accountant
/// both look for — then the facts people choose by (start now, type,
/// arrangement, Sabbath), then how fresh it is. Pay appears only when the
/// poster gave it; nothing says "Negotiable" on their behalf.
///
/// [compact] is the fixed-height version for horizontal rails (Home,
/// "Start now", Saved): one line of chips, no footer.
class JobCard extends StatelessWidget {
  const JobCard({
    super.key,
    required this.job,
    required this.onTap,
    this.saved,
    this.onToggleSave,
    this.applied = false,
    this.compact = false,
  });

  final Job job;
  final VoidCallback onTap;

  /// Null hides the bookmark.
  final bool? saved;
  final VoidCallback? onToggleSave;

  /// The viewer has Quick-applied (shows a quiet status badge).
  final bool applied;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final pay = job.payLabel;
    final company = job.company.trim();
    final place = job.place;
    final sub = [
      if (company.isNotEmpty) company,
      if (place.isNotEmpty) place,
    ].join('  ·  ');

    final chips = <Widget>[
      // Paid placement is always named (patch 289).
      if (job.isFeatured)
        const JobChip('Featured', icon: Icons.trending_up_rounded, strong: true),
      if (job.isUrgent) const JobChip.urgent(),
      JobChip(job.formatType()),
      if (job.workArrangementLabel != null && job.workArrangement != 'on_site')
        JobChip(job.workArrangementLabel!),
      if (job.sabbathFriendly)
        const JobChip('Sabbath-friendly', icon: Icons.brightness_2_outlined),
      if (job.isSdaInstitution && !compact)
        const JobChip('Adventist', icon: Icons.church_outlined),
    ];

    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 10, 14),
        decoration: jobCardDecoration(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                JobMark(category: job.category, size: compact ? 44 : 50),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.title,
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleMedium.copyWith(
                          color: palette.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          height: 1.25,
                        ),
                      ),
                      if (sub.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: palette.textMuted,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (saved != null)
                  SaveJobButton(saved: saved!, onTap: onToggleSave)
                else
                  const SizedBox(width: 6),
              ],
            ),
            SizedBox(height: compact ? 10 : 12),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      pay ?? 'Pay not stated',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: pay == null
                          ? AppTextStyles.bodySmall.copyWith(
                              color: palette.textMuted,
                              fontStyle: FontStyle.italic,
                            )
                          : AppTextStyles.titleMedium.copyWith(
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                    ),
                  ),
                  if (compact)
                    Text(
                      jobAge(job.createdAt),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (compact)
              SizedBox(
                height: 26,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    maxWidth: double.infinity,
                    child: Row(
                      children: [
                        for (final c in chips) ...[c, const SizedBox(width: 6)],
                      ],
                    ),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Wrap(spacing: 6, runSpacing: 6, children: chips),
              ),
            if (!compact) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 14,
                      color: palette.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Posted ${jobAge(job.createdAt)}',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    if (applied) const StatusBadge('Applied'),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// White card, hairline, soft lift — shared by every jobs card.
BoxDecoration jobCardDecoration(BuildContext context) {
  final palette = context.palette;
  return BoxDecoration(
    color: palette.card,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: palette.divider),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 16,
        offset: const Offset(0, 6),
      ),
    ],
  );
}

/// A member who is available for work, as an employer sees them.
///
/// The person, not a vacancy: the work they do, where, how experienced,
/// the rate they ask and their own first lines. Poster identity stays
/// private (earlier owner decision), so the avatar is the field's icon,
/// never a profile photo.
class SeekerCard extends StatelessWidget {
  const SeekerCard({
    super.key,
    required this.job,
    required this.onTap,
    this.saved,
    this.onToggleSave,
  });

  final Job job;
  final VoidCallback onTap;
  final bool? saved;
  final VoidCallback? onToggleSave;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final pay = job.payLabel;
    final about = (job.description ?? '').trim();
    final meta = [
      if (job.place.isNotEmpty) job.place,
      switch (job.level) {
        'entry' => 'New to the work',
        'senior' => '5+ years',
        _ => '1–4 years',
      },
    ].join('  ·  ');
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 10, 14),
        decoration: jobCardDecoration(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.primaryGradient,
                  ),
                  child: Icon(
                    JobCategory.byId(job.category)?.icon ??
                        Icons.person_outline,
                    color: AppColors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleMedium.copyWith(
                          color: palette.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: palette.textMuted,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (saved != null)
                  SaveJobButton(saved: saved!, onTap: onToggleSave),
              ],
            ),
            if (about.isNotEmpty) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  about,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: palette.text,
                    height: 1.45,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (job.isFeatured)
                    const JobChip(
                      'Featured',
                      icon: Icons.trending_up_rounded,
                      strong: true,
                    ),
                  if (job.isUrgent) const StatusBadge('Available now'),
                  JobChip(job.formatType()),
                  if (pay != null) JobChip(pay, strong: true),
                  if (job.sabbathFriendly)
                    const JobChip(
                      'Keeps Sabbath',
                      icon: Icons.brightness_2_outlined,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The field's icon on a tinted squircle — the employer mark. Everyday
/// and professional work are blue (lighter / stronger tint), skilled work
/// navy: quiet palette tones so a list reads as varied, not uniform.
class JobMark extends StatelessWidget {
  const JobMark({super.key, required this.category, this.size = 50});
  final String? category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cat = JobCategory.byId(category);
    final tone = switch (cat?.kind) {
      JobKind.skilled => dark ? const Color(0xFF8FA6D9) : AppColors.darkNavy,
      _ => AppColors.primaryBlue,
    };
    final bgAlpha = switch (cat?.kind) {
      JobKind.professional => 0.16,
      JobKind.skilled => dark ? 0.18 : 0.09,
      _ => 0.10,
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tone.withValues(alpha: bgAlpha),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(
        cat?.icon ?? Icons.work_outline,
        color: tone,
        size: size * 0.46,
      ),
    );
  }
}

/// A quiet fact pill. [JobChip.urgent] is the one red thing on a card —
/// CLAUDE.md keeps red for urgent content.
class JobChip extends StatelessWidget {
  const JobChip(this.label, {super.key, this.icon, this.strong = false})
    : urgent = false;
  const JobChip.urgent({super.key})
    : label = 'Start now',
      icon = Icons.bolt_rounded,
      strong = true,
      urgent = true;

  final String label;
  final IconData? icon;
  final bool strong;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fg = urgent
        ? AppColors.red
        : strong
        ? AppColors.primaryBlue
        : palette.text;
    final bg = urgent
        ? AppColors.red.withValues(alpha: 0.10)
        : strong
        ? AppColors.primaryBlue.withValues(alpha: 0.10)
        : palette.cardMuted;
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: fg,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Green status badge — CLAUDE.md allows green for status badges only.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.successGreen;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: c,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class SaveJobButton extends StatelessWidget {
  const SaveJobButton({super.key, required this.saved, this.onTap});
  final bool saved;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: saved ? 'Remove from saved' : 'Save',
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
        child: Icon(
          saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          key: ValueKey(saved),
          color: saved ? AppColors.primaryBlue : context.palette.textMuted,
        ),
      ),
    );
  }
}

/// "2h ago", "3d ago", "2w ago", or a date.
String jobAge(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 60) return 'just now';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  if (d.inDays < 35) return '${d.inDays ~/ 7}w ago';
  const m = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${t.day} ${m[t.month - 1]}';
}
