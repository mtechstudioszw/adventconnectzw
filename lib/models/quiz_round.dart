import 'quiz_question_model.dart';

/// The ways a round can be played. Each mode carries its own rules so the
/// round screen stays a dumb player of whatever config it's handed.
enum QuizMode {
  /// Today's 5 questions — same set for everyone, advances the streak.
  daily,

  /// A 10-question mixed round.
  practice,

  /// A 10-question round limited to one topic.
  category,

  /// Sudden death: one wrong answer ends the run. No fixed length.
  survival,

  /// 60 seconds on the clock — answer as many as you can.
  speed,

  /// Re-serves questions this player has previously gotten wrong.
  mistakes,
}

extension QuizModeInfo on QuizMode {
  String get label => switch (this) {
        QuizMode.daily => 'Daily Challenge',
        QuizMode.practice => 'Quick Play',
        QuizMode.category => 'Topic Round',
        QuizMode.survival => 'Survival',
        QuizMode.speed => 'Speed Round',
        QuizMode.mistakes => 'Fix Your Mistakes',
      };

  /// Seconds allowed per question before the speed bonus is gone.
  ///
  /// The clock NEVER ends a question — running it down only costs you the
  /// bonus points (the deliberate design call: arcade energy without
  /// pressuring anyone on a doctrinal question). [QuizMode.speed] is the
  /// exception, and there the pressure is the round clock, not the question.
  int get secondsPerQuestion => switch (this) {
        QuizMode.daily => 25,
        QuizMode.practice => 20,
        QuizMode.category => 20,
        QuizMode.survival => 15,
        QuizMode.speed => 12,
        QuizMode.mistakes => 30,
      };

  /// Whole-round clock in seconds, or null when the round is question-based.
  int? get roundSeconds => this == QuizMode.speed ? 60 : null;

  /// A wrong answer ends the round.
  bool get suddenDeath => this == QuizMode.survival;

  /// Rounds that feed the "questions you got wrong" pool.
  bool get tracksMistakes => this != QuizMode.mistakes;

  /// How many questions to load. Survival and Speed pull a deep buffer
  /// because the player decides when they stop.
  int get questionCount => switch (this) {
        QuizMode.daily => 5,
        QuizMode.practice => 10,
        QuizMode.category => 10,
        QuizMode.survival => 60,
        QuizMode.speed => 40,
        QuizMode.mistakes => 10,
      };

  /// Shown under the mode title in the lobby.
  String get blurb => switch (this) {
        QuizMode.daily => 'Five questions. Everyone gets the same set.',
        QuizMode.practice => 'Ten questions across every topic.',
        QuizMode.category => 'Ten questions on one topic.',
        QuizMode.survival => 'One wrong answer ends the run.',
        QuizMode.speed => 'Sixty seconds. Go as far as you can.',
        QuizMode.mistakes => 'The ones that caught you out before.',
      };
}

/// One answered question inside a round.
class QuizAnswer {
  const QuizAnswer({
    required this.questionId,
    required this.chosenIndex,
    required this.correct,
    required this.elapsedMs,
    required this.points,
    required this.comboAfter,
  });

  final String questionId;

  /// -1 when the player skipped or the round clock ran out on them.
  final int chosenIndex;
  final bool correct;
  final int elapsedMs;
  final int points;
  final int comboAfter;
}

/// The finished round, handed to the results screen.
class QuizRoundResult {
  const QuizRoundResult({
    required this.mode,
    required this.title,
    required this.answers,
    required this.questions,
    required this.points,
    required this.bonusPoints,
    required this.bestCombo,
    required this.xpEarned,
    required this.coinsEarned,
    required this.newLevel,
    required this.leveledUp,
    required this.streak,
    required this.isNewBestScore,
    this.challengeId,
  });

  final QuizMode mode;
  final String title;
  final List<QuizAnswer> answers;

  /// Every question served this round, so the results screen can show what
  /// you actually got wrong. [answers] alone only carries ids — and a
  /// generated question has no server row to look the text back up from.
  final List<QuizQuestion> questions;

  /// Set when this round settled a head-to-head challenge.
  final String? challengeId;

  /// Total points including [bonusPoints].
  final int points;

  /// The perfect-round bonus, so the results screen can call it out.
  final int bonusPoints;
  final int bestCombo;
  final int xpEarned;
  final int coinsEarned;
  final int newLevel;
  final bool leveledUp;
  final int streak;
  final bool isNewBestScore;

