// Every create screen pops `true` when it saves, and every list ignored it:
// the job, event, prayer or listing you had just posted was missing until
// you pulled to refresh.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:advent_connect_zw/screens/widgets/post_form_widgets.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

GoRouter _router(VoidCallback onCreated) => GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => Scaffold(
        floatingActionButton: PostFab(
          routeName: 'create',
          tooltip: 'Create',
          onCreated: onCreated,
        ),
      ),
      routes: [
        GoRoute(
          path: 'create',
          name: 'create',
          builder: (context, _) => Scaffold(
            body: Column(
              children: [
                TextButton(
                  onPressed: () => context.pop(true),
                  child: const Text('Save'),
                ),
                TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Back'),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  ],
);

void main() {
  testWidgets('saving calls onCreated; backing out does not', (t) async {
    var created = 0;
    await t.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: _router(() => created++),
      ),
    );

    await t.tap(find.byType(PostFab));
    await t.pumpAndSettle();
    await t.tap(find.text('Back'));
    await t.pumpAndSettle();
    expect(created, 0);

    await t.tap(find.byType(PostFab));
    await t.pumpAndSettle();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(created, 1);
  });
}
