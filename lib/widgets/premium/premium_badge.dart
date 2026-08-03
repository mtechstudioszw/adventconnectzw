import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// The gold mark that says someone supports the app.
///
/// Gold is the app's one-highlight-per-screen accent, which is exactly
/// why it suits this: it is already the colour that means "this one is
/// different". Sized to sit on a name row without pushing the line
/// height around.
class PremiumBadge extends StatelessWidget {
  const PremiumBadge({super.key, this.size = 14, this.showLabel = false});

  /// Height of the mark. The star scales with it.
  final double size;

  /// Show the word "Premium" next to the star. Off in dense rows (a
  /// feed name line), on where there is room to explain itself.
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final star = Icon(
      Icons.star_rounded,
      size: size,
      color: AppColors.goldAccent,
      // Announced once, here, rather than by every caller.
      semanticLabel: showLabel ? null : 'Premium member',
    );

    if (!showLabel) return star;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: size * 0.5,
        vertical: size * 0.18,
      ),
      decoration: BoxDecoration(
        color: AppColors.goldAccent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size),
        border: Border.all(
          color: AppColors.goldAccent.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          star,
          SizedBox(width: size * 0.25),
          // No fixed height anywhere here: this sits next to names that
          // wrap and must survive 2.5x system text.
          Text(
            'Premium',
            style: TextStyle(
              fontSize: size * 0.78,
              fontWeight: FontWeight.w700,
              color: AppColors.goldAccent,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
