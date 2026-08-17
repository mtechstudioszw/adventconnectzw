// Appodeal hands out ONE banner view and ONE MREC view per process.
//
// Found by reading the plugin's own Android source
// (stack_appodeal_flutter 4.2.0, AppodealAdView.kt): the views live in
// static WeakReferences, and every new platform view begins by ripping the
// view out of whatever parent already had it. So a second AdBanner does not
// get a second ad — it blanks the first one.
//
// That is not hypothetical. Pushing Jobs on top of Home leaves BOTH routes
// mounted, because Navigator keeps a covered route alive, and both of those
// screens place a banner.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/ads/ad_view_slot.dart';
import 'package:advent_connect_zw/services/ads/ads_service.dart';
import 'package:advent_connect_zw/services/premium_service.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/ads/ad_banner.dart';

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

  group('AdViewSlot', () {
    test('the newest claim wins, because it is the one on screen', () async {
      final first = AdViewSlot.banner.claim();
      await Future<void>.delayed(Duration.zero);
      expect(first.isActive.value, isTrue);

      final second = AdViewSlot.banner.claim();
      await Future<void>.delayed(Duration.zero);
      expect(second.isActive.value, isTrue);
      expect(first.isActive.value, isFalse,
          reason: 'the covered screen must stop mounting the shared view');

      // Popping back returns the view to the screen underneath.
      second.release();
      await Future<void>.delayed(Duration.zero);
      expect(first.isActive.value, isTrue);

      first.release();
      expect(AdViewSlot.banner.debugClaimCount, 0);
    });

    test('banner and MREC are independent — they are different views',
        () async {
      final banner = AdViewSlot.banner.claim();
      final mrec = AdViewSlot.mrec.claim();
      await Future<void>.delayed(Duration.zero);

      expect(banner.isActive.value, isTrue);
      expect(mrec.isActive.value, isTrue,
          reason: 'a 320x50 banner and a 300x250 MREC can coexist');

      banner.release();
      mrec.release();
    });

    test('releasing twice is safe', () async {
      final claim = AdViewSlot.banner.claim();
      await Future<void>.delayed(Duration.zero);
      claim.release();
      expect(claim.release, returnsNormally);
    });
  });

  testWidgets('only one of two mounted banners renders the ad view',
      (t) async {
    PremiumService.debugSet(premium: false);
    AdsService.debugSetReady(true);

    // Home's banner and a pushed screen's banner, both alive at once.
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
        body: Column(children: [AdBanner(), AdBanner()]),
      ),
    ));
    await t.pump();
    AdsService.bannerAvailable.value = true;
    await t.pump();

    // Two AdBanner widgets, but only one of them has any height — the
    // other must render nothing rather than an empty 50dp box.
    final sizes = t
        .widgetList<AdBanner>(find.byType(AdBanner))
        .map((w) => t.getSize(find.byWidget(w)).height)
        .toList();
    expect(sizes.length, 2);
    expect(sizes.where((h) => h == kAdBannerHeight).length, 1,
        reason: 'exactly one banner may mount the shared native view');
    expect(sizes.where((h) => h == 0).length, 1);
  });
}
