import 'package:flutter/foundation.dart';

import 'ads/rewarded_ad_manager.dart';
import 'cache_service.dart';
import 'premium_service.dart';
import 'quiz_progress_service.dart';

/// The rules behind every "watch a short ad for X" offer in the quiz.
///
/// ## The principle these are built on
///
/// **The reward is additive; the block is never punitive.** The founder's
/// first proposal was lives that reset, with an ad to earn one back. This
/// is a church app and the quiz is scripture and doctrine — making Bible
/// study *harder* in order to force ad views risks congregation trust in a
/// way it simply would not in a match-3 game. So nothing here takes
/// anything away. Every placement offers something extra at a moment the
/// player already wants it, which is also the pattern that converts better
/// in mobile games.
///
/// Concretely: **nothing in the quiz is ever gated behind an ad.** Not a
/// question, not a round, and above all not the Daily Challenge — that is
/// the habit that brings people back, and putting a streak behind an ad is
/// the single placement most likely to feel extractive.
///
/// ## Premium
///
/// Subscribers never load an ad SDK at all, so "watch an ad" is not a thing
/// they can do. Rather than hide the features from them, the ones that are
/// about *play* — continues and lifelines — are simply **free**. That makes
/// the subscription more valuable at zero cost to us. The ones that are
/// about *coins* are hidden instead, because a subscriber has nothing to
/// spend coins on once lifelines are free.
class QuizRewards {
  QuizRewards._();

  /// Continues allowed in a single Survival run.
  ///
  /// One, not "escalating cost forever" like an arcade. A run that can be
  /// extended indefinitely stops being sudden death, and the leaderboard it
  /// feeds stops meaning anything.
  static const int continuesPerRun = 1;

  /// Coins granted by the lobby's top-up button.
  ///
  /// Enough to matter (a 50/50 is 30) without making the round rate
  /// pointless.
  static const int coinTopUp = 50;

  /// One streak repair a week, so a streak still means something. Without a
  /// cap, "streak" would just mean "watched an ad occasionally".
  static const Duration streakRepairCooldown = Duration(days: 7);

  /// Deliberately unprefixed, so [CacheService.clearUserData] wipes it on
  /// sign-out along with the streak itself. Signing out to dodge the weekly
  /// cap would also destroy the streak there is to repair, so the loophole
  /// closes itself.
  static const String _kLastRepair = 'quiz_streak_repair_at';

  /// True when the member gets the perk without watching anything.
  static bool get grantedFree => PremiumService.isActive;

  /// Whether a "watch an ad for X" offer can be shown at all right now.
  ///
  /// This is what makes the offers *visible* rather than the old behaviour,
  /// where the quiz only ever mentioned an ad if one happened to already be
  /// cached at the exact moment the player ran out of coins.
  static bool get canOffer => grantedFree || RewardedAdManager.isReady;

  /// Run the ad (or grant it outright for a subscriber). True means the
  /// caller may hand over the reward.
  static Future<bool> claim() async {
    if (grantedFree) return true;
    return RewardedAdManager.showForReward();
  }

  // ---- Streak repair ------------------------------------------------------

  /// Whether the Daily Challenge streak is currently broken but rescuable.
  ///
  /// Note that a missed day does NOT clear the stored streak — the reset is
  /// lazy, computed on the next `recordDailyComplete()`. So the number is
  /// still sitting there, which is exactly what makes repairing it possible
  /// (and what makes offering it honest: we are not inventing a streak, we
  /// are stopping one from being discarded).
  static bool get streakIsBroken {
    final missed = QuizProgressService.daysSinceLastDaily();
    // null  = never played, nothing to repair.
    // 0 / 1 = played today or yesterday, the streak is fine.
    if (missed == null || missed < 2) return false;
    return QuizProgressService.currentStreak() >= 2;
  }

  static DateTime? get _lastRepair =>
      DateTime.tryParse(CacheService.readPref(_kLastRepair) ?? '');

  static bool get _cooldownElapsed {
    final last = _lastRepair;
    if (last == null) return true;
    return DateTime.now().difference(last) >= streakRepairCooldown;
  }

  /// The full test for showing the repair offer.
  static bool get canRepairStreak =>
      streakIsBroken && _cooldownElapsed && canOffer;

  /// Days until the weekly cap lets them repair again, for the UI to
  /// explain itself instead of just hiding the button.
  static int get daysUntilRepairAllowed {
    final last = _lastRepair;
    if (last == null) return 0;
    final elapsed = DateTime.now().difference(last);
    final left = streakRepairCooldown - elapsed;
    return left.isNegative ? 0 : left.inDays + 1;
  }

  /// Watch (or skip, if premium) and rescue the streak. Returns true if it
  /// was repaired.
  static Future<bool> repairStreak() async {
    if (!canRepairStreak) return false;
    final earned = await claim();
    if (!earned) return false;
    try {
      await QuizProgressService.repairStreak();
      await CacheService.writePref(
        _kLastRepair,
        DateTime.now().toIso8601String(),
      );
    } catch (e) {
      debugPrint('QuizRewards.repairStreak failed to persist: $e');
      return false;
    }
    return true;
  }

  // ---- Coins --------------------------------------------------------------

  /// The lobby's explicit top-up. Hidden from subscribers — see the class
  /// doc. Returns the coins granted, or 0.
  static Future<int> topUpCoins() async {
    if (grantedFree) return 0;
    final earned = await claim();
    if (!earned) return 0;
    await QuizProgressService.addCoins(coinTopUp);
    return coinTopUp;
  }
}
