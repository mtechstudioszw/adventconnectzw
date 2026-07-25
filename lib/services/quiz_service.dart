import 'dart:convert';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/quiz_question_model.dart';
import '../models/quiz_round.dart';
import 'cache_service.dart';
import 'connectivity_service.dart';
import 'quiz_generator_service.dart';
import 'quiz_progress_service.dart';

/// Quiz question supply.
///
/// Two sources, deliberately blended:
/// * **curated** rows in Supabase — doctrine, Adventist history, the Spirit
///   of Prophecy: everything a generator can't write; and
/// * **generated** questions from the bundled KJV
///   ([QuizGenerator]) — an endless supply of scripture questions so the
///   bank never runs dry between admin uploads.
///
/// Local player state lives in [QuizProgressService]; this class is purely
/// about *which questions to serve*.
class QuizService {
  QuizService._();
  static final SupabaseClient _client = Supabase.instance.client;

  static const _cacheKey = 'quiz_questions_v1';
  static List<QuizQuestion>? _mem;

  /// A topic with fewer than this many curated questions isn't worth
  /// offering as its own round — you'd see the same question every time.
  /// (Baptism and Sanctuary each shipped with exactly one.)
  static const int minCategorySize = 5;

  /// Share of a mixed round that comes from the generator. Curated stays
  /// the majority so rounds keep their doctrinal centre of gravity.
  static const double generatedShare = 0.4;

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

  /// Topics for the lobby: curated categories with enough questions to make
  /// a real round, plus the generator's endless ones.
  static Future<List<String>> categories() async {
    final list = await all();
    final counts = <String, int>{};
    for (final question in list) {
      counts[question.category] = (counts[question.category] ?? 0) + 1;
    }
    final curated = [
      for (final entry in counts.entries)
        if (entry.value >= minCategorySize) entry.key,
    ]..sort();
    // Deduped: 'Bible Basics' is both a curated category AND one the
    // generator can write, so a naive concat listed it twice in the lobby.
    return <String>{...QuizGenerator.categories, ...curated}.toList();
  }

  // ---- Round building -----------------------------------------------------

  /// Build the question list for a round.
  ///
  /// The Daily Challenge is seeded by the date so every player gets the
  /// same set and can't reshuffle it — which is also why it can't consult
  /// the local seen-list (that would make it device-specific).
  static Future<List<QuizQuestion>> buildRound({
    required QuizMode mode,
    String? category,
  }) async {
    if (mode == QuizMode.mistakes) {
      final missed = QuizProgressService.mistakes();
      return (missed.toList()..shuffle()).take(mode.questionCount).toList();
    }

    final count = mode.questionCount;
    if (mode == QuizMode.daily) return _dailyRound(count);

    // Can the generator write questions for this topic? 'Scripture' is
    // generator-only (no curated rows), 'Bible Basics' exists in both — so
    // picking that topic must still mix in its 30-odd curated questions
    // rather than serving generated ones exclusively.
    final generatorSupports =
        category != null && QuizGenerator.categories.contains(category);

    final pool = await _curatedPool(category);
    final wantGenerated = (category == null || generatorSupports)
        ? (count * generatedShare).round()
        : 0;
    final wantCurated = count - wantGenerated;

    final curated = QuizProgressService.pickFresh(pool, wantCurated);
    // A thin topic (or an empty cache offline) is topped up from the
    // generator rather than served short or repeated.
    final shortfall = count - curated.length;
    final generated = shortfall <= 0
        ? const <QuizQuestion>[]
        : await QuizGenerator.generate(
            count: shortfall,
            // Asking for a topic the generator can't write (say 'Sabbath')
            // would spin through its attempt budget and return nothing,
            // leaving a short round. Fall back to any topic instead — this
            // only bites when the curated cache is empty offline, and a
            // full round of scripture beats an empty one.
            category: generatorSupports ? category : null,
          );

    final round = [...curated, ...generated]..shuffle();
    return round.take(count).toList();
  }

  /// Today's set — identical on every device, curated-first.
  static Future<List<QuizQuestion>> _dailyRound(int count) async {
    final now = DateTime.now();
    final seed = now.year * 10000 + now.month * 100 + now.day;

    final pool = await all();
    final wantGenerated = (count * generatedShare).round();
    final wantCurated = count - wantGenerated;

    // A seeded shuffle is only reproducible if the INPUT order is too, and
    // `all()` selects with no ORDER BY — PostgREST makes no ordering
    // promise, and the offline cache can differ from a fresh fetch. Sorting
    // by numeric id first is what actually makes "everyone gets the same
    // daily set" true rather than merely intended.
    final curated = List.of(pool)
      ..sort((a, b) =>
          (int.tryParse(a.id) ?? 0).compareTo(int.tryParse(b.id) ?? 0));
    curated.shuffle(Random(seed));
    final picked = curated.take(wantCurated).toList();

    final generated = await QuizGenerator.generate(
      count: count - picked.length,
      seed: seed,
    );

    final round = [...picked, ...generated]..shuffle(Random(seed + 1));
    return round.take(count).toList();
  }

  static Future<List<QuizQuestion>> _curatedPool(String? category) async {
    final list = await all();
    if (category == null) return List.of(list);
    return list.where((q) => q.category == category).toList();
  }

  /// Warm both sources so the lobby's Start button is instant.
  static Future<void> warm() async {
    await Future.wait([
      all().then((_) {}),
      QuizGenerator.warm(),
    ]);
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
      'explanation': (explanation == null || explanation.trim().isEmpty)
          ? null
          : explanation.trim(),
      'reference': (reference == null || reference.trim().isEmpty)
          ? null
          : reference.trim(),
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

  /// Player-reported bad question. Generated questions have no row, so the
  /// id is stored as text and the admin sees the rendered question.
  static Future<void> reportQuestion({
    required QuizQuestion question,
    String? reason,
  }) async {
    try {
      await _client.from('quiz_reports').insert({
        'question_id': question.id,
        'is_generated': QuizGenerator.isGenerated(question.id),
        'question_text': question.question,
        'reason': reason,
      });
    } catch (_) {
      // Reporting is a courtesy — never surface a failure mid-round.
    }
  }
}
