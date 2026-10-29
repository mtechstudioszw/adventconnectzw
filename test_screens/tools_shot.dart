import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:advent_connect_zw/screens/library/library_hub_screen.dart';
import 'package:advent_connect_zw/screens/library/memory_verses_screen.dart';
import 'package:advent_connect_zw/screens/library/reading_plans_screen.dart';
import 'package:advent_connect_zw/screens/library/sabbath_hours_screen.dart';
import 'package:advent_connect_zw/services/cache_service.dart';
import 'package:advent_connect_zw/services/memory_verse_service.dart';
import 'package:advent_connect_zw/services/reading_plan_service.dart';

import '../test/helpers/fake_supabase.dart';
import 'shot.dart';

void main() {
  setUpAll(() async {
    await loadShotFonts();
    await initFakeSupabase();
    await signInFake('me', metadata: {'full_name': 'Tanatswa'});
    final dir = await Directory.systemTemp.createTemp('tools_shot');
    Hive.init(dir.path);
    // ignore: invalid_use_of_visible_for_testing_member
    await CacheService.debugUseBox(await Hive.openBox<String>('tools'));
    ReadingPlanService.start(
      'bible_year',
      on: DateTime.now().subtract(const Duration(days: 11)),
    );
    for (var d = 0; d < 9; d++) {
      ReadingPlanService.setDone('bible_year', d, true);
    }
    final old = DateTime.now().subtract(const Duration(days: 2));
    MemoryVerseService.add(book: 42, chapter: 2, from: 15, now: old);
    MemoryVerseService.add(book: 19, chapter: 2, from: 4, to: 5, now: old);
    MemoryVerseService.add(book: 18, chapter: 22, from: 0, now: old);
    final id = MemoryVerseService.all()[2].id;
    MemoryVerseService.review(id, gotIt: true);
    MemoryVerseService.review(id, gotIt: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  testWidgets('plans', (t) async {
    await pumpShot(t, const ReadingPlansScreen(), dark: false);
    await saveShot(t, 'plans');
  });

  testWidgets('plan', (t) async {
    await pumpShot(
      t,
      ReadingPlanScreen(plan: ReadingPlanService.byId('bible_year')!),
      dark: false,
    );
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await saveShot(t, 'plan');
  });

  testWidgets('memory', (t) async {
    await pumpShot(t, const MemoryVersesScreen(), dark: false);
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await saveShot(t, 'memory');
  });

  testWidgets('practice', (t) async {
    await pumpShot(t, const MemoryPracticeScreen(), dark: false);
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await saveShot(t, 'practice');
  });

  testWidgets('sabbath', (t) async {
    await pumpShot(
      t,
      SabbathHoursScreen(now: DateTime(2026, 10, 29, 10)),
      dark: false,
    );
    await saveShot(t, 'sabbath');
  });

  testWidgets('hub_today', (t) async {
    await pumpShot(t, const LibraryHubScreen(), dark: false);
    await saveShot(t, 'hub_top', rounds: 10);
    await t.drag(find.byType(Scrollable).first, const Offset(0, -560));
    await saveShot(t, 'hub_today');
  });
}
