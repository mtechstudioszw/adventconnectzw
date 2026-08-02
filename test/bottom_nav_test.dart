// The island must never claim a tab the member is not on.
//
// Founder report, 2 Aug 2026: opening Prayer lit the **Profile** pill.
// It was deliberate once — Prayer is reached from Profile's "My prayers",
// so the screen passed `currentIndex: 4` — but Prayer is also reached
// from Home, and either way the bar was saying "you are in Profile" while
// the member was reading prayers. Tapping that lit pill did nothing,
// because the code treats a tap on the active tab as a reselect.
//
// The sibling complaint was that Church and Prayer "show tabs that aren't
// real". Churches passed `currentIndex: -1`, which renders the island with
// no pill lit at all — still a tab bar, now claiming you are nowhere.
// Both are now PUSHED screens that hide the island entirely and rely on a
// back button, the convention Events set on 27 Jul.
//
// These tests cover the reselect behaviour that made the wrong highlight
// actively broken, plus the -1 contract, since the widget is shared by
// every tab.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/widgets/main_bottom_nav.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

Future<void> _pump(WidgetTester t, int index, {VoidCallback? onReselect}) async {
  t.view.physicalSize = const Size(360, 720);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  await t.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      bottomNavigationBar:
          MainBottomNav(currentIndex: index, onReselect: onReselect),
    ),
  ));
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('only the active tab shows its label', (t) async {
    await _pump(t, 0);

    // Inactive tabs are icon-only; the active one expands into a labelled
    // pill. So the label set is exactly one item.
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Watch'), findsNothing);
    expect(find.text('Profile'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('index -1 lights nothing', (t) async {
    await _pump(t, -1);

    for (final label in ['Home', 'Watch', 'Chat', 'Marketplace', 'Profile']) {
      expect(find.text(label), findsNothing, reason: '$label should be inert');
    }
  });

  testWidgets('tapping the active tab reselects rather than navigating',
      (t) async {
    var reselected = 0;
    await _pump(t, 0, onReselect: () => reselected++);

    await t.tap(find.text('Home'));
    await t.pump();

    // This is why a wrong currentIndex was worse than a missing one: the
    // lit pill swallows its own tap. On Prayer, the lit Profile pill did
    // nothing at all.
    expect(reselected, 1);
  });

  testWidgets('lays out at 360dp with the widest label active', (t) async {
    // Marketplace is the long one — the label that forced five tabs to
    // drop their labels in the first place.
    await _pump(t, 3);

    expect(find.text('Marketplace'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
