// Founder, 19 Aug 2026: *"the refesh of egw dosent work"* / *"if u swipe
// down it dosent refresh"*.
//
// `branded_refresh_indicator_test.dart` already proves the indicator itself
// fires for every scroll-view shape the Library uses, including a shelf too
// short to scroll and an empty one. So the fault is in the EGW tab, and this
// pumps the real thing to find it.
//
// The tab reaches Supabase through `LibraryService`, which throws without an
// initialised client and falls back to its cache — so it renders offline
// here exactly as it does on a phone with no signal.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/library/egw_tab.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

void main() {
  Future<void> pumpTab(WidgetTester t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: EgwTab()),
      ),
    );
    // Let the failed fetch settle back to the empty shelf.
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
  }

  testWidgets('the shelf offers something to pull on', (t) async {
    await pumpTab(t);

    // Whatever state the shelf lands in, there must be a scrollable — a bare
    // `Center(BrandSpinner)` has no scroll notifications to give, so a pull
    // is silently impossible and the only way to retry is to leave the tab.
    expect(
      find.byType(Scrollable),
      findsWidgets,
      reason: 'nothing to pull on means refresh cannot work at all',
    );
  });

  testWidgets('pulling down does not throw out of _refresh', (t) async {
    // This is the bug, and it is a one-character one.
    //
    //     setState(() => _future = future)
    //
    // is an ARROW body, so it returns the value it assigns — a Future — and
    // `setState` asserts against exactly that, since it is how
    // `setState(() async {…})` gets caught. The assert fires after the
    // assignment but before `markNeedsBuild()`, and the throw escapes
    // `_refresh` so its `await future` never runs. The refresh indicator
    // awaits `onRefresh` to know how long to spin, so it was handed an
    // exception instead and settled instantly however long the fetch took.
    //
    // CI ships a DEBUG apk, so this fired on the founder's phone on every
    // single pull: *"if u swipe down it dosent refresh"*.
    await pumpTab(t);

    await t.drag(find.byType(Scrollable).first, const Offset(0, 320));
    await t.pump();
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
  });
}
