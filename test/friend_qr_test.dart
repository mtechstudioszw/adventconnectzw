// The friend QR's scanning budget.
//
// The logo used to be painted straight over the code by qr_flutter's
// `embeddedImage`, so dark modules showed through around the mark and it
// had no quiet zone — the "logo laid over the QR" the founder reported on
// 2 Aug 2026. It is now a solid white plate punched through the middle
// with the mark seated inside it.
//
// A round hole in a QR code is a data loss, so the geometry is a budget
// rather than a style choice. The shipped numbers were checked by
// generating the real payload at level H, painting the identical circular
// occlusion over it and decoding the pixels:
//
//     plate= 62dp  covers  6.8%  ->  DECODED OK   <- shipped
//     plate= 70dp  covers  8.7%  ->  DECODED OK
//     plate= 80dp  covers 11.4%  ->  DECODED OK
//     plate= 90dp  covers 14.4%  ->  DECODED OK
//     plate=100dp  covers 17.8%  ->  DECODED OK
//     plate=110dp  covers 21.5%  ->  FAILED TO DECODE
//     plate=120dp  covers 25.6%  ->  FAILED TO DECODE
//
// So the code stops decoding somewhere between 17.8% and 21.5% coverage,
// and the shipped plate sits at 6.8% — roughly 2.6x of headroom. This
// test fails if a later tweak spends it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/config/share_config.dart';
import 'package:advent_connect_zw/theme/app_colors.dart';
import 'package:advent_connect_zw/widgets/friend_qr_sheet.dart';

void main() {
  group('QR occlusion budget', () {
    test('the shipped plate covers well under the measured failure point',
        () {
      final fraction = qrOcclusionFraction();

      expect(fraction, closeTo(0.068, 0.002));
      // The measured cliff is ~0.18–0.215. Half of the lower bound is the
      // line: past it, a scan starts depending on the reader.
      expect(fraction, lessThan(0.09),
          reason: 'the plate is eating the level-H recovery budget; '
              'decoding was measured to fail by 21.5% coverage');
    });

    test('the mark leaves a real quiet zone inside the plate', () {
      // The white ring between plate edge and mark is what makes it a
      // punched hole rather than a sticker. Without it the logo's edge
      // touches live modules.
      expect(kQrLogo, lessThan(kQrPlate));
      final ring = (kQrPlate - kQrLogo) / 2;
      expect(ring, greaterThanOrEqualTo(6),
          reason: 'a thinner ring stops reading as a quiet zone');
    });

    test('growing the plate costs budget as the square of its radius', () {
      // Guards the intuition, not the framework: doubling the plate is 4x
      // the data loss, which is why a "slightly bigger logo" is not a
      // small change.
      final small = qrOcclusionFraction(plate: 50);
      final double_ = qrOcclusionFraction(plate: 100);

      expect(double_ / small, closeTo(4.0, 0.01));
    });
  });

  group('the centre mark is actually visible', () {
    // Regression, 3 Aug 2026. assets/icon/logo.png is a WHITE wordmark on
    // a fully transparent background, and it was being drawn straight onto
    // the code's WHITE centre plate — so the middle of every friend code
    // was a blank white dot. Nothing threw and nothing looked broken in
    // code review; it just quietly had no logo in it.
    testWidgets('seats the mark on a filled disc, not on bare white', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: kQrLogo,
                height: kQrLogo,
                child: QrCentreMark(),
              ),
            ),
          ),
        ),
      );

      final decoration = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.shape == BoxShape.circle);

      expect(
        decoration.color,
        isNotNull,
        reason: 'the disc behind the wordmark is what makes it visible',
      );
      expect(
        decoration.color,
        isNot(AppColors.white),
        reason: 'a white disc under a white wordmark is the original bug',
      );
      // Contrast against the plate is the actual requirement.
      expect(decoration.color!.computeLuminance(), lessThan(0.3));
    });

    testWidgets('keeps the whole wordmark rather than cropping it', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: kQrLogo,
                height: kQrLogo,
                child: QrCentreMark(),
              ),
            ),
          ),
        ),
      );

      // The mark is 2:1. BoxFit.cover on a square box would crop its ends
      // off and leave an unreadable middle slice.
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.contain);
    });
  });

  group('friendQrPayload', () {
    // Whichever form is switched on, the QR must encode something the
    // scanner can read back. Asserting on the flag rather than on one shape
    // means flipping it does not silently leave this test passing against
    // the form nobody ships.
    test('encodes the form the flag selects', () {
      final payload = friendQrPayload('abc-123');

      if (kFriendQrUsesLandingPage) {
        expect(payload, startsWith('https://'));
        expect(payload, endsWith('/u/abc-123'));
      } else {
        expect(payload, 'io.supabase.adventconnect://user/abc-123');
      }
    });

    // The https form is written and tested even while it is switched off, so
    // turning it on after the worker is deployed is a one-line change and
    // not a re-implementation.
    test('the https landing form round-trips, ready for the switch', () {
      expect(friendIdFromScan(friendShareUrl('abc-123')), 'abc-123');
    });

    test('the scanner reads back what the generator writes', () {
      expect(friendIdFromScan(friendQrPayload('abc-123')), 'abc-123');
    });

    test('codes already shared in the old format still scan', () {
      expect(
        friendIdFromScan(friendQrLegacyPayload('abc-123')),
        'abc-123',
      );
    });

    test('a QR from any other app is refused', () {
      expect(friendIdFromScan('https://example.com/whatever'), isNull);
      expect(friendIdFromScan('not a uri at all'), isNull);
      expect(friendIdFromScan('io.supabase.adventconnect://product/7'), isNull);
    });

    test('is short enough to stay a dense-but-scannable symbol', () {
      // A real uuid, which is what this always carries.
      final payload =
          friendQrPayload('0b92eb23-de5d-4da3-b4be-f3286ae5f144');

      // Level H on a longer payload needs a higher QR version, more
      // modules, and smaller modules at a fixed 210dp — which is the other
      // way this stops scanning.
      //
      // The budget moved from 80 to 100 when the payload became an https
      // landing page (1.3.2), because a custom scheme is a no-op on a phone
      // without the app and the whole point of a shared code is handing it
      // to someone who has not joined. That is a real cost, paid knowingly:
      //
      //   ≤ 84 bytes → version 8,  49×49, 4.29dp per module
      //   ≤ 98 bytes → version 9,  53×53, 3.96dp per module   ← we are here
      //   ≤119 bytes → version 10, 57×57, 3.68dp per module
      //
      // ~4dp per module still scans comfortably at arm's length. 100 keeps
      // us inside version 9; past that the symbol gets denser than anyone
      // has tested. Most of the payload is the worker's hostname, so a short
      // custom domain is the way to buy the room back — not a bigger number
      // here.
      expect(payload.length, lessThan(100));
    });
  });
}
