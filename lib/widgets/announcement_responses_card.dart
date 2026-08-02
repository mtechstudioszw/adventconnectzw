import 'package:flutter/material.dart';

import '../services/church_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';
import 'screen_shell.dart';

/// How members responded to each announcement — the reaction breakdown
/// behind the admin dashboard's open rate.
///
/// The admin dashboard keeps its other panels as private classes in its
/// own file. This one lives out here with [AnnouncementReactionBar]
/// because the two are the same feature seen from both ends — what a
/// member taps and what the admin reads — and because a card built from a
/// plain list of stats is worth a layout test of its own. The bar
/// overflowed by 144px at 2.5x text before its test caught it.
///
/// Reach counts opens; this counts replies to what was opened, so the
/// percentage is measured against readCount, not the send count. An
/// announcement nobody opened has no response rate rather than 0% — the
/// difference matters to an admin deciding whether the message or the
/// delivery was the problem.
///
/// Newest first. The service hands rows back oldest-first to match the
/// reach sparkline's left-to-right time axis; a list has no axis, and the
/// announcement an admin just posted is the one they came to check.
class AnnouncementResponsesCard extends StatelessWidget {
  const AnnouncementResponsesCard({super.key, required this.stats});

  final List<AnnouncementReactionStat> stats;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final newestFirst = stats.reversed.toList(growable: false);
    final totalResponses = stats.fold<int>(0, (s, r) => s + r.reactionCount);

    return ScreenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Flexible so the eyebrow yields to the tally instead of
              // pushing it off the card at large text scales.
              Flexible(
                child: Text(
                  'HOW THEY RESPONDED',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                totalResponses == 1 ? '1 response' : '$totalResponses responses',
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Last ${stats.length} announcements, newest first.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < newestFirst.length; i++) ...[
            if (i > 0) Divider(height: 18, color: palette.divider),
            _ResponseRow(stat: newestFirst[i]),
          ],
        ],
      ),
    );
  }
}

class _ResponseRow extends StatelessWidget {
  const _ResponseRow({required this.stat});

  final AnnouncementReactionStat stat;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final counts = stat.reactions.counts;
    // Against opens, not sends — see [AnnouncementResponsesCard].
    final rate = stat.readCount == 0
        ? null
        : (stat.reactionCount / stat.readCount * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          stat.title.isEmpty ? 'Untitled announcement' : stat.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
            color: palette.text,
          ),
        ),
        const SizedBox(height: 6),
        // Wrap, not Row: four faces plus a trailing rate overflows a 360dp
        // card once the system font is scaled up, and a Row would throw
        // rather than reflow.
        Wrap(
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (stat.reactionCount == 0)
              Text(
                stat.readCount == 0 ? 'Not opened yet' : 'Opened, no responses',
                style: AppTextStyles.bodySmall.copyWith(
                  color: palette.textMuted,
                ),
              )
            else
              for (final kind in AnnouncementReaction.values)
                if ((counts[kind] ?? 0) > 0)
                  Text(
                    '${kind.emoji} ${counts[kind]}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: palette.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
            if (rate != null && stat.reactionCount > 0)
              Text(
                '$rate% of ${stat.readCount} who opened',
                style: AppTextStyles.bodySmall.copyWith(
                  color: palette.textMuted,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
