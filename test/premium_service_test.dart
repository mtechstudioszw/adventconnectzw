import 'package:advent_connect_zw/services/ads/ads_service.dart';
import 'package:advent_connect_zw/services/premium_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The premium state machine, tested without Supabase, secure storage or
/// a real clock. [PremiumService.evaluate] is the whole decision: given a
/// cached expiry, who it belongs to, who is signed in and what time it
/// is, may this user skip ads?
void main() {
  const alice = 'user-alice';
  const bob = 'user-bob';
  final now = DateTime.utc(2026, 8, 3, 12);
  final future = now.add(const Duration(days: 20));
  final past = now.subtract(const Duration(days: 1));

  tearDown(() {
    PremiumService.debugReset();
    AdsService.debugSetReady(false);
  });

  group('PremiumService.evaluate', () {
    test('grants premium while the expiry is in the future', () {
      expect(
        PremiumService.evaluate(
          until: future,
          owner: alice,
          currentUserId: alice,
          now: now,
        ),
        isTrue,
      );
    });

    test('refuses once the expiry has passed', () {
      expect(
        PremiumService.evaluate(
          until: past,
          owner: alice,
          currentUserId: alice,
          now: now,
        ),
        isFalse,
      );
    });

    test('treats the exact expiry instant as lapsed', () {
      expect(
        PremiumService.evaluate(
          until: now,
          owner: alice,
          currentUserId: alice,
          now: now,
        ),
        isFalse,
      );
    });

    test('never lets one account inherit another account\'s premium', () {
      // The cache says premium until next month, but it was written for
      // Alice and Bob is the one signed in now.
      expect(
        PremiumService.evaluate(
          until: future,
          owner: alice,
          currentUserId: bob,
          now: now,
        ),
        isFalse,
      );
    });

    test('grants nothing when nobody is signed in', () {
      expect(
        PremiumService.evaluate(
          until: future,
          owner: alice,
          currentUserId: null,
          now: now,
        ),
        isFalse,
      );
    });

    test('grants nothing with no cached expiry', () {
      expect(
        PremiumService.evaluate(
          until: null,
          owner: alice,
          currentUserId: alice,
          now: now,
        ),
        isFalse,
      );
    });

    test('grants nothing when the cache has an expiry but no owner', () {
      expect(
        PremiumService.evaluate(
          until: future,
          owner: null,
          currentUserId: alice,
          now: now,
        ),
        isFalse,
      );
    });
  });

  group('isPremium notifier', () {
    test('starts false', () {
      expect(PremiumService.isActive, isFalse);
    });

    test('notifies listeners when premium starts and stops', () {
      final seen = <bool>[];
      void listener() => seen.add(PremiumService.isActive);
      PremiumService.isPremium.addListener(listener);
      addTearDown(() => PremiumService.isPremium.removeListener(listener));

      PremiumService.debugSet(premium: true);
      PremiumService.debugSet(premium: false);

      expect(seen, [true, false]);
    });
  });

  group('ad gating', () {
    test('a premium user may not request ads even with the SDK ready', () {
      AdsService.debugSetReady(true);
      PremiumService.debugSet(premium: true);
      expect(AdsService.isReady, isTrue,
          reason: 'the SDK itself is still initialised');
      expect(AdsService.canRequestAds, isFalse,
          reason: 'but a subscriber must never request an ad');
    });

    test('a free user with the SDK ready may request ads', () {
      AdsService.debugSetReady(true);
      PremiumService.debugSet(premium: false);
      expect(AdsService.canRequestAds, isTrue);
    });

    test('nobody may request ads before the SDK is ready', () {
      AdsService.debugSetReady(false);
      PremiumService.debugSet(premium: false);
      expect(AdsService.canRequestAds, isFalse);
    });

    test('init() is a no-op while premium, so the SDK never starts', () async {
      PremiumService.debugSet(premium: true);
      await AdsService.init();
      expect(AdsService.isReady, isFalse);
      expect(AdsService.canRequestAds, isFalse);
    });
  });
}
