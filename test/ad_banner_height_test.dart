import 'package:advent_connect_zw/widgets/ads/ad_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reported three times: *"the ads are not allowing me to use the screen"*,
/// then again after the shipped fix, then again for Jobs (founder, 3 Aug
/// 2026).
///
/// The banner is 320×50 and was never anything else — but it was wrapped in
/// a bare `Center`, and a bare `Center` shrink-wraps its height ONLY when
/// the incoming height constraint is unbounded.
///
///   * Inside a `Column` the vertical constraint IS unbounded, so it
///     shrink-wrapped. That is Home and Marketplace, which were fine, and
///     is why the bug never reproduced where anyone looked first.
///   * `Scaffold` lays `bottomNavigationBar` out with a LOOSE constraint
///     whose max is the entire scaffold height. Loose is still *bounded*,
///     so `Center` took the lot — a 50dp ad inside a full-screen bar, with
///     the actual screen pushed out of reach.
///
/// Every screen that put the banner straight into `bottomNavigationBar`
/// had it: Events and Churches (pushed, so `MainScaffold.showNav` is
/// false), Jobs, and Job details.
///
/// The earlier fix added `HideOnScroll` to that branch. That made the
/// full-height bar collapsible, which read as progress and shipped — but it
/// never addressed why the bar was full height, so the founder installed it
/// and saw no change.
const _adWidth = 320.0;
const _adHeight = 50.0;

Widget _frame({EdgeInsetsGeometry? padding}) => AdBannerFrame(
      width: _adWidth,
      height: _adHeight,
      padding: padding,
      child: const ColoredBox(color: Color(0xFF00FF00)),
    );

void main() {
  testWidgets('a banner in bottomNavigationBar is 50dp, not the screen',
      (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 720 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(),
          // Exactly how Jobs, Job details, Events and Churches place it.
          bottomNavigationBar: SafeArea(top: false, child: _frame()),
        ),
      ),
    );

    final size = tester.getSize(find.byType(AdBannerFrame));
    expect(
      size.height,
      _adHeight,
      reason: 'the ad must occupy its own height and nothing more',
    );
    // The specific failure: it used to be the whole 720dp screen.
    expect(size.height, lessThan(100));
  });

  testWidgets('padding adds only its own height', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: SafeArea(
            top: false,
            child: _frame(padding: const EdgeInsets.symmetric(vertical: 6)),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(AdBannerFrame)).height, _adHeight + 12);
  });

  testWidgets('inside a Column it still hugs its height', (tester) async {
    // Home and Marketplace. This path was always correct and must stay so.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [_frame(), const SizedBox(height: 56)],
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(AdBannerFrame)).height, _adHeight);
  });

  testWidgets('still spans the full width so the ad stays centred',
      (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 720 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: SafeArea(top: false, child: _frame()),
        ),
      ),
    );

    expect(tester.getSize(find.byType(AdBannerFrame)).width, 360);
  });
}
