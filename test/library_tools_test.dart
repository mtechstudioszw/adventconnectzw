// Reading plans, memory verses and Sabbath hours (owner, 29 Oct 2026).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:advent_connect_zw/screens/library/sabbath_hours_screen.dart';
import 'package:advent_connect_zw/services/bible_service.dart';
import 'package:advent_connect_zw/services/cache_service.dart';
import 'package:advent_connect_zw/services/library_reminders.dart';
import 'package:advent_connect_zw/services/memory_verse_service.dart';
import 'package:advent_connect_zw/services/reading_plan_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  var seq = 0;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('library_tools');
    Hive.init(dir.path);
    await CacheService.debugUseBox(await Hive.openBox<String>('t${seq++}'));
  });
  tearDown(() async {
    await CacheService.debugUseBox(null);
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  group('reading plan split', () {
    test('every item once, in order, no empty day', () {
      final weights = [5, 1, 1, 30, 2, 2, 2, 9, 1, 1, 1, 40, 3];
      for (final parts in [1, 3, 5, 13, 20]) {
        final runs = ReadingPlan.split(weights, parts);
        expect(runs.length, parts.clamp(1, weights.length));
        expect(
          runs.expand((r) => r).toList(),
          List.generate(weights.length, (i) => i),
        );
        expect(runs.every((r) => r.isNotEmpty), isTrue, reason: '$parts');
      }
    });

    test('the real plans cover exactly their books', () async {
      final books = await BibleService.books();
      for (final plan in ReadingPlanService.plans) {
        final days = plan.schedule(books);
        expect(days.length, plan.days, reason: plan.id);
        final chapters = days.expand((d) => d).toList();
        var expected = 0;
        for (var b = plan.firstBook; b <= plan.lastBook; b++) {
          expected += books[b].chapterCount;
        }
        expect(chapters.length, expected, reason: plan.id);
        expect(days.every((d) => d.isNotEmpty), isTrue, reason: plan.id);
      }
      final year = ReadingPlanService.byId('bible_year')!.schedule(books);
      expect(year.first.first.label, 'Genesis 1');
      expect(year.last.last.book.index, 65);
      expect(year.expand((d) => d).length, 1189);
    });

    test('days are balanced by verses, not chapters', () async {
      final books = await BibleService.books();
      final year = ReadingPlanService.byId('bible_year')!.schedule(books);
      final verses = [
        for (final d in year)
          d.fold<int>(0, (n, c) => n + c.book.chapters[c.chapter].length),
      ];
      final avg = verses.reduce((a, b) => a + b) / verses.length;
      // Psalm 119 alone is 176 verses, so a day can't go below that; no
      // day should be more than about double the average otherwise.
      final heavy = verses.where((v) => v > avg * 2.2).length;
      expect(heavy, lessThanOrEqualTo(2), reason: 'avg $avg');
    });
  });

  group('plan progress', () {
    test('next day, behind and finished', () {
      final p = PlanProgress(start: DateTime(2026, 10, 1), done: {0, 1, 3});
      expect(p.nextDay(30), 2);
      final now = DateTime(2026, 10, 5); // day index 4
      expect(p.scheduledDay(30, now: now), 4);
      // Due: days 0-4 (5 days), done within them: 3 → 2 behind
      // (today's reading counts as one of them).
      expect(p.behind(30, now: now), 2);
      expect(p.finished(30), isFalse);
    });

    test('start, tick, stop', () {
      ReadingPlanService.start('gospels_30', on: DateTime(2026, 10, 29));
      expect(ReadingPlanService.active().single.$1.id, 'gospels_30');
      ReadingPlanService.setDone('gospels_30', 0, true);
      expect(ReadingPlanService.progress('gospels_30')!.done, {0});
      ReadingPlanService.stop('gospels_30');
      expect(ReadingPlanService.active(), isEmpty);
    });

    test('progress is the member\'s own (cleared on sign-out)', () {
      final src = File(
        'lib/services/reading_plan_service.dart',
      ).readAsStringSync();
      expect(src.contains("'reading_plans_v1'"), isTrue);
      expect(src.contains("'pref:reading_plans"), isFalse);
    });
  });

  group('memory verses', () {
    test('a selection becomes runs of consecutive verses', () {
      expect(MemoryVerseService.runs({9, 5, 6}), [(5, 6), (9, 9)]);
    });

    test('add once, then practise up and down the levels', () {
      final t = DateTime(2026, 10, 29, 9);
      expect(
        MemoryVerseService.add(book: 42, chapter: 2, from: 15, now: t),
        isTrue,
      );
      expect(
        MemoryVerseService.add(book: 42, chapter: 2, from: 15, now: t),
        isFalse,
      );
      final id = MemoryVerseService.all().single.id;
      expect(MemoryVerseService.due(now: t).length, 1);

      MemoryVerseService.review(id, gotIt: true, now: t);
      var v = MemoryVerseService.all().single;
      expect(v.level, 1);
      expect(v.due, DateTime(2026, 10, 30));
      expect(MemoryVerseService.due(now: t), isEmpty);

      MemoryVerseService.review(id, gotIt: false, now: t);
      v = MemoryVerseService.all().single;
      expect(v.level, 0);
      expect(MemoryVerseService.due(now: t).length, 1);
    });

    test('hidden words grow with the level and never change', () {
      const id = '42:2:15-15';
      expect(MemoryVerseService.hiddenWords(id, 25, 0), isEmpty);
      expect(MemoryVerseService.hiddenWords(id, 25, 5).length, 25);
      for (var l = 1; l < 5; l++) {
        final lower = MemoryVerseService.hiddenWords(id, 25, l);
        final upper = MemoryVerseService.hiddenWords(id, 25, l + 1);
        expect(upper.containsAll(lower), isTrue, reason: 'level $l');
        expect(MemoryVerseService.hiddenWords(id, 25, l), lower);
      }
    });

    test('every starter verse exists', () async {
      for (final ref in MemoryVerseService.starters) {
        final r = await BibleService.resolveReference(ref);
        expect(r?.verse, isNotNull, reason: ref);
      }
    });
  });

  group('reminders', () {
    test('reading: the next days at the chosen time, never in the past', () {
      final now = DateTime(2026, 10, 29, 8, 30);
      final early = LibraryReminders.readingInstants((7, 0), now: now);
      expect(early.first, DateTime(2026, 10, 30, 7));
      expect(early.length, 14);
      final late = LibraryReminders.readingInstants((20, 0), now: now);
      expect(late.first, DateTime(2026, 10, 29, 20));
    });

    test('Sabbath: Fridays only, lead minutes before sundown', () {
      DateTime sunset(DateTime d) =>
          DateTime.utc(d.year, d.month, d.day, 16, 30);
      final now = DateTime(2026, 10, 30, 12); // a Friday
      final list = LibraryReminders.sabbathInstants(
        60,
        now: now,
        count: 3,
        sunsetOn: sunset,
      );
      expect(list.length, 3);
      for (final e in list) {
        expect(e.sunset.difference(e.fireAt), const Duration(minutes: 60));
      }
      expect(list.map((e) => e.sunset.day), [30, 6, 13]);
    });
  });

  group('Sabbath window', () {
    DateTime sunset(DateTime d) => DateTime(d.year, d.month, d.day, 18).toUtc();

    test('midweek → the coming Friday', () {
      final w = SabbathHoursScreen.window(
        DateTime(2026, 10, 28, 12), // Wednesday
        sunsetOn: sunset,
      );
      expect(w.start, DateTime(2026, 10, 30, 18).toUtc());
      expect(w.end, DateTime(2026, 10, 31, 18).toUtc());
    });

    test('Saturday morning → the Sabbath in progress', () {
      final w = SabbathHoursScreen.window(
        DateTime(2026, 10, 31, 10),
        sunsetOn: sunset,
      );
      expect(w.start, DateTime(2026, 10, 30, 18).toUtc());
    });

    test('Saturday after sundown → next week', () {
      final w = SabbathHoursScreen.window(
        DateTime(2026, 10, 31, 19),
        sunsetOn: sunset,
      );
      expect(w.start, DateTime(2026, 11, 6, 18).toUtc());
    });
  });
}
