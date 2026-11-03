import 'dart:io';

import 'package:advent_connect_zw/screens/library/bible_tab.dart';
import 'package:advent_connect_zw/services/bible_service.dart';
import 'package:advent_connect_zw/services/cache_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// Opening the reader at a verse (devotion, verse of the day, search) must
/// land ON that verse, not just highlight it off screen (3 Nov 2026). The
/// chapter used to be a lazy ListView, so a verse far down had no widget
/// to scroll to and the jump did nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('jump').path);
    await CacheService.debugUseBox(await Hive.openBox<String>('jump'));
  });

  testWidgets('John 3:16 is scrolled into view', (t) async {
    final books = await t.runAsync(BibleService.books);
    final john = books!.firstWhere((b) => b.name == 'John');
    await t.binding.setSurfaceSize(const Size(390, 760));
    await t.pumpWidget(
      MaterialApp(
        home: BibleReaderScreen(book: john, chapter: 2, scrollToVerse: 15),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
    final verse = find.textContaining('so loved the world', findRichText: true);
    expect(verse, findsOneWidget);
    final y = t.getTopLeft(verse).dy;
    expect(y, inInclusiveRange(0, 760));
  });
}
