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

import 'package:flutter_test/flutter_test.dart';

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

  group('friendQrPayload', () {
    test('encodes a deep link the scanner already understands', () {
      final payload = friendQrPayload('abc-123');

      expect(payload, 'io.supabase.adventconnect://user/abc-123');
    });

    test('is short enough to stay a dense-but-scannable symbol', () {
      // A real uuid, which is what this always carries.
      final payload =
          friendQrPayload('0b92eb23-de5d-4da3-b4be-f3286ae5f144');

      // Level H on a longer payload needs a higher QR version, more
      // modules, and smaller modules at a fixed 210dp — which is the other
      // way this stops scanning. The scheme is fixed, so this only moves
      // if someone appends to the payload.
      expect(payload.length, lessThan(80));
    });
  });
}
