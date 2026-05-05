import 'package:flutter/material.dart';
import 'churches/churches_screen.dart';
import 'events/events_screen.dart';
import 'home/home_screen.dart';
import 'prayer/prayer_screen.dart';
import 'profile/profile_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _tabs = <_TabSpec>[
    _TabSpec(
      label: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      screen: HomeScreen(),
    ),
    _TabSpec(
      label: 'Churches',
      icon: Icons.church_outlined,
      activeIcon: Icons.church,
      screen: ChurchesScreen(),
    ),
    _TabSpec(
      label: 'Events',
      icon: Icons.event_outlined,
      activeIcon: Icons.event,
      screen: EventsScreen(),
    ),
    _TabSpec(
      label: 'Prayer',
      icon: Icons.volunteer_activism_outlined,
      activeIcon: Icons.volunteer_activism,
      screen: PrayerScreen(),
    ),
    _TabSpec(
      label: 'Profile',
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      screen: ProfileScreen(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final tab = _tabs[_index];
    return Scaffold(
      backgroundColor: AppColors.lightGrey,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        ),
        title: Text(tab.label, style: AppTextStyles.appBarTitle),
        elevation: 0,
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: _tabs.map((t) => t.screen).toList(),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: _tabs
            .map(
              (t) => BottomNavigationBarItem(
                icon: Icon(t.icon),
                activeIcon: Icon(t.activeIcon),
                label: t.label,
              ),
            )
            .toList(),
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.screen,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Widget screen;
}
