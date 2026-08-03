// "The ads are not allowing me to use the screen" (Events, 3 Aug 2026).
//
// Two bugs stacked, both invisible in code review:
//
//  1. MainScaffold only wrapped the banner in HideOnScroll on the
//     showNav:true branch. Pushed screens (Events, Churches) pinned the
//     banner to the bottom forever.
//  2. NavVisibilityMixin ignored any scroll notification with depth != 0.
//     A TabBarView is a horizontal PageView, so the vertical list inside
//     it reports at depth 1 — every scroll on Events was discarded and
//     the bar could never hide even where HideOnScroll was wired.
//
// Neither throws. The only symptom is an ad that never goes away.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/widgets/main_scaffold.dart';
import 'package:advent_connect_zw/services/premium_service.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/ads/ad_banner.dart';
import 'package:advent_connect_zw/widgets/ads/scroll_aware_ad_footer.dart';
import 'package:advent_connect_zw/widgets/motion/hide_on_scroll.dart';

/// A screen shaped like Events: a header stack, then a TabBarView whose
/// pages are the scrolling lists.
class _TabbedScreen extends StatefulWidget {
  const _TabbedScreen({required this.showNav});
  final bool showNav;

  @override
  State<_TabbedScreen> createState() => _TabbedScreenState();
}

class _TabbedScreenState extends State<_TabbedScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MainScaffold(
      title: 'Events',
      currentIndex: 0,
      showNav: widget.showNav,
      body: Column(
        children: [
          const SizedBox(height: 60, child: Text('header')),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                ListView.builder(
                  itemCount: 40,
                  itemBuilder: (_, i) => SizedBox(height: 80, child: Text('e$i')),
                ),
                const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void main() {
  setUp(() {
    // Premium makes AdBanner bail before it arms its 6-second retry
    // loop, which would otherwise leave pending timers at teardown.
    // This is a layout test — the collapse behaviour is identical
    // either way, and HideOnScroll still wraps the (empty) banner.
    PremiumService.debugSet(premium: true);
  });

  tearDown(PremiumService.debugReset);

  group('NavVisibilityMixin decides on axis, not depth', () {
    testWidgets(
        'a vertical list nested in a TabBarView still collapses the bar',
        (t) async {
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const _TabbedScreen(showNav: true),
      ));
      await t.pump();

      double heightFactor() => t
          .widgetList<Align>(find.descendant(
            of: find.byType(HideOnScroll),
            matching: find.byType(Align),
          ))
          .first
          .heightFactor!;

      expect(heightFactor(), 1.0, reason: 'bar starts visible');

      // Scroll the list DOWN (finger up). Before the fix this scroll was
      // discarded at depth 1 and the bar stayed at 1.0 forever.
      await t.drag(find.text('e2'), const Offset(0, -300));
      await t.pumpAndSettle();

      expect(heightFactor(), 0.0,
          reason: 'scrolling down must hand the space back to the list');

      // Any scroll up brings it straight back.
      await t.drag(find.byType(ListView), const Offset(0, 300));
      await t.pumpAndSettle();

      expect(heightFactor(), 1.0, reason: 'scrolling up restores the bar');
    });

    testWidgets('a PUSHED screen (showNav:false) also collapses its banner',
        (t) async {
      // Events and Churches. Before the fix this branch had no
      // HideOnScroll at all, so the banner was pinned permanently.
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const _TabbedScreen(showNav: false),
      ));
      await t.pump();

      expect(find.byType(HideOnScroll), findsOneWidget,
          reason: 'a pushed screen with ads must still be able to hide them');
    });
  });

  group('ScrollAwareAdFooter', _footerTests);

  group('horizontal scrollables still must not drive the nav', () {
    testWidgets('a stories-style rail leaves the bar alone', (t) async {
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: MainScaffold(
          title: 'Home',
          currentIndex: 0,
          body: Column(
            children: [
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: 30,
                  itemBuilder: (_, i) =>
                      SizedBox(width: 80, child: Text('story$i')),
                ),
              ),
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
      ));
      await t.pump();

      double heightFactor() => t
          .widgetList<Align>(find.descendant(
            of: find.byType(HideOnScroll),
            matching: find.byType(Align),
          ))
          .first
          .heightFactor!;

      await t.drag(find.text('story2'), const Offset(-300, 0));
      await t.pumpAndSettle();

      expect(heightFactor(), 1.0,
          reason: 'swiping a horizontal rail must not hide the bottom nav');
    });
  });
}

// ---------------------------------------------------------------------
//  ScrollAwareAdFooter — the drop-in that makes the previously-reverted
//  detail-screen placements viable again.
// ---------------------------------------------------------------------
void _footerTests() {
  testWidgets('the footer banner collapses on scroll down and returns on up',
      (t) async {
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ScrollAwareAdFooter(
          child: ListView.builder(
            itemCount: 40,
            itemBuilder: (_, i) => SizedBox(height: 80, child: Text('row$i')),
          ),
        ),
      ),
    ));
    await t.pump();

    double heightFactor() => t
        .widgetList<Align>(find.descendant(
          of: find.byType(HideOnScroll),
          matching: find.byType(Align),
        ))
        .first
        .heightFactor!;

    expect(heightFactor(), 1.0);

    await t.drag(find.text('row2'), const Offset(0, -300));
    await t.pumpAndSettle();
    expect(heightFactor(), 0.0,
        reason: 'a detail screen must be able to reclaim the ad space');

    await t.drag(find.byType(ListView), const Offset(0, 300));
    await t.pumpAndSettle();
    expect(heightFactor(), 1.0);
  });

  testWidgets('enabled:false renders the body untouched — no ad at all',
      (t) async {
    // Chat, auth and Prayer. The opt-out is explicit at the call site so
    // it cannot be "fixed" later by someone adding an ad back.
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
        body: ScrollAwareAdFooter(
          enabled: false,
          child: Center(child: Text('chat body')),
        ),
      ),
    ));
    await t.pump();

    expect(find.text('chat body'), findsOneWidget);
    expect(find.byType(HideOnScroll), findsNothing);
    expect(find.byType(AdBanner), findsNothing);
  });
}
