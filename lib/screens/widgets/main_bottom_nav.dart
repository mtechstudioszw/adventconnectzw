import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/motion/pressable.dart';

/// Frosted glass behind the island.
///
/// Only pays off on screens with `extendBody: true`, where content actually
/// passes underneath — today that's Home. The other tabs still displace
/// content normally and will adopt extendBody as each is redesigned.
///
/// Set false if it ever janks on low-end hardware; the opaque island looks
/// nearly identical.
const bool kFloatingNavBlur = true;

/// Custom bottom navigation shared by the 5 top-level tabs.
///
/// Home, Watch, Churches, Marketplace, Profile. (Watch replaced the
/// Events tab — Events now lives on Home via the featured-events strip +
/// the events discovery row + a "See all" entry.) Prayer and Messaging
/// live inside the Profile tab's menu rather than as top-level tabs —
/// which is why unread chat / friend request counts surface on the
/// Profile icon here.
///
/// A FLOATING ISLAND: detached from the screen edge, frosted, with content
/// scrolling underneath. Inactive tabs are icon-only; the active one expands
/// into a labelled gradient pill. Dropping four labels is what buys the
/// active one room to breathe — five equal labelled columns is exactly what
/// made the old bar read as stock Material.
///
/// **Screens must reserve ~96dp of bottom padding**, because the island now
/// floats over content instead of displacing it.
///
/// Because each tab is its own route (no shell yet), the bar remounts per
/// screen — so the pill *pops in* at the new tab rather than sliding across;
/// the app-wide fade-through transition carries the movement between tabs.
///
/// Each tab can optionally show a red badge with a count by passing
/// [badges] (map of tab-index → count). A count of 0 hides the badge.
class MainBottomNav extends StatelessWidget {
  const MainBottomNav({
    super.key,
    required this.currentIndex,
    this.badges = const <int, int>{},
    this.onReselect,
  });

  final int currentIndex;
  final Map<int, int> badges;

  /// Fired when the ALREADY-ACTIVE tab is tapped again. Screens use it to
  /// scroll their content back to the top — the standard behaviour everywhere
  /// else, and the only way back up from a long endless feed.
  final VoidCallback? onReselect;

  static const _routes = [
    'home',
    'watch',
    'churches',
    'marketplace',
    'profile',
  ];

