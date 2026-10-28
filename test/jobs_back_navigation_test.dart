// Owner, 28 Oct 2026: "the back button in jobs … takes you to home instead
// of the previous screen, which is marketplace". Marketplace opened Jobs
// with goNamed, which REPLACES the stack, so there was nothing to go back
// to. It now pushes, and Jobs with nothing underneath backs out to
// Marketplace rather than leaving the section.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:advent_connect_zw/screens/jobs/jobs_screen.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

import 'helpers/fake_supabase.dart';

GoRouter _router(String initial) => GoRouter(
  initialLocation: initial,
  routes: [
    GoRoute(
      path: '/home',
      name: 'home',
      builder: (_, _) => const Scaffold(body: Text('HOME')),
    ),
    GoRoute(
      path: '/marketplace',
      name: 'marketplace',
      builder: (context, _) => Scaffold(
        body: TextButton(
          onPressed: () => context.pushNamed('jobs'),
          child: const Text('MARKETPLACE'),
        ),
      ),
    ),
    GoRoute(path: '/jobs', name: 'jobs', builder: (_, _) => const JobsScreen()),
  ],
);

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    await initFakeSupabase((_) => const <Object>[]);
  });

  testWidgets('Back from Jobs returns to Marketplace', (t) async {
    t.view.physicalSize = const Size(390, 1400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final router = _router('/marketplace');
    await t.pumpWidget(
      MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
    await _settle(t);
    await t.tap(find.text('MARKETPLACE'));
    await _settle(t);
    expect(find.byType(JobsScreen), findsOneWidget);

    // The phone's Back button / gesture.
    await t.binding.handlePopRoute();
    await _settle(t);
    expect(find.text('MARKETPLACE'), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('Jobs opened from a link backs out to Marketplace', (t) async {
    t.view.physicalSize = const Size(390, 1400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final router = _router('/jobs');
    await t.pumpWidget(
      MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
    await _settle(t);
    await t.binding.handlePopRoute();
    await _settle(t);
    expect(find.text('MARKETPLACE'), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
    await t.pump(const Duration(seconds: 2));
  });
}
