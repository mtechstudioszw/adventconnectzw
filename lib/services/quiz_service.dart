import 'dart:convert';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/quiz_question_model.dart';
import 'cache_service.dart';
import 'connectivity_service.dart';

/// Bible Quiz data + local progress (patch_147). Questions are admin-curated
/// and cached for offline play; streaks/scores are stored locally for the MVP.
class QuizService {
  QuizService._();
  static final SupabaseClient _client = Supabase.instance.client;

  static const _cacheKey = 'quiz_questions_v1';
  static const _kStreak = 'quiz_streak';
  static const _kLastDay = 'quiz_last_day';
  static const _kBestStreak = 'quiz_best_streak';
  static List<QuizQuestion>? _mem;

  /// All published questions, cached (memory → Hive → network).
  static Future<List<QuizQuestion>> all() async {
    if (_mem != null) return _mem!;
    if (!ConnectivityService.isOnline) return _mem = _readCache();
    try {
      final rows = await _client
          .from('quiz_questions')
          .select()
          .eq('is_published', true);
      CacheService.writeString(_cacheKey, jsonEncode(rows));
      return _mem = (rows as List)
          .map((r) => QuizQuestion.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return _mem = _readCache();
    }
  }

  static List<QuizQuestion> _readCache() {
    try {
      final raw = CacheService.readStringStale(_cacheKey);
      if (raw == null) return const [];
      return (jsonDecode(raw) as List)
          .map((r) => QuizQuestion.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static void invalidate() => _mem = null;

  static Future<List<String>> categories() async {
    final list = await all();
    final set = <String>{for (final q in list) q.category};
    final sorted = set.toList()..sort();
    return sorted;
  }

  /// Today's Daily Challenge: a deterministic set of [count] questions seeded by
  /// the date, so every player gets the same daily set and can't reshuffle.
  static Future<List<QuizQuestion>> dailySet({int count = 5}) async {
    final list = await all();
    if (list.length <= count) return List.of(list)..shuffle(_dayRng());
    final pool = List.of(list);
    pool.shuffle(_dayRng());
    return pool.take(count).toList();
  }

  /// A practice round that ROTATES: prefers questions the player hasn't seen
  /// recently, so tapping "play again" keeps serving fresh questions until the
  /// pool is exhausted, then cycles. [category] limits to one topic.
  static Future<List<QuizQuestion>> practiceSet({
    String? category,
    int count = 10,
  }) async {
    final list = await all();
    final pool = category == null
        ? List.of(list)
        : list.where((q) => q.category == category).toList();
    if (pool.isEmpty) return const [];

    var seen = _seenIds();
    var unseen = pool.where((q) => !seen.contains(q.id)).toList();
    // Not enough fresh questions left in this pool → reset the "seen" marks
    // for this pool so we start cycling through it again.
    if (unseen.length < count) {
      final poolIds = pool.map((q) => q.id).toSet();
      seen = seen.where((id) => !poolIds.contains(id)).toSet();
      _writeSeen(seen);
      unseen = List.of(pool);
    }
    unseen.shuffle();
    return unseen.take(count).toList();
  }

  static Random _dayRng() {
    final now = DateTime.now();
    final seed = now.year * 10000 + now.month * 100 + now.day;
    return Random(seed);
  }

  // ---- Admin (super admin only via RLS) ------------------------------------

  /// Every question including unpublished, for the admin editor.
  static Future<List<QuizQuestion>> fetchAllAdmin() async {
    final rows = await _client
        .from('quiz_questions')
        .select()
        .order('category', ascending: true)
        .order('id', ascending: true);
    return (rows as List)
        .map((r) => QuizQuestion.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveQuestion({
    String? id,
    required String question,
    required List<String> options,
    required int correctIndex,
    String? explanation,
    String? reference,
    required String category,
    String difficulty = 'medium',
  }) async {
    final payload = <String, dynamic>{
      'question': question.trim(),
      'options': options,
      'correct_index': correctIndex,
      'explanation':
          (explanation == null || explanation.trim().isEmpty) ? null : explanation.trim(),
      'reference':
          (reference == null || reference.trim().isEmpty) ? null : reference.trim(),
      'category': category.trim().isEmpty ? 'General' : category.trim(),
      'difficulty': difficulty,
      'is_published': true,
    };
    if (id == null) {
      await _client.from('quiz_questions').insert(payload);
    } else {
      await _client.from('quiz_questions').update(payload).eq('id', id);
    }
    invalidate();
  }

  static Future<void> deleteQuestion(String id) async {
    await _client.from('quiz_questions').delete().eq('id', id);
    invalidate();
  }

  // ---- Streak (local) ------------------------------------------------------

  static String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  static int currentStreak() =>
      int.tryParse(CacheService.readPref(_kStreak) ?? '') ?? 0;

  static int bestStreak() =>
      int.tryParse(CacheService.readPref(_kBestStreak) ?? '') ?? 0;

  /// True once today's Daily Challenge has been completed.
  static bool playedToday() =>
      CacheService.readPref(_kLastDay) == _todayKey();

  /// Record completion of today's Daily Challenge and advance the streak
  /// (resets to 1 if a day was missed). No-op if already played today.
  static Future<void> recordDailyComplete() async {
    if (playedToday()) return;
    final last = CacheService.readPref(_kLastDay);
    final y = DateTime.now().subtract(const Duration(days: 1));
    final yesterday = '${y.year}-${y.month}-${y.day}';
    final next = (last == yesterday) ? currentStreak() + 1 : 1;
    await CacheService.writePref(_kStreak, next.toString());
    await CacheService.writePref(_kLastDay, _todayKey());
    if (next > bestStreak()) {
      await CacheService.writePref(_kBestStreak, next.toString());
    }
  }

  // ---- Seen-question rotation (local) --------------------------------------

  static const _kSeen = 'quiz_seen_ids';

  static Set<String> _seenIds() {
    final raw = CacheService.readPref(_kSeen);
    if (raw == null) return <String>{};
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static void _writeSeen(Set<String> ids) {
    CacheService.writePref(_kSeen, jsonEncode(ids.toList())).ignore();
  }

  /// Remember that [questions] were just played, so the next round rotates to
  /// fresh ones. Called by the play screen when a round loads.
  static void markSeen(Iterable<QuizQuestion> questions) {
    final set = _seenIds()..addAll(questions.map((q) => q.id));
    _writeSeen(set);
  }

  // ---- Rating / lifetime stats (local) -------------------------------------

  static const _kAnswered = 'quiz_total_answered';
  static const _kCorrect = 'quiz_total_correct';

  static int totalAnswered() =>
      int.tryParse(CacheService.readPref(_kAnswered) ?? '') ?? 0;

  static int totalCorrect() =>
      int.tryParse(CacheService.readPref(_kCorrect) ?? '') ?? 0;

  /// Lifetime accuracy as a 0–100 percentage (0 when nothing answered yet).
  static int accuracyPct() {
    final a = totalAnswered();
    if (a == 0) return 0;
    return (totalCorrect() / a * 100).round();
  }

  /// A friendly rank that grows with how many questions the player has gotten
  /// right — the visible "rating".
  static String ratingLabel() {
    final c = totalCorrect();
    if (c >= 400) return 'Master';
    if (c >= 150) return 'Teacher';
    if (c >= 50) return 'Scholar';
    if (c >= 10) return 'Student';
    return 'Beginner';
  }

  /// 1–5 stars derived from lifetime accuracy, for a quick visual rating.
  static int ratingStars() {
    if (totalAnswered() < 5) return 0; // not enough data yet
    final p = accuracyPct();
    if (p >= 90) return 5;
    if (p >= 75) return 4;
    if (p >= 60) return 3;
    if (p >= 40) return 2;
    return 1;
  }

  /// Record one answered question (correct or not) toward the lifetime rating.
  static Future<void> recordAnswer(bool correct) async {
    await CacheService.writePref(_kAnswered, (totalAnswered() + 1).toString());
    if (correct) {
      await CacheService.writePref(_kCorrect, (totalCorrect() + 1).toString());
    }
  }

  // ---- Resume an interrupted round (local) ---------------------------------

  static const _kSession = 'quiz_session';

  /// Rebuild questions from saved ids, preserving order. Skips any that no
  /// longer exist (e.g. the admin deleted one).
  static Future<List<QuizQuestion>> questionsByIds(List<String> ids) async {
    final byId = {for (final q in await all()) q.id: q};
    return [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
  }

  /// Persist the in-progress round so the player can resume after leaving.
  static Future<void> saveSession({
    required List<String> ids,
    required int index,
    required int score,
    required String title,
  }) async {
    await CacheService.writePref(
      _kSession,
      jsonEncode({
        'ids': ids,
        'index': index,
        'score': score,
        'title': title,
      }),
    );
  }

  /// The saved in-progress round, or null. Shape:
  /// `{ids: [...], index, score, title}`.
  static Map<String, dynamic>? loadSession() {
    final raw = CacheService.readPref(_kSession);
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final ids = (m['ids'] as List?) ?? const [];
      if (ids.isEmpty) return null;
      return m;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearSession() => CacheService.writePref(_kSession, '');
}
