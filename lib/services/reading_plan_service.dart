import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'bible_service.dart';
import 'cache_service.dart';

/// One chapter to read. [chapter] is 0-based, like the reader.
@immutable
class PlanChapter {
  const PlanChapter(this.book, this.chapter);
  final BibleBook book;
  final int chapter;

  String get label => '${book.name} ${chapter + 1}';
}

/// A reading plan: a span of books spread over [days].
///
/// Plans are generated from the bundled Bible rather than typed out, so
/// they cannot drift from the text and need no licence. Each day is
/// balanced by VERSE count, not chapter count: by chapters, the day with
/// Psalm 119 (176 verses) would be as "short" as the day with Psalm 117
/// (2 verses).
class ReadingPlan {
  const ReadingPlan({
    required this.id,
    required this.title,
    required this.blurb,
    required this.firstBook,
    required this.lastBook,
    required this.days,
  });

  final String id;
  final String title;
  final String blurb;

  /// Inclusive 0-based book indexes (0 = Genesis, 39 = Matthew).
  final int firstBook;
  final int lastBook;
  final int days;

  /// The schedule: `[day][i]`. Every chapter in range appears exactly once,
  /// in Bible order, and no day is empty.
  List<List<PlanChapter>> schedule(List<BibleBook> books) {
    final chapters = <PlanChapter>[];
    final weights = <int>[];
    for (var b = firstBook; b <= lastBook && b < books.length; b++) {
      for (var c = 0; c < books[b].chapterCount; c++) {
        chapters.add(PlanChapter(books[b], c));
        weights.add(books[b].chapters[c].length);
      }
    }
    return split(
      weights,
      days,
    ).map((range) => [for (final i in range) chapters[i]]).toList();
  }

  /// Splits items with [weights] into [parts] contiguous runs of roughly
  /// equal weight, keeping every run non-empty. Public for the tests.
  static List<List<int>> split(List<int> weights, int parts) {
    final n = weights.length;
    final p = parts.clamp(1, n == 0 ? 1 : n);
    final total = weights.fold<int>(0, (a, b) => a + b);
    final out = <List<int>>[];
    var i = 0;
    var done = 0;
    for (var day = 0; day < p; day++) {
      final run = <int>[];
      final daysLeft = p - day;
      // Cumulative target, so rounding never piles up on the last day.
      final target = total * (day + 1) / p;
      while (i < n) {
        // Leave at least one item for each remaining day.
        if (run.isNotEmpty && n - i <= daysLeft - 1) break;
        final next = done + weights[i];
        // Stop before overshooting unless the run would be empty, and
        // take the item if that lands closer to the target.
        if (run.isNotEmpty &&
            next > target &&
            (next - target) > (target - done)) {
          break;
        }
        run.add(i);
        done = next;
        i++;
        if (done >= target && day < p - 1) break;
      }
      out.add(run);
    }
    // Anything left (only possible through rounding) joins the last day.
    while (i < n) {
      out.last.add(i++);
    }
    return out;
  }
}

/// Progress on one plan.
@immutable
class PlanProgress {
  const PlanProgress({required this.start, required this.done});

  /// The day the member started, local calendar date.
  final DateTime start;

  /// 0-based day indexes ticked off.
  final Set<int> done;

  Map<String, dynamic> toJson() => {
    'start': _ymd(start),
    'done': done.toList()..sort(),
  };

  factory PlanProgress.fromJson(Map<String, dynamic> j) => PlanProgress(
    start: DateTime.tryParse('${j['start']}') ?? DateTime.now(),
    done: ((j['done'] as List?) ?? const [])
        .map((e) => (e as num).toInt())
        .toSet(),
  );

  /// The day the calendar says you should be on (0-based), clamped.
  int scheduledDay(int days, {DateTime? now}) {
    final today = _dateOnly(now ?? DateTime.now());
    final diff = today.difference(_dateOnly(start)).inDays;
    return diff.clamp(0, days - 1);
  }

