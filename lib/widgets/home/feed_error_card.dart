import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';

/// Home's feed when the first page failed and nothing was cached.
///
/// Kept apart from the empty-feed card on purpose: "follow a church to fill
/// your feed" is the wrong advice for a feed that simply did not arrive —
/// it told members with no signal that they had no friends.
///
/// Offline and server failure are worded differently for the same reason
/// the offline toast is careful: "check your connection" over a server
/// fault sends the member chasing a problem that isn't theirs.
class FeedErrorCard extends StatelessWidget {
  const FeedErrorCard({
    super.key,
    required this.offline,
    required this.onRetry,
  });

  final bool offline;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.xl,
        AppSpace.lg,
        AppSpace.lg,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpace.xl),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: palette.divider),
        ),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                offline ? Icons.wifi_off_rounded : Icons.cloud_off_outlined,
                color: AppColors.primaryBlue,
                size: 34,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            Text(
              offline ? "You're offline" : "Couldn't load your feed",
              textAlign: TextAlign.center,
              style: AppTextStyles.headlineSmall.copyWith(
                color: palette.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              offline
                  ? 'Posts will appear here once you have a connection. '
                      'Your Library downloads still work offline.'
                  : 'Something went wrong on our side. Please try again.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: palette.textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            FilledButton.icon(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
