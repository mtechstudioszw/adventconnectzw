import 'dart:convert';
import 'dart:math';

import '../models/quiz_question_model.dart';
import '../models/quiz_round.dart';
import 'cache_service.dart';

/// Everything the player accumulates: XP, level, streak, best scores, the
/// questions they've seen lately, and the ones they got wrong.
///
/// Local-first by design — a round must score, save and celebrate with no
/// network. [QuizCloudService] mirrors this to Supabase so a reinstall
/// doesn't wipe a 60-day streak and so the leaderboard has something to
/// rank; local always wins for reads, the cloud is a backup and a
/// scoreboard.
///
/// The legacy `quiz_*` keys from the first version are reused deliberately
/// so existing players keep the streak and stats they already earned.
class QuizProgressService {
  QuizProgressService._();

  // Legacy keys — DO NOT rename, players have data under these.
  static const _kStreak = 'quiz_streak';
  static const _kLastDay = 'quiz_last_day';
  static const _kBestStreak = 'quiz_best_streak';
  static const _kAnswered = 'quiz_total_answered';
  static const _kCorrect = 'quiz_total_correct';
  static const _kSeenLegacy = 'quiz_seen_ids';
  static const _kSession = 'quiz_session';

  // Arena keys.
  static const _kXp = 'quiz_xp';
  static const _kSeen = 'quiz_seen_v2';
  static const _kMistakes = 'quiz_mistakes';
  static const _kBestPrefix = 'quiz_best_';
  static const _kLifetimePoints = 'quiz_points_total';

  /// A question isn't served again for this long unless the pool runs dry.
  /// The old behaviour wiped the whole seen-list the moment it couldn't
  /// fill a round, so questions could repeat immediately.
  static const Duration seenCooldown = Duration(days: 21);

  /// Cap on locally cached missed questions.
  static const int maxMistakes = 80;

  static int _readInt(String key) =>
      int.tryParse(CacheService.readPref(key) ?? '') ?? 0;

  static Future<void> _writeInt(String key, int value) =>
      CacheService.writePref(key, value.toString());

  // ---- XP + level ---------------------------------------------------------

  static int totalXp() => _readInt(_kXp);

  static int level() => QuizScoring.levelForXp(totalXp());

  static String rank() => QuizScoring.rankForLevel(level());

  static double levelProgress() => QuizScoring.levelProgress(totalXp());

  /// Adds [xp] and reports whether the player levelled up.
  static Future<bool> addXp(int xp) async {
    if (xp <= 0) return false;
    final before = level();
    await _writeInt(_kXp, totalXp() + xp);
    return level() > before;
  }

  static int lifetimePoints() => _readInt(_kLifetimePoints);

  static Future<void> addPoints(int points) =>
      _writeInt(_kLifetimePoints, lifetimePoints() + points);

  // ---- Streak -------------------------------------------------------------

  static String _dayKey([DateTime? when]) {
    final d = when ?? DateTime.now();
    return '${d.year}-${d.month}-${d.day}';
  }

  static int currentStreak() => _readInt(_kStreak);

  static int bestStreak() => _readInt(_kBestStreak);

  /// True once today's Daily Challenge is done.
  static bool playedToday() => CacheService.readPref(_kLastDay) == _dayKey();

  /// Advances the streak, resetting to 1 if a day was missed.
  static Future<void> recordDailyComplete() async {
    if (playedToday()) return;
    final last = CacheService.readPref(_kLastDay);
    final yesterday = _dayKey(DateTime.now().subtract(const Duration(days: 1)));
    final next = (last == yesterday) ? currentStreak() + 1 : 1;
    await _writeInt(_kStreak, next);
    await CacheService.writePref(_kLastDay, _dayKey());
    if (next > bestStreak()) await _writeInt(_kBestStreak, next);
  }

  // ---- Lifetime accuracy --------------------------------------------------

  static int totalAnswered() => _readInt(_kAnswered);

  static int totalCorrect() => _readInt(_kCorrect);

  static int accuracyPct() {
    final answered = totalAnswered();
    if (answered == 0) return 0;
    return (totalCorrect() / answered * 100).round();
  }

  static Future<void> recordAnswer(bool correct) async {
    await _writeInt(_kAnswered, totalAnswered() + 1);
    if (correct) await _writeInt(_kCorrect, totalCorrect() + 1);
  }

  // ---- Best score per mode ------------------------------------------------

  static int bestScore(QuizMode mode) => _readInt('$_kBestPrefix${mode.name}');

  /// Stores [points] if it beats the record; returns true when it did.
  static Future<bool> recordScore(QuizMode mode, int points) async {
    if (points <= bestScore(mode)) return false;
    await _writeInt('$_kBestPrefix${mode.name}', points);
    return true;
  }

  /// Write a cloud snapshot straight into local storage.
  ///
  /// Only ever called by [QuizCloudService.restoreIfEmpty] after a
  /// reinstall — it overwrites rather than merges, which is exactly why the
  /// caller checks that local progress is empty first.
  static Future<void> restoreFromCloud({
    required int xp,
    required int currentStreak,
    required int bestStreak,
    required int totalAnswered,
    required int totalCorrect,
    required int lifetimePoints,
    required Map<QuizMode, int> bestScores,
  }) async {
    await _writeInt(_kXp, xp);
    await _writeInt(_kStreak, currentStreak);
    await _writeInt(_kBestStreak, bestStreak);
    await _writeInt(_kAnswered, totalAnswered);
    await _writeInt(_kCorrect, totalCorrect);
    await _writeInt(_kLifetimePoints, lifetimePoints);
    for (final entry in bestScores.entries) {
      await _writeInt('$_kBestPrefix${entry.key.name}', entry.value);
    }
    // Deliberately NOT restored: `_kLastDay`. Without it the next Daily
    // Challenge is playable immediately on the new device, and the streak
    // continues instead of the player being told they already played today.
  }

