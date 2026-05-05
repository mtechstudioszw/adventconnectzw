import 'package:flutter/material.dart';
import '../widgets/tab_placeholder.dart';

class ChurchesScreen extends StatelessWidget {
  const ChurchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const TabPlaceholder(
      icon: Icons.church_outlined,
      title: 'Churches',
      subtitle: 'Find and follow churches near you.',
    );
  }
}
