import 'package:flutter/material.dart';
import '../widgets/main_scaffold.dart';
import '../widgets/tab_placeholder.dart';

class PrayerScreen extends StatelessWidget {
  const PrayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const MainScaffold(
      title: 'Prayer',
      currentIndex: 3,
      body: TabPlaceholder(
        icon: Icons.volunteer_activism_outlined,
        title: 'Prayer',
        subtitle: 'Share requests and pray with the community.',
      ),
    );
  }
}
