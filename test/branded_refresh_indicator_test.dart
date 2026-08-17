// Founder, 19 Aug 2026: *"the refesh of egw dosent work"*, then *"if u swipe
// down it dosent refresh"* — so the PULL ITSELF is doing nothing, not the
// fetch behind it.
//
// `BrandedRefreshIndicator` is hand-rolled on scroll notifications rather
// than being Material's `RefreshIndicator`, so nothing about it is
// guaranteed by the framework. This pins the one thing every call site
// assumes: that dragging down past the top actually calls `onRefresh`.
//
// The EGW shelf is the interesting case and the reason this file exists.
// Its content is SHORT — production has very few EGW books — so its scroll
// view has nothing to scroll, which is exactly the condition under which a
// notification-driven indicator is most likely to never see an event.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/widgets/motion/branded_refresh_indicator.dart';

void main() {
  Future<bool> pullOn(WidgetTester t, Widget scrollable) async {
    var called = false;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrandedRefreshIndicator(
            onRefresh: () async => called = true,
            child: scrollable,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();

    // Well past the 88px arm distance once the 0.55 damping is applied.
    await t.drag(find.byType(Scrollable).first, const Offset(0, 320));
    await t.pumpAndSettle();
    return called;
  }

  testWidgets('a long list refreshes when pulled', (t) async {
    expect(
      await pullOn(
        t,
        ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < 40; i++) SizedBox(height: 60, child: Text('$i')),
          ],
        ),
      ),
      isTrue,
    );
  });

  testWidgets('a CustomScrollView refreshes when pulled', (t) async {
    // The shape every Library tab actually uses.
    expect(
      await pullOn(
        t,
        CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverList.builder(
              itemCount: 40,
              itemBuilder: (_, i) => SizedBox(height: 60, child: Text('$i')),
            ),
          ],
        ),
      ),
      isTrue,
    );
  });

  testWidgets('a shelf too short to scroll still refreshes', (t) async {
    // The EGW shelf in production: a handful of books, so the content is
    // shorter than the viewport and there is no scroll range at all.
    expect(
      await pullOn(
        t,
        CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverList.builder(
              itemCount: 2,
              itemBuilder: (_, i) => SizedBox(height: 60, child: Text('$i')),
            ),
          ],
        ),
      ),
      isTrue,
    );
  });

  testWidgets('an empty shelf still refreshes', (t) async {
    // `_emptyShelf` — nothing to show, and the ONLY way back to content is
    // the pull. If it does not fire here it is a dead end.
    expect(
      await pullOn(
        t,
        ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [SizedBox(height: 100), Text('Nothing here yet')],
        ),
      ),
      isTrue,
    );
  });

  testWidgets('a small drag does not refresh', (t) async {
    var called = false;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrandedRefreshIndicator(
            onRefresh: () async => called = true,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < 40; i++)
                  SizedBox(height: 60, child: Text('$i')),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();

    await t.drag(find.byType(Scrollable).first, const Offset(0, 20));
    await t.pumpAndSettle();
    expect(called, isFalse, reason: 'a nudge must not trigger a refresh');
  });
}
