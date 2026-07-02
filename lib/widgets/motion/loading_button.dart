import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import 'brand_spinner.dart';
import 'pressable.dart';

/// The app's primary action button with a built-in loading morph: while
/// [loading] is true the gradient pill contracts into a circle around a
/// branded spinner, then springs back to its label when the work is done
/// — buttons never sit frozen and never need an external spinner.
///
/// Controlled, not fire-and-forget: the screen owns the `loading` bool
/// (it usually already has a `_saving`/`_submitting` flag), so the morph
/// is interruptible and can't get stuck out of sync with the real work.
///
/// ```dart
/// LoadingButton(
///   label: 'Post prayer',
///   icon: Icons.send_rounded,
///   loading: _submitting,
///   onPressed: _submit,
/// )
/// ```
class LoadingButton extends StatelessWidget {
  const LoadingButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.enabled = true,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final bool enabled;
  final double height;

  @override
  Widget build(BuildContext context) {
    final active = enabled && !loading && onPressed != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final fullWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return Align(
          child: Pressable(
            onTap: active ? onPressed : null,
            haptics: true,
            child: AnimatedContainer(
              duration: AppMotion.maybe(context, AppMotion.standard),
              curve: AppMotion.ease,
              width: loading ? height : fullWidth,
              height: height,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius:
                    BorderRadius.circular(loading ? height / 2 : AppRadius.button),
                boxShadow: active ? AppShadows.glow(context) : null,
              ),
              child: AnimatedOpacity(
                duration: AppMotion.maybe(context, AppMotion.quick),
                opacity: active || loading ? 1.0 : 0.55,
                child: AnimatedSwitcher(
                  duration: AppMotion.maybe(context, AppMotion.quick),
                  switchInCurve: AppMotion.easeOut,
                  switchOutCurve: AppMotion.easeIn,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  ),
                  child: loading
                      ? const Center(
                          key: ValueKey('spinner'),
                          child: BrandSpinner(size: 26),
                        )
                      : Row(
                          key: const ValueKey('label'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (icon != null) ...[
                              Icon(icon, color: AppColors.white, size: 20),
                              const SizedBox(width: AppSpace.sm),
                            ],
                            Flexible(
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.buttonText,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
