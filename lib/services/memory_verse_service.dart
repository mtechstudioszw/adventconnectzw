import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/bible_translation.dart';
import 'bible_service.dart';
import 'bible_translation_service.dart';
import 'cache_service.dart';

/// A verse (or a short run of verses) the member is learning by heart.
@immutable
class MemoryVerse {
  const MemoryVerse({
    required this.book,
    required this.chapter,
    required this.from,
    required this.to,
    required this.translation,
    required this.level,
    required this.due,
    required this.added,
  });

  /// 0-based, like the reader. [from]..[to] inclusive.
  final int book;
  final int chapter;
  final int from;
  final int to;

  /// The translation it was learnt in (`BibleTranslation.id`).
  final String translation;

  /// 0 = new … [MemoryVerseService.maxLevel] = known.
  final int level;
  final DateTime due;
  final DateTime added;

  String get id => '$book:$chapter:$from-$to';

  MemoryVerse copyWith({int? level, DateTime? due}) => MemoryVerse(
    book: book,
    chapter: chapter,
    from: from,
    to: to,
    translation: translation,
    level: level ?? this.level,
    due: due ?? this.due,
    added: added,
  );

  Map<String, dynamic> toJson() => {
    'b': book,
    'c': chapter,
    'f': from,
    't': to,
    'tr': translation,
    'l': level,
    'due': due.toIso8601String(),
    'added': added.toIso8601String(),
  };

  factory MemoryVerse.fromJson(Map<String, dynamic> j) => MemoryVerse(
    book: (j['b'] as num).toInt(),
    chapter: (j['c'] as num).toInt(),
    from: (j['f'] as num).toInt(),
    to: (j['t'] as num).toInt(),
    translation: '${j['tr'] ?? BibleTranslations.kjv.id}',
    level: (j['l'] as num?)?.toInt() ?? 0,
    due: DateTime.tryParse('${j['due']}') ?? DateTime.now(),
    added: DateTime.tryParse('${j['added']}') ?? DateTime.now(),
  );
}

/// Memory verses with simple spaced practice.
///
/// Each level hides more of the verse ([hiddenShare]) and waits longer
/// before it comes back ([intervals]). "Got it" moves up a level, "Again"
/// moves down one and brings it back today. Learnt verses are the member's
/// own, so the key is not `pref:`-prefixed (sign-out clears it).
class MemoryVerseService {
  MemoryVerseService._();

  static const _key = 'memory_verses_v1';
  static const maxLevel = 5;

  /// Days until the next practice, by level reached.
  static const intervals = [0, 1, 3, 7, 14, 30];

  /// Share of words hidden when practising at each level.
  static const hiddenShare = [0.0, 0.25, 0.45, 0.65, 0.85, 1.0];

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Well-known verses to start with. References only — the text comes
  /// from whichever Bible the member reads.
  static const starters = [
    'John 3:16',
    'Psalm 23:1',
    'Proverbs 3:5',
    'Philippians 4:13',
    'Joshua 1:9',
    'Isaiah 41:10',
    'Romans 8:28',
    'Matthew 11:28',
    'Exodus 20:8',
    'Revelation 14:12',
  ];

