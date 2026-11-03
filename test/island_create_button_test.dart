// Home's "+" joins the island (owner, 3 Nov 2026): a round frosted button
// beside the bar, same height. These cover the layout promises: no
// overflow at 360dp, the "+" is there only when asked for, it fires, and a
// too-narrow island shows an icon-only pill instead of a clipped label.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/widgets/main_bottom_nav.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

Future<void> _pump(
  WidgetTester t, {
  required double width,
  int index = 0,
  VoidCallback? onCreate,
}) async {
  t.view.physicalSize = Size(width, 760);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: const ColoredBox(color: Colors.blueGrey),
        bottomNavigationBar: MainBottomNav(
          currentIndex: index,
          onCreate: onCreate,
        ),
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  for (final width in [320.0, 360.0, 412.0]) {
    testWidgets('fits at ${width.toInt()}dp with the + (no overflow)', (
      t,
    ) async {
      await _pump(t, width: width, onCreate: () {});
      expect(t.takeException(), isNull);
      expect(find.byTooltip('Create a post'), findsOneWidget);
    });
  }

  testWidgets('the + matches the island height and fires', (t) async {
    var taps = 0;
    await _pump(t, width: 412, onCreate: () => taps++);
    final plus = t.getSize(find.byTooltip('Create a post'));
    expect(plus.height, 62);
    await t.tap(find.byTooltip('Create a post'));
    await t.pump(const Duration(milliseconds: 300));
    expect(taps, 1);
  });

  testWidgets('no + unless asked for (other tabs)', (t) async {
    await _pump(t, width: 412, index: 2);
    expect(find.byTooltip('Create a post'), findsNothing);
  });

  testWidgets('narrow island: icon-only pill, never a clipped label', (
    t,
  ) async {
    await _pump(t, width: 320, onCreate: () {});
    expect(find.text('Home'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('wide phone keeps the label', (t) async {
    await _pump(t, width: 430, onCreate: () {});
    expect(find.text('Home'), findsOneWidget);
  });
}
