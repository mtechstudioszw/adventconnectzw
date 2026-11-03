// Home's floating "+" (owner, 3 Nov 2026): rides just above the island,
// drops into the island's place while it is hidden, can be dragged
// anywhere, and snaps to the nearest side keeping its height.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/widgets/main_bottom_nav.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/home/island_create_fab.dart';

const _w = 412.0, _h = 800.0;

Widget _app({required bool visible, VoidCallback? onTap}) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: Colors.blueGrey)),
        Positioned.fill(
          child: IslandCreateFab(islandVisible: visible, onTap: onTap ?? () {}),
        ),
      ],
    ),
  ),
);

Rect _fab(WidgetTester t) => t.getRect(find.byTooltip('Create a post'));

Future<void> _size(WidgetTester t) async {
  t.view.physicalSize = const Size(_w, _h);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

void main() {
  testWidgets('rests just above the island, on the right', (t) async {
    await _size(t);
    await t.pumpWidget(_app(visible: true));
    await t.pumpAndSettle();
    final r = _fab(t);
    expect(_h - r.bottom, IslandCreateFab.restingBottom(islandVisible: true));
    expect(r.right, _w - IslandCreateFab.sideMargin);
    // Clear of the island's top edge (12 + 62 from the bottom).
    expect(_h - r.bottom, greaterThan(12 + 62));
  });

  testWidgets('drops into the island\'s place when it hides, and back', (
    t,
  ) async {
    await _size(t);
    await t.pumpWidget(_app(visible: true));
    await t.pumpAndSettle();
    final up = _fab(t).bottom;

    await t.pumpWidget(_app(visible: false));
    await t.pumpAndSettle();
    final down = _fab(t);
    expect(
      _h - down.bottom,
      IslandCreateFab.restingBottom(islandVisible: false),
    );
    // Centred where the 62dp island was.
    expect(down.center.dy, closeTo(_h - 12 - 31, 0.5));
    expect(down.bottom, greaterThan(up));

    await t.pumpWidget(_app(visible: true));
    await t.pumpAndSettle();
    expect(_fab(t).bottom, up);
  });

  testWidgets('drag: snaps to the nearest side and keeps its height', (
    t,
  ) async {
    await _size(t);
    await t.pumpWidget(_app(visible: true));
    await t.pumpAndSettle();
    final start = _fab(t);

    await t.drag(find.byTooltip('Create a post'), const Offset(-300, -200));
    await t.pumpAndSettle();
    final r = _fab(t);
    expect(r.left, IslandCreateFab.sideMargin); // snapped left
    expect(start.bottom - r.bottom, closeTo(200, 1)); // kept the lift

    // Hiding the island drops it by the same amount, keeping the lift.
    await t.pumpWidget(_app(visible: false));
    await t.pumpAndSettle();
    final drop =
        IslandCreateFab.restingBottom(islandVisible: true) -
        IslandCreateFab.restingBottom(islandVisible: false);
    expect(_fab(t).bottom - r.bottom, closeTo(drop, 1));
  });

  testWidgets('never dragged below its spot above the island', (t) async {
    await _size(t);
    await t.pumpWidget(_app(visible: true));
    await t.pumpAndSettle();
    final start = _fab(t);
    await t.drag(find.byTooltip('Create a post'), const Offset(0, 300));
    await t.pumpAndSettle();
    expect(_fab(t).bottom, start.bottom);
  });

  testWidgets('tap opens create', (t) async {
    await _size(t);
    var taps = 0;
    await t.pumpWidget(_app(visible: true, onTap: () => taps++));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Create a post'));
    await t.pump(const Duration(milliseconds: 300));
    expect(taps, 1);
  });

  // The island itself: small phones get an icon-only pill, never "Ho…".
  Future<void> nav(WidgetTester t, double width) async {
    t.view.physicalSize = Size(width, 760);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          bottomNavigationBar: MainBottomNav(currentIndex: 0),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 400));
  }

  testWidgets('very narrow island: icon-only pill', (t) async {
    await nav(t, 300);
    expect(find.text('Home'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('normal phone keeps the label', (t) async {
    await nav(t, 360);
    expect(find.text('Home'), findsOneWidget);
  });
}
