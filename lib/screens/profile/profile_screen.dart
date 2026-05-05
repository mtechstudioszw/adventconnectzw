import 'package:flutter/material.dart';
import '../widgets/main_scaffold.dart';
import '../widgets/tab_placeholder.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const MainScaffold(
      title: 'Profile',
      currentIndex: 4,
      body: TabPlaceholder(
        icon: Icons.person_outline,
        title: 'Profile',
        subtitle: 'Your account, settings, and activity.',
      ),
    );
  }
}