  static const _tabs = <(IconData, IconData, String)>[
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.play_circle_outline, Icons.play_circle_fill_rounded, 'Watch'),
    (Icons.church_outlined, Icons.church_rounded, 'Churches'),
    // storefront, not a shopping bag — this is a marketplace members sell
    // in, not a checkout.
    (Icons.storefront_outlined, Icons.storefront_rounded, 'Marketplace'),
    (Icons.person_outline, Icons.person_rounded, 'Profile'),
  ];

  /// The Profile tab shows the member's actual photo rather than a generic
  /// person glyph — the one place in the nav that should feel like *theirs*.
  /// Falls back to their initials on the brand gradient, matching how avatars
  /// degrade everywhere else in the app.
  static Widget _profileAvatar({required bool active, required double size}) {
    final user = AuthService.currentUser;
    final meta = user?.userMetadata ?? const {};
    final photo = (meta['profile_photo_url'] as String?)?.trim() ?? '';
    final name = (meta['full_name'] as String?)?.trim() ?? '';
    final initial = name.isNotEmpty
        ? name.substring(0, 1).toUpperCase()
        : ((user?.email ?? '?').isEmpty
            ? '?'
            : (user?.email ?? '?').substring(0, 1).toUpperCase());

    final fallback = Text(
      initial,
      style: AppTextStyles.labelSmall.copyWith(
        color: AppColors.white,
        fontWeight: FontWeight.w800,
        fontSize: size * 0.44,
        height: 1,
      ),
    );

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.primaryGradient,
        // A white ring inside the active pill so the photo separates from
        // the blue behind it; a subtle outline when resting on the island.
        border: Border.all(
          color: active
              ? AppColors.white
              : AppColors.primaryBlue.withValues(alpha: 0.35),
          width: active ? 1.8 : 1.4,
        ),
      ),
      child: photo.isEmpty
          ? fallback
          : CachedImage(
              photo,
              fit: BoxFit.cover,
              width: size,
              height: size,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }

  void _go(BuildContext context, int i) {
    if (i == currentIndex) {
      final reselect = onReselect;
      if (reselect != null) {
        HapticFeedback.selectionClick();
        reselect();
      }
      return;
    }
    HapticFeedback.selectionClick();
    context.goNamed(_routes[i]);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final blurring = kFloatingNavBlur && AppMotion.enabled(context);

    Widget island = Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
      decoration: BoxDecoration(
        // Translucent when we're blurring so the frost actually reads;
        // opaque otherwise so it never looks washed out.
        color: palette.card.withValues(alpha: blurring ? 0.82 : 1.0),
        borderRadius: BorderRadius.circular(AppRadius.sheet + 4),
        border: Border.all(
          color: dark
              ? AppColors.white.withValues(alpha: 0.08)
              : palette.divider,
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++)
            _NavItem(
              outlineIcon: _tabs[i].$1,
              filledIcon: _tabs[i].$2,
              label: _tabs[i].$3,
              active: i == currentIndex,
              badge: badges[i] ?? 0,
              onTap: () => _go(context, i),
              // Profile is the last tab and shows the member's own photo.
              glyph: i == _tabs.length - 1
                  ? _profileAvatar(
                      active: i == currentIndex,
                      size: i == currentIndex ? 24 : 26,
                    )
                  : null,
            ),
        ],
      ),
    );

    if (blurring) {
      island = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: island,
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          0,
          AppSpace.lg,
          AppSpace.md,
        ),
        child: DecoratedBox(
          // The shadow sits OUTSIDE the ClipRRect — clipping it would cut the
          // blur off at the same edge and lose the lift entirely.
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sheet + 4),
            boxShadow: AppShadows.floating(context),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sheet + 4),
            child: island,
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.outlineIcon,
    required this.filledIcon,
    required this.label,
    required this.active,
    required this.badge,
    required this.onTap,
    this.glyph,
  });

  final IconData outlineIcon;
  final IconData filledIcon;
  final String label;
  final bool active;
  final int badge;
  final VoidCallback onTap;

  /// Replaces the icon entirely. Used by the Profile tab to show the
  /// member's own avatar instead of a generic person glyph.
  final Widget? glyph;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    Widget icon = glyph ??
        Icon(
          active ? filledIcon : outlineIcon,
          size: 23,
          color: active ? AppColors.white : palette.textMuted,
        );
    if (badge > 0) icon = _BadgedIcon(icon: icon, badge: badge);

    final content = active
        ? Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md,
              vertical: AppSpace.sm,
            ),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.34),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(width: AppSpace.sm - 2),
                // Flexible + ellipsis so "Marketplace" shrinks gracefully on
                // a 360dp screen instead of overflowing the island.
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelMedium.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          )
        : SizedBox(width: 46, height: 44, child: Center(child: icon));

    final item = Semantics(
      selected: active,
      button: true,
      label: label,
      child: PressEffect(
        pressedScale: 0.90,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: active && AppMotion.enabled(context)
              // The pill springs in on arrival. Because the bar remounts per
              // route it can't slide from the previous tab — this is what
              // sells the transition instead.
              ? TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.80, end: 1),
                  duration: AppMotion.standard,
                  curve: AppMotion.spring,
                  builder: (context, v, child) =>
                      Transform.scale(scale: v, child: child),
                  child: content,
                )
              : content,
        ),
      ),
    );

    // The active pill takes whatever room it needs (and gives some back when
    // cramped); inactive icons stay a fixed, comfortable tap target.
    return active ? Flexible(child: item) : item;
  }
}

class _BadgedIcon extends StatelessWidget {
  const _BadgedIcon({required this.icon, required this.badge});

  final Widget icon;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          top: -4,
          right: -8,
          child: Container(
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: AppColors.red,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: context.palette.card, width: 1.5),
            ),
            alignment: Alignment.center,
            child: Text(
              badge > 99 ? '99+' : '$badge',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.white,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                height: 1.0,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
