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

  /// A practice round: [count] random questions, optionally from one category.
  static Future<List<QuizQuestion>> practiceSet({
    String? category,
    int count = 10,
  }) async {
    final list = await all();
    final pool = category == null
        ? List.of(list)
        : list.where((q) => q.category == category).toList();
    pool.shuffle();
    return pool.take(count).toList();
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
}
