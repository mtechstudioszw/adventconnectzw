import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Bottom navigation shared by the 5 top-level tabs.
///
/// Per master reference Part 7: Home, Churches, Events, Marketplace,
/// Profile. Prayer and Messaging live inside the Profile tab's menu
/// rather than as top-level tabs — which is why unread chat / friend
/// request counts surface on the Profile icon here.
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
    'churches',
    'events',
    'marketplace',
    'profile',
  ];

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: (i) {
        if (i == currentIndex) return;
        context.goNamed(_routes[i]);
      },
      items: [
        _item(Icons.home_outlined, Icons.home, 'Home', badges[0] ?? 0),
        _item(Icons.church_outlined, Icons.church, 'Churches', badges[1] ?? 0),
        _item(Icons.event_outlined, Icons.event, 'Events', badges[2] ?? 0),
        _item(
          Icons.shopping_bag_outlined,
          Icons.shopping_bag,
          'Marketplace',
          badges[3] ?? 0,
        ),
        _item(
          Icons.person_outline,
          Icons.person,
          'Profile',
          badges[4] ?? 0,
        ),
      ],
    );
  }

  BottomNavigationBarItem _item(
    IconData icon,
    IconData activeIcon,
    String label,
    int badge,
  ) {
    return BottomNavigationBarItem(
      icon: _BadgedIcon(icon: icon, badge: badge),
      activeIcon: _BadgedIcon(icon: activeIcon, badge: badge),
      label: label,
    );
  }
}

class _BadgedIcon extends StatelessWidget {
  const _BadgedIcon({required this.icon, required this.badge});

  final IconData icon;
  final int badge;

  @override
  Widget build(BuildContext context) {
    if (badge <= 0) return Icon(icon);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
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
