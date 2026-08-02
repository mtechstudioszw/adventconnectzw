import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:go_router/go_router.dart';

import '../services/connectivity_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';

/// Wraps a bespoke flat header so the status-bar icons are dark on the light
/// background (and light in dark mode). The themed AppBar does this for
/// AppBar screens automatically; custom `Container` headers need it set here
/// so no screen ends up with invisible status-bar icons.
class FlatStatusBar extends StatelessWidget {
  const FlatStatusBar({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      ),
      child: child,
    );
  }
}

/// Light-grey chip fill for circular header icon buttons. Sits a touch
/// darker than the scaffold so the buttons read against the flat header;
/// swaps to a muted card fill in dark mode.
Color _headerChipColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? context.palette.cardMuted
        : const Color(0xFFE4E9F2);

/// Flat, single-colour header used at the top of most secondary screens.
/// Shares the scaffold background so the screen reads as one continuous
/// colour from the status bar down — no navy block, no curve, no gradient.
class ScreenHero extends StatelessWidget {
  const ScreenHero({
    super.key,
    required this.title,
    this.tagline,
    this.subtitle,
    this.fallbackRoute,
    this.trailing,
  });

  final String title;
  final String? tagline;
  final String? subtitle;
  final String? fallbackRoute;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return FlatStatusBar(
      child: Container(
        width: double.infinity,
        color: palette.scaffoldBg,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ScreenHeroBackButton(fallbackRoute: fallbackRoute),
                    const Spacer(),
                    ?trailing,
                  ],
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (tagline != null) ...[
                        Text(
                          tagline!.toUpperCase(),
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.primaryBlue,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.6,
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      Text(
                        title,
                        style: AppTextStyles.displayMedium.copyWith(
                          color: palette.text,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ScreenHeroBackButton extends StatelessWidget {
  const ScreenHeroBackButton({super.key, this.fallbackRoute});
  final String? fallbackRoute;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (context.canPop()) {
            context.pop();
          } else if (fallbackRoute != null) {
            context.goNamed(fallbackRoute!);
          } else {
            context.goNamed('home');
          }
        },
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _headerChipColor(context),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.arrow_back_ios_new,
            size: 16,
            color: context.palette.text,
          ),
        ),
      ),
    );
  }
}

class ScreenHeroTrailing extends StatelessWidget {
  const ScreenHeroTrailing({super.key, required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HeaderIconButton(icon: icon, onTap: onTap);
  }
}

/// Circular icon button for the flat light headers — a light-grey chip with
/// a navy icon (both adapt to dark mode), plus an optional red count badge
/// for things like the notifications bell.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
    this.tooltip,
    this.iconSize = 20,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final int badgeCount;
  final String? tooltip;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    Widget result = Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _headerChipColor(context),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: context.palette.text, size: iconSize),
        ),
      ),
    );
    if (badgeCount > 0) {
      result = Stack(
        clipBehavior: Clip.none,
        children: [
          result,
          Positioned(
            right: -1,
            top: -1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              constraints: const BoxConstraints(minWidth: 18),
              decoration: BoxDecoration(
                color: AppColors.red,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: context.palette.scaffoldBg, width: 1.5),
              ),
              child: Text(
                badgeCount > 99 ? '99+' : '$badgeCount',
                textAlign: TextAlign.center,
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ),
          ),
        ],
      );
    }
    return tooltip == null ? result : Tooltip(message: tooltip!, child: result);
  }
}

/// White rounded card with the standard subtle shadow. Used everywhere
/// for content blocks so the shadow / radius stays consistent.
class ScreenCard extends StatelessWidget {
  const ScreenCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
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

class PrimaryGradientButton extends StatelessWidget {
  const PrimaryGradientButton({
    super.key,
    required this.label,
    required this.onTap,
    this.busy = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onTap;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null && !busy ? 0.6 : 1,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withValues(alpha: 0.30),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppColors.white,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null) ...[
                            Icon(icon, color: AppColors.white, size: 18),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            label,
                            style: AppTextStyles.buttonText.copyWith(
                              fontSize: 15,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A failed load, stated in place and offered a way out.
///
/// This is the app's most-used error surface — eight screens render it as
/// their ENTIRE body when a fetch fails. Until 2 Aug 2026 it had no retry
/// affordance of any kind, so a load that failed on a flaky connection was
/// a dead end: the member's only move was to leave the screen and come
/// back. That is the blocking behaviour an offline audit exists to remove.
///
/// Two things it now does:
///
///  * **Offers [onRetry]**, which re-runs only the operation that failed.
///    The rest of the screen keeps working throughout — this is a banner
///    inside the layout, never a route and never an overlay.
///  * **Tells the truth about why.** A dropped connection and a server
///    error need different words: "check your connection" is useless
///    advice when the connection is fine. When the device is offline the
///    banner says so and ignores the caller's server-shaped [message].
///
/// The retry button is deliberately part of the banner rather than left to
/// each caller, because eight callers meant eight chances to forget it.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message, this.onRetry});

  /// What went wrong. Overridden by the offline copy when the device has
  /// no connection, since the cause is then known and more specific.
  final String message;

  /// Re-runs the failed operation. When null the banner still explains
  /// itself but cannot offer a way forward — pass this wherever a load
  /// function exists.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final offline = !ConnectivityService.isOnline;
    final text = offline
        ? 'You\'re offline. Check your internet connection and try again.'
        : message;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
      ),
      // Column, not Row: the message wraps and the button sits under it,
      // so neither has to give up width to the other at large text scales.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                offline ? Icons.wifi_off_rounded : Icons.error_outline,
                color: AppColors.red,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.red,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.message,
    this.icon = Icons.info_outline,
  });
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primaryBlue, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textMuted,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return ScreenCard(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primaryBlue, size: 38),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyles.headlineMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textMuted,
              height: 1.5,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 18),
            action!,
          ],
        ],
      ),
    );
  }
}
