import 'package:flutter/material.dart';
import '../../widgets/screen_shell.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/motion/loading_button.dart';

/// Shared building blocks for "post X" screens (post event, post job,
/// add product, post prayer). Keeps the form/visual language identical
/// without duplicating ~600 lines of widgets.

/// Gold-gradient FAB used on the four list screens (events, jobs,
/// marketplace, prayer) to launch the matching post screen.
class PostFab extends StatelessWidget {
  const PostFab({
    super.key,
    required this.routeName,
    required this.tooltip,
    this.icon = Icons.add,
  });

  final String routeName;
  final String tooltip;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFFC8A951), Color(0xFFD9BD6B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.goldAccent.withValues(alpha: 0.40),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.pushNamed(routeName),
          customBorder: const CircleBorder(),
          child: Tooltip(
            message: tooltip,
            child: SizedBox(
              width: 60,
              height: 60,
              child: Icon(icon, color: AppColors.darkNavy, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}

class PostFormHero extends StatelessWidget {
  const PostFormHero({
    super.key,
    required this.kicker,
    required this.title,
    required this.subtitle,
    required this.fallbackRouteName,
  });

  final String kicker;
  final String title;
  final String subtitle;
  final String fallbackRouteName;

  @override
  Widget build(BuildContext context) {
    return ScreenHero(
      title: title,
      tagline: kicker,
      subtitle: subtitle,
      fallbackRoute: fallbackRouteName,
    );
  }
}

class PostFormCard extends StatelessWidget {
  const PostFormCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
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
      child: child,
    );
  }
}

class PostFormLabeledField extends StatelessWidget {
  const PostFormLabeledField({
    super.key,
    required this.label,
    required this.child,
    this.helper,
  });

  final String label;
  final Widget child;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label.toUpperCase(),
              style: AppTextStyles.labelSmall.copyWith(
                color: context.palette.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const Spacer(),
            if (helper != null)
              Text(
                helper!,
                style: AppTextStyles.labelSmall.copyWith(
                  color: context.palette.textMuted,
                  fontSize: 11,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class PostFormErrorBanner extends StatelessWidget {
  const PostFormErrorBanner({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.red, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.red,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared submit button for every post form (event / product / prayer /
/// job / notice / news). While [busy] the gradient pill contracts into a
/// circle around the branded spinner, then springs back — the
/// LoadingButton morph from the motion kit.
class PostFormSaveButton extends StatelessWidget {
  const PostFormSaveButton({
    super.key,
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: AppMotion.quick,
      opacity: onTap == null && !busy ? 0.6 : 1,
      child: LoadingButton(
        label: label,
        loading: busy,
        enabled: onTap != null,
        onPressed: onTap,
        height: 56,
      ),
    );
  }
}

InputDecoration postFormFilledDecoration({
  required IconData icon,
  required String hint,
}) {
  return InputDecoration(
    hintText: hint,
    prefixIcon: Padding(
      padding: const EdgeInsets.only(left: 14, right: 10),
      child: Icon(icon, color: AppColors.primaryBlue, size: 20),
    ),
    prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    filled: true,
    // Adaptive: light grey in light mode (unchanged), a dark muted fill in
    // dark mode so the post-event / post-news fields aren't glaring white.
    fillColor: AppColors.surfaceMuted,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: AppColors.divider),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: AppColors.divider),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.red),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.red, width: 1.5),
    ),
  );
}