  static List<MemoryVerse> all() {
    final raw = CacheService.readPref(_key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => MemoryVerse.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static void _save(List<MemoryVerse> list) {
    revision.value++;
    unawaited(
      CacheService.writePref(
        _key,
        jsonEncode(list.map((v) => v.toJson()).toList()),
      ).catchError((Object e) => debugPrint('MemoryVerse save: $e')),
    );
  }

  static bool contains(String id) => all().any((v) => v.id == id);

  /// Verses due now, oldest due first.
  static List<MemoryVerse> due({DateTime? now}) {
    final t = now ?? DateTime.now();
    return all().where((v) => !v.due.isAfter(t)).toList()
      ..sort((a, b) => a.due.compareTo(b.due));
  }

  /// Adds verses [from]..[to]. Returns false if already there.
  static bool add({
    required int book,
    required int chapter,
    required int from,
    int? to,
    String? translation,
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();
    final v = MemoryVerse(
      book: book,
      chapter: chapter,
      from: from,
      to: to ?? from,
      translation: translation ?? BibleTranslationService.active.value,
      level: 0,
      due: t,
      added: t,
    );
    final list = all();
    if (list.any((e) => e.id == v.id)) return false;
    _save(list..add(v));
    return true;
  }

  /// Contiguous runs of [verses] (0-based), so selecting 5, 6 and 9 adds
  /// "5–6" and "9" rather than one entry that skips verses.
  static List<(int, int)> runs(Iterable<int> verses) {
    final sorted = verses.toSet().toList()..sort();
    final out = <(int, int)>[];
    for (final v in sorted) {
      if (out.isNotEmpty && out.last.$2 == v - 1) {
        out[out.length - 1] = (out.last.$1, v);
      } else {
        out.add((v, v));
      }
    }
    return out;
  }

  static void remove(String id) => _save(all()..removeWhere((v) => v.id == id));

  /// Records a practice. [gotIt] false = "Again".
  static void review(String id, {required bool gotIt, DateTime? now}) {
    final t = now ?? DateTime.now();
    final list = all();
    final i = list.indexWhere((v) => v.id == id);
    if (i < 0) return;
    final v = list[i];
    final level = gotIt
        ? math.min(v.level + 1, maxLevel)
        : math.max(v.level - 1, 0);
    final today = DateTime(t.year, t.month, t.day);
    final due = gotIt ? today.add(Duration(days: intervals[level])) : t;
    list[i] = v.copyWith(level: level, due: due);
    _save(list);
  }

  /// Which words to hide at [level] — the same words every time for the
  /// same verse and level, so practice is repeatable, and always a
  /// superset of the level below, so a level never "un-hides" a word.
  static Set<int> hiddenWords(String id, int wordCount, int level) {
    if (wordCount == 0) return {};
    final share = hiddenShare[level.clamp(0, maxLevel)];
    final count = (wordCount * share).round();
    // One fixed shuffle per verse; each level takes a longer prefix.
    final order = List<int>.generate(wordCount, (i) => i)
      ..shuffle(math.Random(_seed(id)));
    return order.take(count).toSet();
  }

  /// A stable seed. `String.hashCode` is not guaranteed to be the same
  /// from one run of the app to the next, and the hidden words must be.
  static int _seed(String s) {
    var h = 17;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7FFFFFFF;
    }
    return h;
  }

  static String reference(MemoryVerse v, List<BibleBook> books) {
    final name = v.book < books.length ? books[v.book].name : '?';
    final verses = v.from == v.to
        ? '${v.from + 1}'
        : '${v.from + 1}-${v.to + 1}';
    return '$name ${v.chapter + 1}:$verses';
  }

  /// The verse text in the translation it was learnt in, falling back to
  /// the bundled KJV when that translation can't be reached offline.
  static Future<({String text, String translation})> text(
    MemoryVerse v,
    List<BibleBook> books,
  ) async {
    final tr = BibleTranslations.byId(v.translation);
    if (!tr.isBundled) {
      final ch = await BibleTranslationService.chapter(
        translation: tr,
        bookIndex: v.book,
        chapter: v.chapter,
      );
      if (ch != null && v.to < ch.verses.length) {
        return (
          text: ch.verses.sublist(v.from, v.to + 1).join(' '),
          translation: tr.name,
        );
      }
    }
    final chapter = books[v.book].chapters[v.chapter];
    final to = math.min(v.to, chapter.length - 1);
    return (
      text: [
        for (var i = v.from; i <= to; i++) BibleService.cleanVerse(chapter[i]),
      ].join(' '),
      translation: BibleTranslations.kjv.name,
    );
  }
}
