import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';

/// The marketplace safety notice.
///
/// This existed as a byte-identical private `_SafetyCard` in both
/// product_details_screen and seller_profile_screen — same copy, same
/// layout, two definitions. Since there are no payment rails, this
/// disclaimer is load-bearing legal text, and it must not be possible for
/// the two copies to drift apart.
class MarketplaceSafetyCard extends StatelessWidget {
  const MarketplaceSafetyCard({super.key});

  static const text =
      'Meet in a public place. Inspect items before paying. Never send money '
      'in advance to people you don\'t trust. Advent Connect ZW is not a '
      'party to any transaction.';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.darkNavy.withValues(alpha: 0.04),
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.darkNavy.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpace.sm),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.10),
              borderRadius: AppRadius.smAll,
            ),
            child: const Icon(
              Icons.shield_outlined,
              color: AppColors.primaryBlue,
              size: 18,
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stay safe',
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  text,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: context.palette.textMuted,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
