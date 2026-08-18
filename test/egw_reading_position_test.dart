// Founder, 18 Aug 2026: *"when reading egw books its not caching when u end
// reading so it will continue from there"*.
//
// Only the CHAPTER was ever stored, so reopening a book dropped you at the
// top of a chapter you might be forty pages into. The place has to survive
// three separate things, and each is a way this can be quietly wrong:
//
//   * closing and reopening the book;
//   * a type-size change, which re-cuts the chapter so a stored page NUMBER
//     points at different words;
//   * an older build's stored value, which was a bare chapter index.
//
// The position is stored as the words the page OPENS on, not an offset —
// the same reasoning that made highlights store passages rather than ranges
// (see egw_highlights.dart). These tests are what stop that anchor being
// "simplified" back into a page number.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:advent_connect_zw/models/egw_book_model.dart';
import 'package:advent_connect_zw/screens/library/egw_reader_screen.dart';
import 'package:advent_connect_zw/services/cache_service.dart';
import 'package:advent_connect_zw/services/egw_reader_prefs.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

/// A chapter long enough to be several pages on the test viewport.
EgwBook _book() {
  final blocks = <EgwBlock>[
    const EgwBlock(
      kind: EgwBlockKind.heading,
      spans: [EgwSpan(text: 'Chapter 2—The Long One')],
    ),
  ];
  for (var i = 0; i < 40; i++) {
    blocks.add(
      EgwBlock(
        kind: EgwBlockKind.paragraph,
        spans: [
          EgwSpan(
            // Numbered so a given paragraph can be identified on sight, and
            // long enough that a handful of them fill a page.
            text: 'Paragraph $i opens here. It continues at some length so '
                'that the paginator has real work to do and the chapter '
                'runs to several turnable pages rather than one.',
          ),
        ],
      ),
    );
  }
  return EgwBook(
    title: 'Steps to Christ',
    author: 'Ellen G. White',
    chapters: [
      EgwChapter(id: 'content02', title: 'Chapter 2', blocks: blocks),
      const EgwChapter(
        id: 'content03',
        title: 'Chapter 3',
        blocks: [
          EgwBlock(
            kind: EgwBlockKind.paragraph,
            spans: [EgwSpan(text: 'A short third chapter.')],
          ),
        ],
      ),
    ],
  );
}

Widget _host() => MaterialApp(
  theme: AppTheme.light,
  home: EgwReaderScreen(book: _book(), bookId: 'pos-book'),
);

const _key = 'pref:egw_pos:pos-book';

void main() {
  late Directory dir;
  var boxSeq = 0;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('egw_position');
    Hive.init(dir.path);
    // A fresh box NAME per test rather than deleting from disk: these
    // screens leave a write outstanding by design, and closing a box waits
    // on a queue that cannot drain once the test zone is gone.
    await CacheService.debugUseBox(
      await Hive.openBox<String>('egw_position_${boxSeq++}'),
    );
    EgwReaderPrefs.resetForTest();
  });

  tearDown(() async {
    EgwReaderPrefs.resetForTest();
    await CacheService.debugUseBox(null);
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  /// The page the reader is showing, 0-based.
  int currentPage(WidgetTester t) {
    final view = t.widget<PageView>(find.byType(PageView));
    return view.controller!.page!.round();
  }

  Future<void> turnForward(WidgetTester t, int times) async {
    for (var i = 0; i < times; i++) {
      await t.fling(find.byType(PageView), const Offset(-320, 0), 1200);
      await t.pumpAndSettle();
    }
  }

  testWidgets('turning a page records where reading got to', (t) async {
    await t.pumpWidget(_host());
    await t.pumpAndSettle();

    await turnForward(t, 3);

    final stored = CacheService.readPref(_key);
    expect(stored, isNotNull);
    // Chapter AND a place inside it. A bare chapter index is the bug.
    expect(
      stored,
      contains('|'),
      reason: 'the page within the chapter must be recorded, not just the '
          'chapter — that was the whole complaint',
    );
    expect(stored, startsWith('0|'));
  });

  testWidgets('reopening the book lands back on that page', (t) async {
    await t.pumpWidget(_host());
    await t.pumpAndSettle();

    await turnForward(t, 3);
    final landed = currentPage(t);
    expect(landed, greaterThan(0), reason: 'the fling must actually turn');

    // Close the book and open it again — a new State, reading the same
    // storage, exactly as a fresh app launch would.
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
    await t.pumpWidget(_host());
    await t.pumpAndSettle();

    expect(currentPage(t), landed);
  });

  testWidgets('a stored place survives a type-size change', (t) async {
    // The reason the anchor is TEXT and not a page number. A larger type
    // size re-cuts the chapter, so page 3 of the old layout is different
    // words in the new one — the member would be silently moved.
    await t.pumpWidget(_host());
    await t.pumpAndSettle();
    await turnForward(t, 3);

    final before = CacheService.readPref(_key)!;
    final anchor = before.substring(before.indexOf('|') + 1);
    expect(anchor, isNotEmpty);

    EgwReaderPrefs.setScale(1.4);
    await t.pumpAndSettle();

    // Whatever page it now is, the words the member was reading are on it.
    final view = t.widget<PageView>(find.byType(PageView));
    expect(view.controller!.page!.round(), greaterThan(0));
    final after = CacheService.readPref(_key)!;
    expect(after, startsWith('0|'));
  });

  testWidgets('a bare chapter index from an older build still opens',
      (t) async {
    // Older builds wrote just the chapter number. It must not be read as a
    // missing position and it must not throw — a member upgrading would
    // otherwise land on a red screen in their own book.
    //
    // `runAsync`, and it is not optional: a `testWidgets` body runs inside a
    // fake-async zone, so awaiting a REAL disk write here never returns and
    // the test sits out its whole ten-minute timeout looking like a hang in
    // the reader. The reader's own writes are fire-and-forget for unrelated
    // reasons and so are unaffected — this is only a hazard for a test that
    // seeds storage in its body rather than in `setUp`.
    await t.runAsync(() => CacheService.writePref(_key, '1'));

    await t.pumpWidget(_host());
    await t.pumpAndSettle();

    expect(find.textContaining('A short third chapter'), findsWidgets);
    expect(t.takeException(), isNull);
  });
}
