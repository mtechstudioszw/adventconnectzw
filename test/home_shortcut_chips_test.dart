// The three chips under the composer are navigation, not authoring.
//
// The founder reported (2 Aug 2026) that tapping **Events** opened the
// "create an event" composer. It did: Home wired `onEvent` to
// `_handleCreate(CreateKind.event)` while its two neighbours pushed
// routes. Nothing threw and nothing looked wrong — the chip simply went
// somewhere else. A layout test cannot catch that, so this one asserts
// the wiring itself: each chip fires its own callback and no other.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/home/composer_entry.dart';

void main() {
  testWidgets('each shortcut chip fires its own callback', (t) async {
    t.view.physicalSize = const Size(360, 720);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    final fired = <String>[];
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: HomeShortcutChips(
          onChurches: () => fired.add('churches'),
          onEvents: () => fired.add('events'),
          onDonate: () => fired.add('donate'),
        ),
      ),
    ));

    await t.tap(find.text('Events'));
    await t.pump();
    expect(fired, ['events']);

    await t.tap(find.text('Churches'));
    await t.pump();
    await t.tap(find.text('Donate'));
    await t.pump();
    expect(fired, ['events', 'churches', 'donate']);
    expect(t.takeException(), isNull);
  });

  for (final scale in <double>[1.0, 1.6, 2.5]) {
    testWidgets('shortcut chips lay out at ${scale}x text scale', (t) async {
      t.view.physicalSize = const Size(360, 720);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: HomeShortcutChips(
              onChurches: () {},
              onEvents: () {},
              onDonate: () {},
            ),
          ),
        ),
      ));

      expect(t.takeException(), isNull);
      expect(find.text('Events'), findsOneWidget);
    });
  }
}
