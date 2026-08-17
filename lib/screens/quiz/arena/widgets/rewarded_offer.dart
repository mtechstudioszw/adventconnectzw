import 'package:flutter/material.dart';

import '../../../../services/ads/rewarded_ad_manager.dart';
import '../../../../services/quiz_rewards_service.dart';
import '../../../../theme/app_text_styles.dart';
import '../arena_theme.dart';

/// The one button every "watch a short ad for X" offer in the quiz uses.
///
/// ## Why it looks like this
///
/// The trade is stated on the face of the button, before it is tapped: the
/// label says what you get, the trailing chip says what it costs you. A
/// subscriber sees `FREE` there instead of `AD`, because for them it is.
/// Nothing here is a dark pattern — there is no countdown pressuring a
/// decision, and every offer sits beside a plain way to decline.
///
/// ## Why it rebuilds on [RewardedAdManager.available]
///
/// Under AdMob the quiz decided whether to mention an ad *once*, silently,
/// at the moment the player ran out of coins — and if nothing happened to
/// be cached right then it just granted the bonus for free and said
/// nothing. That is why the funnel looked empty. Listening to availability
/// means the offer appears the moment fill arrives, which is the actual fix
/// for "the quiz is not serving ads the right way".
class RewardedOfferButton extends StatelessWidget {
  const RewardedOfferButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onClaimed,
    this.busy = false,
    this.subtitle,
  });

  /// Short and concrete — "Continue your run", not a sentence. Long labels
  /// are what break fixed-height buttons at 2.5x text scale.
  final String label;

  final String? subtitle;
  final IconData icon;

  /// Called after the ad was watched (or waived for a subscriber).
  final VoidCallback onClaimed;

  final bool busy;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: RewardedAdManager.available,
      builder: (context, _, _) {
        // Nothing to offer and no perk to grant — say nothing at all rather
        // than showing a button that does nothing.
        if (!QuizRewards.canOffer) return const SizedBox.shrink();
        return _button(context);
      },
    );
  }

  Widget _button(BuildContext context) {
    final free = QuizRewards.grantedFree;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: busy ? null : onClaimed,
        child: Opacity(
          opacity: busy ? 0.6 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: ArenaTheme.gold.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: ArenaTheme.gold.withValues(alpha: 0.55),
              ),
            ),
            child: Row(
              children: [
                if (busy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: ArenaTheme.gold,
                    ),
                  )
                else
                  Icon(icon, size: 20, color: ArenaTheme.gold),
                const SizedBox(width: 11),
                // Expanded, not a bare Text: an unflexed Text in a Row
                // THROWS once the label wraps, and this one carries a
                // user-visible string at up to 2.5x scale.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: AppTextStyles.labelMedium.copyWith(
                          color: ArenaTheme.goldBright,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: AppTextStyles.bodySmall
                              .copyWith(color: ArenaTheme.textMutedOnNavy),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _CostChip(free: free),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Says what the offer costs: a short ad, or nothing if you subscribe.
class _CostChip extends StatelessWidget {
  const _CostChip({required this.free});

  final bool free;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: ArenaTheme.gold.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(ArenaTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            free ? Icons.workspace_premium_rounded : Icons.play_arrow_rounded,
            size: 13,
            color: ArenaTheme.goldBright,
          ),
          const SizedBox(width: 3),
          Text(
            free ? 'FREE' : 'AD',
            style: AppTextStyles.labelSmall.copyWith(
              color: ArenaTheme.goldBright,
              fontWeight: FontWeight.w800,
              fontSize: 10.5,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}
