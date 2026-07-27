import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';

/// The ONE section header used by every block on Home.
///
/// Home used to grow a new header grammar per section — `_buildSectionHeader`
/// for the rails, a bespoke icon+title+"See all" row inside the music strip,
/// another inside FeaturedChurchEvents. Three variants of the same thing is
/// what made the screen read as assembled rather than designed, so every
/// section now routes through here.
///
/// Sizes come from [AppTextStyles] / [AppSpace] — do not pass ad-hoc
/// `fontSize:` overrides at the call site.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.action,
    this.onAction,
    this.icon,
  });

  final String title;

  /// Trailing text link, e.g. "See all". Hidden when null.
  final String? action;
  final VoidCallback? onAction;

  /// Optional leading glyph. Used sparingly — most sections are text-only.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.sm, 0),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: AppColors.primaryBlue),
            const SizedBox(width: AppSpace.sm),
          ],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.headlineSmall.copyWith(
                color: context.palette.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    action!,
                    style: AppTextStyles.labelMedium.copyWith(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.primaryBlue,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Vertical rhythm wrapper for a Home section: header, gap, body.
///
/// Every section on Home is spaced by [AppSpace.xl] above and [AppSpace.md]
/// between header and body — one rhythm, applied in one place, so sections
/// can't drift apart the way they had.
class HomeSection extends StatelessWidget {
  const HomeSection({
    super.key,
    required this.child,
    this.title,
    this.action,
    this.onAction,
    this.icon,
  });

  final Widget child;
  final String? title;
  final String? action;
  final VoidCallback? onAction;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpace.xl),
        if (title != null) ...[
          SectionHeader(
            title: title!,
            action: action,
            onAction: onAction,
            icon: icon,
          ),
          const SizedBox(height: AppSpace.md),
        ],
        child,
      ],
    );
  }
}
