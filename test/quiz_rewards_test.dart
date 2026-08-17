import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:advent_connect_zw/models/quiz_round.dart';
import 'package:advent_connect_zw/services/ads/ads_service.dart';
import 'package:advent_connect_zw/services/ads/rewarded_ad_manager.dart';
import 'package:advent_connect_zw/services/cache_service.dart';
import 'package:advent_connect_zw/services/premium_service.dart';
import 'package:advent_connect_zw/services/quiz_progress_service.dart';
import 'package:advent_connect_zw/services/quiz_rewards_service.dart';

/// The rules behind the quiz's rewarded placements.
///
/// The founder's opening proposal was lives that reset, with an ad to earn
/// one back. These tests pin the alternative that shipped instead: every
/// offer is ADDITIVE, nothing in the quiz is ever gated behind an ad, and
/// the streak repair is capped so a streak still means something.

/// `_dayKey` writes `2026-8-7`, not `2026-08-07`.
String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('quiz_rewards_test');
    Hive.init(dir.path);
    await CacheService.debugUseBox(await Hive.openBox<String>('test_box'));
    PremiumService.debugReset();
    AdsService.debugSetReady(false);
    RewardedAdManager.debugSetLoaded(false);
  });

  tearDown(() async {
    PremiumService.debugReset();
    AdsService.debugSetReady(false);
    RewardedAdManager.debugSetLoaded(false);
    await Hive.deleteFromDisk();
    await CacheService.debugUseBox(null);
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('day parsing', () {
    test('reads the un-padded day key single digit months and days write',
        () async {
      // The stored format is `${d.year}-${d.month}-${d.day}`, so for eight
      // days of every month DateTime.parse would have thrown on it. This is
      // the reason lastPlayedDate() parses the parts by hand.
      await CacheService.writePref(
        'quiz_last_day',
        _dayKey(DateTime(2026, 8, 7)),
      );
      expect(QuizProgressService.lastPlayedDate(), DateTime(2026, 8, 7));
    });

    test('never played reads as null, not as day zero', () {
      expect(QuizProgressService.lastPlayedDate(), isNull);
      expect(QuizProgressService.daysSinceLastDaily(), isNull);
    });

    test('counts whole days, ignoring the time of day', () async {
      final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));
      await CacheService.writePref('quiz_last_day', _dayKey(threeDaysAgo));
      expect(QuizProgressService.daysSinceLastDaily(), 3);
    });
  });

  group('streak repair', () {
    Future<void> setStreak(int days, {required int daysAgo}) async {
      await CacheService.writePref('quiz_streak', '$days');
      await CacheService.writePref(
        'quiz_last_day',
        _dayKey(DateTime.now().subtract(Duration(days: daysAgo))),
      );
    }

    test('an intact streak is not offered a repair', () async {
      await setStreak(9, daysAgo: 1); // played yesterday — nothing is wrong
      expect(QuizRewards.streakIsBroken, isFalse);
    });

    test('a missed day with a real streak is repairable', () async {
      await setStreak(9, daysAgo: 2);
      expect(QuizRewards.streakIsBroken, isTrue);
    });

    test('a 1-day "streak" is not worth an ad', () async {
      await setStreak(1, daysAgo: 3);
      expect(QuizRewards.streakIsBroken, isFalse,
          reason: 'there is nothing here the player would mourn');
    });

    test('repair lets the next daily CONTINUE the streak instead of resetting',
        () async {
      // This is the whole mechanism: a missed day does not clear the stored
      // streak, it just makes recordDailyComplete() take the reset branch.
      // Repair moves the marker to yesterday so it takes the other one.
      await setStreak(9, daysAgo: 4);

      await QuizProgressService.repairStreak();
      await QuizProgressService.recordDailyComplete();

      expect(QuizProgressService.currentStreak(), 10,
          reason: 'the streak continues from where it was');
    });

    test('without a repair the same streak resets to 1', () async {
      await setStreak(9, daysAgo: 4);

      await QuizProgressService.recordDailyComplete();

      expect(QuizProgressService.currentStreak(), 1);
    });

    test('repair does not invent progress — you still have to play today',
        () async {
      await setStreak(9, daysAgo: 4);
      await QuizProgressService.repairStreak();

      expect(QuizProgressService.currentStreak(), 9,
          reason: 'the counter only moves when a round is actually played');
      expect(QuizProgressService.playedToday(), isFalse);
    });

    test('capped at once a week', () async {
      PremiumService.debugSet(premium: true); // free claim, no ad needed
      await setStreak(9, daysAgo: 2);
      expect(QuizRewards.canRepairStreak, isTrue);

      expect(await QuizRewards.repairStreak(), isTrue);

      // Break it again straight away — the cap, not the state, is what
      // must stop a second repair.
      await setStreak(9, daysAgo: 2);
      expect(QuizRewards.streakIsBroken, isTrue);
      expect(QuizRewards.canRepairStreak, isFalse,
          reason: 'once a week, or a streak just means "watched an ad"');
      expect(QuizRewards.daysUntilRepairAllowed, greaterThan(0));
      expect(await QuizRewards.repairStreak(), isFalse);
    });
  });

  group('premium', () {
    test('gets continues and lifelines free, without an ad SDK', () async {
      PremiumService.debugSet(premium: true);
      // The SDK is not ready and no ad is loaded — a subscriber never
      // initialises one at all.
      expect(RewardedAdManager.isReady, isFalse);

      expect(QuizRewards.grantedFree, isTrue);
      expect(QuizRewards.canOffer, isTrue,
          reason: 'the perk is offered even though no ad could ever play');
      expect(await QuizRewards.claim(), isTrue);
    });

    test('is not offered coins, because lifelines already cost nothing',
        () async {
      PremiumService.debugSet(premium: true);
      final before = QuizProgressService.coins();

      expect(await QuizRewards.topUpCoins(), 0);
      expect(QuizProgressService.coins(), before);
    });
  });

  group('free user with no fill', () {
    test('no ad loaded means no offer is shown at all', () {
      PremiumService.debugSet(premium: false);
      expect(QuizRewards.canOffer, isFalse,
          reason: 'a button that cannot do anything must not be drawn');
    });

    test('a declined ad grants nothing', () async {
      PremiumService.debugSet(premium: false);
      final before = QuizProgressService.coins();
      // showForReward() returns false when nothing is ready.
      expect(await QuizRewards.topUpCoins(), 0);
      expect(QuizProgressService.coins(), before);
    });
  });

  group('the quiz economy stays coherent', () {
    test('the top-up is worth more than one lifeline but not a whole round',
        () {
      // If a top-up bought everything, coins would stop mattering; if it
      // bought nothing, nobody would watch. Both ends are worth pinning.
      final cheapest = Lifeline.values
          .map((l) => l.cost)
          .reduce((a, b) => a < b ? a : b);
      expect(QuizRewards.coinTopUp, greaterThan(cheapest));
      expect(QuizRewards.coinTopUp, lessThan(QuizCoins.startingBalance));
    });

    test('a survival run can be continued once, not indefinitely', () {
      expect(QuizRewards.continuesPerRun, 1);
    });
  });
}