  int get total => answers.length;
  int get correctCount => answers.where((a) => a.correct).length;

  /// Pairs each answer with the question it was given for, in play order.
  /// Skipped questions have no answer and are deliberately absent.
  List<(QuizQuestion, QuizAnswer)> get reviewPairs {
    final byId = {for (final q in questions) q.id: q};
    return [
      for (final answer in answers)
        if (byId[answer.questionId] != null) (byId[answer.questionId]!, answer),
    ];
  }

  /// 0–100. Guards the empty round (Speed with zero answers).
  int get accuracyPct =>
      total == 0 ? 0 : (correctCount / total * 100).round();

  bool get isPerfect =>
      total >= 5 && correctCount == total && mode != QuizMode.survival;

  /// 0–3 stars, the headline of the results screen.
  int get stars {
    if (total == 0) return 0;
    final pct = accuracyPct;
    if (pct >= 95) return 3;
    if (pct >= 75) return 2;
    if (pct >= 50) return 1;
    return 0;
  }

  String get headline {
    if (mode == QuizMode.survival) {
      return correctCount >= 15
          ? 'Incredible run!'
          : correctCount >= 7
              ? 'Strong run!'
              : 'Run over';
    }
    if (isPerfect) return 'Perfect round!';
    return switch (stars) {
      3 => 'Outstanding!',
      2 => 'Well done!',
      1 => 'Good effort',
      _ => 'Keep studying',
    };
  }
}

/// Pure scoring rules. Kept free of Flutter and of storage so the numbers
/// can be reasoned about (and unit-tested) on their own.
class QuizScoring {
  QuizScoring._();

  /// Points a correct answer is worth before bonuses.
  static const int base = 100;

  /// Maximum speed bonus, earned by answering instantly.
  static const int maxSpeedBonus = 100;

  /// Awarded for a flawless round.
  static const int perfectBonus = 300;

  /// Points per XP — a strong 10-question round lands around 100–150 XP.
  static const int pointsPerXp = 20;

  /// Combo thresholds. Answering 3 in a row doubles everything after it,
  /// which is what makes a player want one more round.
  static int multiplierFor(int combo) {
    if (combo >= 8) return 4;
    if (combo >= 5) return 3;
    if (combo >= 3) return 2;
    return 1;
  }

  /// The combo value at which the multiplier next increases, or null when
  /// the player is already at the cap. Drives the combo meter's fill.
  static int? nextComboThreshold(int combo) {
    if (combo < 3) return 3;
    if (combo < 5) return 5;
    if (combo < 8) return 8;
    return null;
  }

  /// Score one answer.
  ///
  /// [remainingFraction] is how much of the question clock was left (1.0 =
  /// instant, 0.0 = the clock emptied). [comboAfter] is the streak length
  /// INCLUDING this answer, so the third correct answer is itself doubled.
  static int pointsFor({
    required bool correct,
    required double remainingFraction,
    required int comboAfter,
    required QuizMode mode,
  }) {
    if (!correct) return 0;
    final speed = (maxSpeedBonus * remainingFraction.clamp(0.0, 1.0)).round();
    var points = (base + speed) * multiplierFor(comboAfter);
    // Survival gets steeper the longer you last — the reason to risk one
    // more question instead of walking away.
    if (mode == QuizMode.survival) {
      points += 25 * (comboAfter - 1).clamp(0, 40);
    }
    return points;
  }

  /// XP earned from a round's points.
  static int xpFor(int points) => (points / pointsPerXp).round();

  // ---- Levels -------------------------------------------------------------

  /// Cumulative XP needed to reach [level]. Level 1 starts at 0 and each
  /// level costs 100 XP more than the one before (L2 = 100, L3 = 300,
  /// L4 = 600 …) — quick early wins, a long tail for regulars.
  static int xpForLevel(int level) {
    if (level <= 1) return 0;
    final n = level - 1;
    return 50 * n * (n + 1);
  }

  /// The level a player with [xp] total experience has reached.
  static int levelForXp(int xp) {
    var level = 1;
    while (level < 200 && xp >= xpForLevel(level + 1)) {
      level++;
    }
    return level;
  }

  /// Progress through the current level, 0.0–1.0.
  static double levelProgress(int xp) {
    final level = levelForXp(xp);
    final floor = xpForLevel(level);
    final ceil = xpForLevel(level + 1);
    if (ceil <= floor) return 1;
    return ((xp - floor) / (ceil - floor)).clamp(0.0, 1.0);
  }

