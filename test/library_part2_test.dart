// Batch 3, part 2 (29 Oct 2026): Library search, Saved & downloads, the
// resource directory and the 28 Fundamental Beliefs.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/data/fundamental_beliefs.dart';
import 'package:advent_connect_zw/screens/library/beliefs_screen.dart';
import 'package:advent_connect_zw/screens/library/library_directory_screen.dart';
import 'package:advent_connect_zw/screens/library/library_saved_screen.dart';
import 'package:advent_connect_zw/screens/library/library_search_screen.dart';
import 'package:advent_connect_zw/services/bible_service.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

Widget _host(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

BibleBook _book(int index, String name, List<List<String>> chapters) =>
    BibleBook(
      index: index,
      name: name,
      abbrev: name.substring(0, 3),
      chapters: chapters,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('28 Fundamental Beliefs', () {
    test('all 28, numbered in order, under the six official headings', () {
      expect(kFundamentalBeliefs.length, 28);
      for (var i = 0; i < 28; i++) {
        expect(kFundamentalBeliefs[i].number, i + 1);
      }
      expect(kFundamentalBeliefs.map((b) => b.group).toSet().length, 6);
      expect(kFundamentalBeliefs[19].title, 'The Sabbath');
    });

    test('every Bible text opens in the bundled Bible', () async {
      final missing = <String>[];
      for (final b in kFundamentalBeliefs) {
        expect(b.texts, isNotEmpty, reason: b.title);
        for (final ref in b.texts) {
          final r = await BibleService.resolveReference(ref);
          if (r == null) {
            missing.add('${b.number}: $ref');
          } else if (r.verse != null &&
              r.verse! > r.book.chapters[r.chapter - 1].length) {
            missing.add('${b.number}: $ref (no such verse)');
          }
        }
      }
      expect(missing, isEmpty);
    });

    test('links to the official statement', () {
      expect(kBeliefsOfficialUrl, startsWith('https://www.adventist.org/'));
    });

    testWidgets('the list says the summaries are ours', (t) async {
      await t.pumpWidget(_host(const BeliefsScreen()));
      await t.pump();
      expect(find.textContaining('written for this app'), findsOneWidget);
      expect(find.textContaining('adventist.org'), findsWidgets);
    });
  });

  group('search', () {
    test('beliefs match by word or number', () {
      expect(
        LibrarySearchScreen.matchBeliefs('sabbath').map((b) => b.number),
        contains(20),
      );
      expect(
        LibrarySearchScreen.matchBeliefs('20').single.title,
        'The Sabbath',
      );
      expect(LibrarySearchScreen.matchBeliefs(''), isEmpty);
    });

    testWidgets('is the Library only, with type filters', (t) async {
      await t.pumpWidget(_host(const LibrarySearchScreen(autoLoad: false)));
      await t.pump();
      for (final f in const ['All', 'Bible', 'Hymns', 'EGW', 'Beliefs']) {
        expect(find.text(f), findsOneWidget, reason: f);
      }
      final src = File(
        'lib/screens/library/library_search_screen.dart',
      ).readAsStringSync();
      for (final social in const [
        'FeedService',
        'MarketplaceService',
        "'posts'",
      ]) {
        expect(src.contains(social), isFalse, reason: social);
      }
    });
  });

  group('saved', () {
    final books = [
      _book(0, 'Genesis', [
        ['In the beginning God created the heaven and the earth.'],
      ]),
      _book(1, 'Exodus', [
        ['Now these are the names', 'And Reuben, Simeon'],
      ]),
    ];

    test('bookmarks, highlights and notes merge per verse, in Bible order', () {
      final out = LibrarySavedScreen.mergeVerses(
        books,
        bookmarks: {'1:0:1', '0:0:0'},
        highlights: {'0:0:0': 2},
        notes: {'1:0:1': 'Remember this'},
      );
      expect(out.map((v) => v.reference), ['Genesis 1:1', 'Exodus 1:2']);
      expect(out.first.bookmarked, isTrue);
      expect(out.first.highlight, 2);
      expect(out.last.note, 'Remember this');
    });

    test('keys that do not resolve are skipped, never shown blank', () {
      final out = LibrarySavedScreen.mergeVerses(
        books,
        bookmarks: {'9:0:0', '0:5:0', '0:0:9', 'junk', '0:0'},
        highlights: const {},
        notes: const {},
      );
      expect(out, isEmpty);
    });

    testWidgets('an empty shelf says how to fill it', (t) async {
      await t.pumpWidget(_host(const LibrarySavedScreen(autoLoad: false)));
      await t.pump();
      expect(find.textContaining('Nothing saved yet'), findsOneWidget);
      await t.tap(find.text('On this phone'));
      await t.pumpAndSettle();
      expect(find.text('Bible — King James Version'), findsOneWidget);
    });
  });

  group('directory', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('lists only real resources, never Advent AI', () {
      final titles = LibraryDirectoryScreen.entries
          .map((e) => e.title)
          .toList();
      expect(titles, contains('28 Fundamental Beliefs'));
      expect(titles, contains('Prayer'));
      expect(
        titles.any((t) => t.contains('AI')),
        isFalse,
        reason: 'Advent AI opens from the Chat inbox only',
      );
      for (final e in LibraryDirectoryScreen.entries) {
        expect(e.source, isNotEmpty, reason: e.title);
        expect(e.offline, isNotEmpty, reason: e.title);
      }
    });

    test('no Music on iOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(
        LibraryDirectoryScreen.entries.map((e) => e.title),
        isNot(contains('Music')),
      );
    });
  });
}
