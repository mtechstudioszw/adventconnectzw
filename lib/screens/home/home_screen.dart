import 'package:flutter/material.dart';
import '../widgets/tab_placeholder.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const TabPlaceholder(
      icon: Icons.home_outlined,
      title: 'Home',
      subtitle: 'Your personalised feed will live here.',
    );
  }
}