  /// XP still needed for the next level.
  static int xpToNextLevel(int xp) =>
      (xpForLevel(levelForXp(xp) + 1) - xp).clamp(0, 1 << 30);

  /// The visible rank for a level.
  static String rankForLevel(int level) {
    if (level >= 50) return 'Master';
    if (level >= 35) return 'Elder';
    if (level >= 20) return 'Teacher';
    if (level >= 10) return 'Scholar';
    if (level >= 5) return 'Student';
    return 'Seeker';
  }
}

/// Paid helps, bought with coins.
///
/// Each costs coins; when the player can't afford one, the round offers a
/// rewarded ad instead so a lifeline is never hard-gated behind a balance
/// (and the ad is opt-in, never forced).
enum Lifeline { fiftyFifty, skip, extraTime, secondChance }

extension LifelineInfo on Lifeline {
  String get label => switch (this) {
        Lifeline.fiftyFifty => '50/50',
        Lifeline.skip => 'Skip',
        Lifeline.extraTime => '+10s',
        Lifeline.secondChance => 'Second chance',
      };

  String get description => switch (this) {
        Lifeline.fiftyFifty => 'Removes two wrong answers.',
        Lifeline.skip => 'Skips this question — your streak survives.',
        Lifeline.extraTime => 'Adds ten seconds to the clock.',
        Lifeline.secondChance =>
          'Undo a wrong answer and try the question again.',
      };

  int get cost => switch (this) {
        Lifeline.fiftyFifty => 30,
        Lifeline.skip => 20,
        Lifeline.extraTime => 15,
        Lifeline.secondChance => 50,
      };

  /// Seconds granted by [Lifeline.extraTime].
  static const int extraSeconds = 10;
}

/// Coin economy.
///
/// ## Retuned 4 Aug 2026 — coins were too easy to come by
///
/// The old rates paid a strong 10-question round ~5,700 points → **57
/// coins**, against a 30-coin 50/50. One good round bought a lifeline
/// outright and left change, so nobody ever had to choose, and the
/// rewarded-ad offer (which only appears when you cannot afford a
/// lifeline) was almost never reached.
///
/// Earning is now roughly halved: the same round pays **28 coins** — just
/// under a 50/50. That is the whole design. A lifeline costs about two good
/// rounds, so spending one is a decision rather than a reflex, and the
/// player who wants one now is the player the ad is actually for.
///
/// **Existing balances are untouched.** Coins are a STORED value
/// (`QuizProgressService.addCoins` increments a saved number; nothing
/// recomputes a balance from past scores), so this changes what you earn
/// from here on and never takes back what anyone already has. Retroactively
/// deducting from the members who have been playing would be a bad way to
/// thank them.
///
/// [startingBalance] deliberately stays at 100. A new player should still
/// be able to try every lifeline once — that is how they learn the
/// lifelines exist at all, and it is the cheapest onboarding in the game.
class QuizCoins {
  QuizCoins._();

  /// New players start with enough to try every lifeline once.
  static const int startingBalance = 100;

  /// Points-to-coins divisor for a finished round. Was 100.
  static const int pointsPerCoin = 200;

  /// Bonus for completing the Daily Challenge. Was 25.
  ///
  /// Cut by less than the round rate, on purpose: the daily is the habit
  /// worth protecting, and it is capped at once a day anyway, so it cannot
  /// be farmed the way replaying rounds can.
  static const int dailyBonus = 15;

  /// Bonus on each level up. Was 50.
  static const int levelUpBonus = 30;

  static int forRound(int points) => points ~/ pointsPerCoin;
}

/// Everything the round screen needs to run a game.
class QuizRoundConfig {
  const QuizRoundConfig({
    required this.mode,
    required this.questions,
    required this.title,
    this.category,
    this.challengeId,
    this.startIndex = 0,
    this.startPoints = 0,
    this.startCombo = 0,
  });

  /// Set when this round is answering a head-to-head challenge, so the
  /// score can be submitted against it when the round ends.
  final String? challengeId;

  final QuizMode mode;
  final List<QuizQuestion> questions;
  final String title;

  /// The topic this round was drawn from, kept so "Play again" can rebuild
  /// the same kind of round instead of silently dropping back to a mixed one.
  final String? category;

  /// Resume support.
  final int startIndex;
  final int startPoints;
  final int startCombo;
}
