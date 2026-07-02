import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/motion/pressable.dart';

/// Custom bottom navigation shared by the 5 top-level tabs.
///
/// Home, Watch, Churches, Marketplace, Profile. (Watch replaced the
/// Events tab — Events now lives on Home via the featured-events strip +
/// the events discovery row + a "See all" entry.) Prayer and Messaging
/// live inside the Profile tab's menu rather than as top-level tabs —
/// which is why unread chat / friend request counts surface on the
/// Profile icon here.
///
/// Replaces the stock Material BottomNavigationBar: the active tab sits
/// in a soft blue capsule that springs in on arrival, its icon pops from
/// outline to filled, and every item compresses on press. Because each
/// tab is its own route (no shell), the bar remounts per screen — so the
/// capsule *pops in* at the new tab rather than sliding across; the
/// app-wide fade-through transition carries the movement between tabs.
///
/// Each tab can optionally show a red badge with a count by passing
/// [badges] (map of tab-index → count). A count of 0 hides the badge.
class MainBottomNav extends StatelessWidget {
  const MainBottomNav({
    super.key,
    required this.currentIndex,
    this.badges = const <int, int>{},
  });

  final int currentIndex;
  final Map<int, int> badges;

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
    (Icons.shopping_bag_outlined, Icons.shopping_bag_rounded, 'Marketplace'),
    (Icons.person_outline, Icons.person_rounded, 'Profile'),
  ];

  void _go(BuildContext context, int i) {
    if (i == currentIndex) return;
    HapticFeedback.selectionClick();
    context.goNamed(_routes[i]);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        border: Border(top: BorderSide(color: palette.divider, width: 0.7)),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkNavy.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (var i = 0; i < _tabs.length; i++)
                Expanded(
                  child: _NavItem(
                    outlineIcon: _tabs[i].$1,
                    filledIcon: _tabs[i].$2,
                    label: _tabs[i].$3,
                    active: i == currentIndex,
                    badge: badges[i] ?? 0,
                    onTap: () => _go(context, i),
                  ),
                ),
            ],
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
  });

  final IconData outlineIcon;
  final IconData filledIcon;
  final String label;
  final bool active;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = active ? AppColors.primaryBlue : palette.textMuted;

    Widget icon = Icon(
      active ? filledIcon : outlineIcon,
      size: 24,
      color: color,
    );
    if (badge > 0) icon = _BadgedIcon(icon: icon, badge: badge);

    // The active capsule + filled icon spring in on arrival at this tab.
    final item = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: active
                ? AppColors.primaryBlue.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.20
                        : 0.11,
                  )
                : Colors.transparent,
            borderRadius: BorderRadius.circular(100),
          ),
          child: icon,
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.labelSmall.copyWith(
            color: color,
            fontSize: 10.5,
            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );

    return PressEffect(
      pressedScale: 0.90,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Semantics(
          selected: active,
          button: true,
          label: label,
          child: active && AppMotion.enabled(context)
              ? TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.85, end: 1),
                  duration: AppMotion.pressOut,
                  curve: AppMotion.spring,
                  builder: (context, v, child) =>
                      Transform.scale(scale: v, child: child),
                  child: item,
                )
              : item,
        ),
      ),
    );
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
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.white, width: 1.5),
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
