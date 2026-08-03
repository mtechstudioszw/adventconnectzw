// What a subscriber actually pays for.
//
// Hiding a loaded ad is not the deal — the fetch, the impression call and
// the battery are already spent by then. These tests pin the stronger
// contract: while premium is active the ad widgets render nothing AND
// never construct an ad object at all, and a banner already on screen
// when the purchase lands disappears without a rebuild from above.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'package:advent_connect_zw/services/ads/ads_service.dart';
import 'package:advent_connect_zw/services/premium_service.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/ads/ad_banner.dart';
import 'package:advent_connect_zw/widgets/ads/native_ad_card.dart';

Future<void> _pump(WidgetTester t, Widget child) async {
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: Center(child: child)),
  ));
  await t.pump();
}

/// The free-user path retries for ~6s waiting on an ad SDK that never
/// initialises in a test. Drain those timers so the widget can be torn
/// down without "a Timer is still pending".
Future<void> _drainRetries(WidgetTester t) =>
    t.pump(const Duration(seconds: 8));

void main() {
  setUp(() {
    PremiumService.debugReset();
    AdsService.debugSetReady(false);
  });

  tearDown(() {
    PremiumService.debugReset();
    AdsService.debugSetReady(false);
  });

  group('AdBanner', () {
    testWidgets('renders nothing and builds no ad while premium', (t) async {
      PremiumService.debugSet(premium: true);
      await _pump(t, const AdBanner());

      expect(find.byType(AdWidget), findsNothing);
      expect(t.getSize(find.byType(AdBanner)), Size.zero);
      // No retry loop was armed — a subscriber's widget doesn't sit there
      // asking every second for an ad it will never be allowed to show.
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('takes zero height for a free user with no ad loaded',
        (t) async {
      PremiumService.debugSet(premium: false);
      await _pump(t, const AdBanner());

      expect(find.byType(AdWidget), findsNothing);
      expect(t.getSize(find.byType(AdBanner)), Size.zero,
          reason: 'a missed ad must never reserve empty space');
      await _drainRetries(t);
    });

    testWidgets('a visible banner disappears the moment premium starts',
        (t) async {
      PremiumService.debugSet(premium: false);
      await _pump(t, const AdBanner());

      // The purchase lands while the banner is on screen. Nothing above
      // this widget rebuilds — it has to react on its own.
      PremiumService.debugSet(premium: true);
      await t.pump();

      expect(find.byType(AdWidget), findsNothing);
      expect(t.getSize(find.byType(AdBanner)), Size.zero);
      await _drainRetries(t);
    });
  });

  group('NativeAdCard', () {
    testWidgets('renders nothing and builds no ad while premium', (t) async {
      PremiumService.debugSet(premium: true);
      await _pump(t, const NativeAdCard());

      expect(find.byType(AdWidget), findsNothing);
      expect(t.getSize(find.byType(NativeAdCard)), Size.zero);
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('leaves no gap in the feed for a free user with no ad',
        (t) async {
      PremiumService.debugSet(premium: false);
      await _pump(t, const NativeAdCard());

      expect(t.getSize(find.byType(NativeAdCard)), Size.zero);
      await _drainRetries(t);
    });
  });

  group('text scaling', () {
    // House rule: every screen is checked at 1.0x / 1.6x / 2.5x on a
    // 360dp phone. A zero-height widget can't overflow, but the check is
    // cheap and it fails loudly if either widget ever grows a fixed-height
    // box with text in it.
    for (final scale in const [1.0, 1.6, 2.5]) {
      testWidgets('premium banner stays collapsed at ${scale}x', (t) async {
        PremiumService.debugSet(premium: true);
        await t.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(360, 780),
              textScaler: TextScaler.linear(scale),
            ),
            child: const Scaffold(body: Center(child: AdBanner())),
          ),
        ));
        await t.pump();

        expect(t.takeException(), isNull,
            reason: 'no overflow at ${scale}x on a 360dp phone');
        expect(t.getSize(find.byType(AdBanner)), Size.zero);
      });
    }
  });
}
