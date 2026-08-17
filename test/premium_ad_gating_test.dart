// What a subscriber actually pays for.
//
// Hiding a loaded ad is not the deal — the fetch, the impression call and
// the battery are already spent by then. These tests pin the stronger
// contract: while premium is active the ad widgets render nothing AND
// never take a claim on an ad view at all, and a banner already on screen
// when the purchase lands disappears without a rebuild from above.
//
// Rewritten for Appodeal (18 Aug 2026). The gate itself is unchanged and
// deliberately provider-agnostic — what changed is that there is no ad
// OBJECT to look for any more. Appodeal's banner is a platform view onto a
// single shared native view, so "did this widget ask for an ad" is now
// "did it claim the slot".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/ads/ad_view_slot.dart';
import 'package:advent_connect_zw/services/ads/ads_service.dart';
import 'package:advent_connect_zw/services/premium_service.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/ads/ad_banner.dart';
import 'package:advent_connect_zw/widgets/ads/feed_ad_card.dart';

Future<void> _pump(WidgetTester t, Widget child) async {
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: Center(child: child)),
  ));
  await t.pump();
}

void main() {
  setUp(() {
    PremiumService.debugReset();
    AdsService.debugSetReady(false);
    AdViewSlot.debugResetAll();
  });

  tearDown(() {
    PremiumService.debugReset();
    AdsService.debugSetReady(false);
    AdViewSlot.debugResetAll();
  });

  group('AdBanner', () {
    testWidgets('renders nothing and claims no ad view while premium',
        (t) async {
      PremiumService.debugSet(premium: true);
      await _pump(t, const AdBanner());

      expect(t.getSize(find.byType(AdBanner)), Size.zero);
      expect(AdViewSlot.banner.debugClaimCount, 0,
          reason: 'a subscriber must not even take a claim on the ad view');
      // No retry loop was armed — a subscriber's widget doesn't sit there
      // asking for an ad it will never be allowed to show.
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('takes zero height for a free user with no ad available',
        (t) async {
      PremiumService.debugSet(premium: false);
      await _pump(t, const AdBanner());

      expect(t.getSize(find.byType(AdBanner)), Size.zero,
          reason: 'a missed ad must never reserve empty space');
    });

    testWidgets('occupies exactly the ad height once one is available',
        (t) async {
      // The whole point of the frame: 50dp, never the screen. Pinned here
      // as well as in ad_banner_height_test because this is the path that
      // actually mounts the platform view.
      PremiumService.debugSet(premium: false);
      AdsService.debugSetReady(true);
      await _pump(t, const AdBanner());

      AdsService.bannerAvailable.value = true;
      await t.pump();

      expect(t.getSize(find.byType(AdBannerFrame)).height, kAdBannerHeight);
    });

    testWidgets('a visible banner disappears the moment premium starts',
        (t) async {
      PremiumService.debugSet(premium: false);
      AdsService.debugSetReady(true);
      await _pump(t, const AdBanner());
      AdsService.bannerAvailable.value = true;
      await t.pump();
      expect(t.getSize(find.byType(AdBanner)).height, kAdBannerHeight);

      // The purchase lands while the banner is on screen. Nothing above
      // this widget rebuilds — it has to react on its own.
      PremiumService.debugSet(premium: true);
      await t.pump();

      expect(t.getSize(find.byType(AdBanner)), Size.zero);
      expect(AdViewSlot.banner.debugClaimCount, 0,
          reason: 'the slot must be handed back so another screen can use it');
    });
  });

  group('FeedAdCard', () {
    testWidgets('renders nothing and claims no ad view while premium',
        (t) async {
      PremiumService.debugSet(premium: true);
      await _pump(t, const FeedAdCard());

      expect(t.getSize(find.byType(FeedAdCard)), Size.zero);
      expect(AdViewSlot.mrec.debugClaimCount, 0);
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('leaves no gap in the feed for a free user with no ad',
        (t) async {
      PremiumService.debugSet(premium: false);
      await _pump(t, const FeedAdCard());

      expect(t.getSize(find.byType(FeedAdCard)), Size.zero);
    });
  });

  group('text scaling', () {
    // House rule: every screen is checked at 1.0x / 1.6x / 2.5x on a
    // 360dp phone. The sponsored card grew a "Sponsored" label when the
    // native template went away, so this now guards real text.
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

      testWidgets('sponsored card label survives ${scale}x', (t) async {
        PremiumService.debugSet(premium: false);
        AdsService.debugSetReady(true);
        await t.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(360, 780),
              textScaler: TextScaler.linear(scale),
            ),
            child: const Scaffold(
              body: SingleChildScrollView(child: FeedAdCard()),
            ),
          ),
        ));
        await t.pump();
        AdsService.mrecAvailable.value = true;
        await t.pump();

        expect(t.takeException(), isNull,
            reason: 'no overflow at ${scale}x on a 360dp phone');
        expect(find.text('Sponsored'), findsOneWidget);
      });
    }
  });
}
