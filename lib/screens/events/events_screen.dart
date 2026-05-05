import 'package:flutter/material.dart';
import '../widgets/main_scaffold.dart';
import '../widgets/tab_placeholder.dart';

class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const MainScaffold(
      title: 'Events',
      currentIndex: 2,
      body: TabPlaceholder(
        icon: Icons.event_outlined,
        title: 'Events',
        subtitle: 'Services, conferences, and gatherings across Zimbabwe.',
      ),
    );
  }
}