  /// The first day not yet ticked — what "Today's reading" opens.
  int nextDay(int days) {
    for (var d = 0; d < days; d++) {
      if (!done.contains(d)) return d;
    }
    return days - 1;
  }

  /// Days behind the calendar (0 when on track or ahead).
  int behind(int days, {DateTime? now}) {
    final due = scheduledDay(days, now: now) + 1;
    final doneUpTo = done.where((d) => d < due).length;
    return (due - doneUpTo).clamp(0, days);
  }

  bool finished(int days) => done.length >= days;
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Plans and progress. Progress is the member's own, so the key is NOT
/// `pref:`-prefixed: sign-out clears it, and the next person on a shared
/// phone does not inherit it.
class ReadingPlanService {
  ReadingPlanService._();

  static const _kProgress = 'reading_plans_v1';

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static const plans = <ReadingPlan>[
    ReadingPlan(
      id: 'bible_year',
      title: 'The Bible in a year',
      blurb: 'Genesis to Revelation in 365 days, about 15 minutes a day.',
      firstBook: 0,
      lastBook: 65,
      days: 365,
    ),
    ReadingPlan(
      id: 'nt_90',
      title: 'New Testament in 90 days',
      blurb: 'Matthew to Revelation in three months.',
      firstBook: 39,
      lastBook: 65,
      days: 90,
    ),
    ReadingPlan(
      id: 'gospels_30',
      title: 'The Gospels in 30 days',
      blurb: 'The life of Jesus: Matthew, Mark, Luke and John.',
      firstBook: 39,
      lastBook: 42,
      days: 30,
    ),
    ReadingPlan(
      id: 'psalms_proverbs_60',
      title: 'Psalms and Proverbs in 60 days',
      blurb: 'Prayer, praise and wisdom, a little each day.',
      firstBook: 18,
      lastBook: 19,
      days: 60,
    ),
    ReadingPlan(
      id: 'acts_28',
      title: 'Acts in 28 days',
      blurb: 'The early church, one chapter a day.',
      firstBook: 43,
      lastBook: 43,
      days: 28,
    ),
  ];

  static ReadingPlan? byId(String id) {
    for (final p in plans) {
      if (p.id == id) return p;
    }
    return null;
  }

  static Map<String, PlanProgress> all() {
    final raw = CacheService.readPref(_kProgress);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map).map(
        (k, v) => MapEntry(
          k.toString(),
          PlanProgress.fromJson(Map<String, dynamic>.from(v as Map)),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  static PlanProgress? progress(String planId) => all()[planId];

  /// Started plans, most recently started first.
  static List<(ReadingPlan, PlanProgress)> active() {
    final out = <(ReadingPlan, PlanProgress)>[];
    all().forEach((id, p) {
      final plan = byId(id);
      if (plan != null && !p.finished(plan.days)) out.add((plan, p));
    });
    out.sort((a, b) => b.$2.start.compareTo(a.$2.start));
    return out;
  }

  /// Notify first, persist after — nothing on screen waits on a flush.
  static void _save(Map<String, PlanProgress> map) {
    revision.value++;
    unawaited(
      CacheService.writePref(
        _kProgress,
        jsonEncode(map.map((k, v) => MapEntry(k, v.toJson()))),
      ).catchError((Object e) => debugPrint('ReadingPlan save: $e')),
    );
  }

  static void start(String planId, {DateTime? on}) {
    final map = all()
      ..[planId] = PlanProgress(
        start: _dateOnly(on ?? DateTime.now()),
        done: const {},
      );
    _save(map);
  }

  static void stop(String planId) => _save(all()..remove(planId));

  static void setDone(String planId, int day, bool value) {
    final map = all();
    final p = map[planId];
    if (p == null) return;
    final done = {...p.done};
    value ? done.add(day) : done.remove(day);
    map[planId] = PlanProgress(start: p.start, done: done);
    _save(map);
  }
}
