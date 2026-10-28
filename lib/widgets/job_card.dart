import 'package:flutter/material.dart';

import '../models/job_model.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';
import 'motion/pressable.dart';

/// One job in a list (redesign, 28 Oct 2026).
///
/// Scannable in one look: the employer mark, the role, who and where, then
/// the three facts people filter by — type, arrangement, pay — as quiet
/// chips, and when it was posted. "Looking for work" posts are marked so
/// they're never mistaken for vacancies. Pay shows only when the poster
/// gave it; nothing says "Negotiable" on their behalf.
class JobCard extends StatelessWidget {
  const JobCard({
    super.key,
    required this.job,
    required this.onTap,
    this.saved,
    this.onToggleSave,
  });

  final Job job;
  final VoidCallback onTap;

  /// Null hides the bookmark (e.g. on Home's rail).
  final bool? saved;
  final VoidCallback? onToggleSave;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final cat = JobCategory.byId(job.category);
    final company = job.company.trim();
    final place = job.place;
    final chips = <String>[
      job.formatType(),
      ?job.workArrangementLabel,
      if ((job.salaryRange ?? '').isNotEmpty) job.salaryRange!,
    ];
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Mark(job: job, icon: cat?.icon ?? Icons.work_outline),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (job.isSeeking)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            'LOOKING FOR WORK',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                      Text(
                        job.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleSmall.copyWith(
                          color: palette.text,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (company.isNotEmpty) company,
                          if (place.isNotEmpty) place,
                        ].join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (saved != null)
                  Semantics(
                    button: true,
                    label: saved! ? 'Remove from saved jobs' : 'Save job',
                    child: InkResponse(
                      onTap: onToggleSave,
                      radius: 22,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          saved!
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                          color: saved!
                              ? AppColors.primaryBlue
                              : palette.textMuted,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final c in chips)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: palette.cardMuted,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            c,
                            style: AppTextStyles.labelSmall.copyWith(
                              color: palette.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (job.sabbathFriendly)
                        Tooltip(
                          message: 'Sabbath-friendly hours',
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: AppColors.primaryBlue.withValues(
                                alpha: 0.10,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.brightness_3_outlined,
                              size: 14,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _ago(job.createdAt),
                  style: AppTextStyles.labelSmall.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays >= 7) return '${diff.inDays ~/ 7}w ago';
    if (diff.inDays >= 1) return '${diff.inDays}d ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    return 'New';
  }
}

class _Mark extends StatelessWidget {
  const _Mark({required this.job, required this.icon});
  final Job job;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final words = job.company
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: job.isSeeking
          ? const Icon(
              Icons.person_search_outlined,
              color: AppColors.primaryBlue,
              size: 22,
            )
          : words.isEmpty
          ? Icon(icon, color: AppColors.primaryBlue, size: 22)
          : Text(
              words,
              style: AppTextStyles.titleSmall.copyWith(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}