  // ---- Seen rotation ------------------------------------------------------

  /// id → epoch millis it was last served.
  static Map<String, int> _seen() {
    final raw = CacheService.readPref(_kSeen);
    if (raw == null || raw.isEmpty) return _migrateLegacySeen();
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in decoded.entries)
          entry.key: (entry.value as num?)?.toInt() ?? 0,
      };
    } catch (_) {
      return {};
    }
  }

  /// Old versions stored a flat id list with no timestamps. Bring them
  /// across at epoch 0 — "seen, but long ago", so nothing is lost and
  /// everything is immediately eligible again.
  static Map<String, int> _migrateLegacySeen() {
    final raw = CacheService.readPref(_kSeenLegacy);
    if (raw == null || raw.isEmpty) return {};
    try {
      final ids = (jsonDecode(raw) as List).map((e) => e.toString());
      return {for (final id in ids) id: 0};
    } catch (_) {
      return {};
    }
  }

  static Future<void> _writeSeen(Map<String, int> seen) async {
    // Keep the store bounded: drop the oldest once it gets large.
    if (seen.length > 1200) {
      final entries = seen.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      seen = Map.fromEntries(entries.skip(entries.length - 900));
    }
    await CacheService.writePref(_kSeen, jsonEncode(seen));
  }

  /// Remember that these questions were just served.
  static Future<void> markSeen(Iterable<QuizQuestion> questions) async {
    final seen = _seen();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final question in questions) {
      seen[question.id] = now;
    }
    await _writeSeen(seen);
  }

  /// Pick [count] from [pool], strongly preferring questions not served
  /// inside [seenCooldown], then falling back to whatever was seen
  /// longest ago. The old code wiped its memory when it couldn't fill a
  /// round, which let a question reappear in the very next one.
  static List<QuizQuestion> pickFresh(
    List<QuizQuestion> pool,
    int count, {
    int? seed,
  }) {
    if (pool.isEmpty || count <= 0) return const [];
    final seen = _seen();
    final cutoff = DateTime.now()
        .subtract(seenCooldown)
        .millisecondsSinceEpoch;

    final fresh = <QuizQuestion>[];
    final stale = <QuizQuestion>[];
    for (final question in pool) {
      final lastSeen = seen[question.id];
      if (lastSeen == null || lastSeen < cutoff) {
        fresh.add(question);
      } else {
        stale.add(question);
      }
    }

    // A seeded shuffle keeps the Daily Challenge identical on every device
    // running this build — same source of randomness as the generator uses.
    fresh.shuffle(seed == null ? null : Random(seed));
    // Oldest-seen first, so a forced repeat is at least the most distant one.
    stale.sort((a, b) => (seen[a.id] ?? 0).compareTo(seen[b.id] ?? 0));

    return [...fresh, ...stale].take(count).toList();
  }

  // ---- Mistakes -----------------------------------------------------------

  /// Missed questions, newest first. Cached whole (not by id) because a
  /// generated question has no server row to fetch back.
  static List<QuizQuestion> mistakes() {
    final raw = CacheService.readPref(_kMistakes);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => QuizQuestion.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static int mistakeCount() => mistakes().length;

  static Future<void> addMistake(QuizQuestion question) async {
    final list = mistakes()
      ..removeWhere((q) => q.id == question.id)
      ..insert(0, question);
    final trimmed = list.take(maxMistakes).toList();
    await CacheService.writePref(
      _kMistakes,
      jsonEncode([for (final q in trimmed) q.toJson()]),
    );
  }

  /// Drop a question from the pool once it's been answered correctly in
  /// Fix Your Mistakes — the list should shrink as you learn.
  static Future<void> clearMistake(String id) async {
    final list = mistakes()..removeWhere((q) => q.id == id);
    await CacheService.writePref(
      _kMistakes,
      jsonEncode([for (final q in list) q.toJson()]),
    );
  }

  // ---- Resume -------------------------------------------------------------

  /// Persist an in-progress round. Generated questions are stored whole so
  /// a resumed round can rebuild them without re-running the generator.
  static Future<void> saveSession({
    required List<QuizQuestion> questions,
    required int index,
    required int points,
    required int combo,
    required QuizMode mode,
    required String title,
  }) async {
    await CacheService.writePref(
      _kSession,
      jsonEncode({
        'v': 2,
        'questions': [for (final q in questions) q.toJson()],
        'index': index,
        'points': points,
        'combo': combo,
        'mode': mode.name,
        'title': title,
      }),
    );
  }

  /// The saved round, or null. Returns null for v1 sessions (which only
  /// stored ids) rather than trying to half-restore one.
  static Map<String, dynamic>? loadSession() {
    final raw = CacheService.readPref(_kSession);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['v'] != 2) return null;
      final questions = map['questions'] as List?;
      if (questions == null || questions.isEmpty) return null;
      return map;
    } catch (_) {
      return null;
    }
  }

  static List<QuizQuestion> sessionQuestions(Map<String, dynamic> session) {
    try {
      return (session['questions'] as List)
          .map((e) => QuizQuestion.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static QuizMode sessionMode(Map<String, dynamic> session) {
    final name = session['mode']?.toString();
    return QuizMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => QuizMode.practice,
    );
  }

  static Future<void> clearSession() => CacheService.writePref(_kSession, '');
}
