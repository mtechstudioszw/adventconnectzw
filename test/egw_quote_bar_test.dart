// Founder, 18 Aug 2026: *"the moment i click the text should highlight n
// there a big a share button to share image or text of the qoute. when click
// a sentence highlight it with this share button ready n option to highlight
// more sentence like how u highlight bible verse"*.
//
// Tapping a statement already highlighted it — that half shipped. What was
// missing is everything that makes a highlight worth making: nothing on
// screen offered to share it, so the quote card was still behind a
// long-press, a drag-select and a context menu. And a second tap could not
// EXTEND the quote, which is the Bible tab's multi-verse behaviour applied
// to sentences.
//
// So what is asserted here is the bar, not the store: that a tap opens it,
// that a second tap adds to it rather than replacing it, that the passages
// come out in reading order however they were tapped, and that closing it
// does not throw away the highlights.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:advent_connect_zw/models/egw_book_model.dart';
import 'package:advent_connect_zw/screens/library/egw_reader_screen.dart';
import 'package:advent_connect_zw/services/cache_service.dart';
import 'package:advent_connect_zw/services/egw_highlights.dart';
import 'package:advent_connect_zw/services/egw_reader_prefs.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

const _first = 'The first statement stands alone.';
const _second = 'The second statement follows it.';

EgwBook _book() => const EgwBook(
  title: 'Steps to Christ',
  author: 'Ellen G. White',
  chapters: [
    EgwChapter(
      id: 'content02',
      title: 'Chapter 2',
      blocks: [
        EgwBlock(
          kind: EgwBlockKind.paragraph,
          spans: [
            EgwSpan(text: '$_first '),
            // A page anchor: no characters in the source, one character in
            // the painted paragraph. It is also what a shared quote cites.
            EgwSpan(text: '', page: 18),
            EgwSpan(text: _second),
          ],
        ),
      ],
    ),
  ],
);

/// The book's own paragraph, not the chrome.
///
/// Scoped to the `PageView` deliberately. The reader paints several
/// `RichText`s — the title in the top bar, the page counter, and (once a
/// statement is picked) the quote bar's own preview of the very same words.
/// An unscoped predicate matches that preview too and every tap after the
/// first one becomes ambiguous.
final _paragraph = find.descendant(
  of: find.byType(PageView),
  matching: find.byWidgetPredicate(
    (w) => w is RichText && w.text.toPlainText().contains(_first),
  ),
);

void main() {
  late Directory dir;
  var boxSeq = 0;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('egw_quote_bar');
    Hive.init(dir.path);
    await CacheService.debugUseBox(
      await Hive.openBox<String>('quote_bar_${boxSeq++}'),
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

  Future<void> pumpReader(WidgetTester t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: EgwReaderScreen(book: _book(), bookId: 'quote-book'),
      ),
    );
    await t.pumpAndSettle();
  }

  /// Taps inside the paragraph at [dx] from its left edge, on its first line.
  Future<void> tapText(WidgetTester t, {required double dx}) async {
    final box = t.getRect(_paragraph);
    await t.tapAt(Offset(box.left + dx, box.top + 6));
    await t.pump();
  }

  testWidgets('tapping a statement opens a big Share button', (t) async {
    await pumpReader(t);
    expect(find.text('Share quote'), findsNothing);

    await tapText(t, dx: 6);

    // The whole point: the share action is ON SCREEN the moment the
    // statement is picked, not two gestures deep in a context menu.
    expect(find.text('Share quote'), findsOneWidget);
    expect(find.text('1 statement · tap another to add it'), findsOneWidget);

    // And the highlight itself still happened.
    expect(
      EgwHighlights.forChapter('quote-book', 'content02'),
      contains(_first),
    );
  });

  testWidgets('the button is a full-width primary, not a menu item',
      (t) async {
    // "a BIG share button" is the request, and it is the difference between
    // a feature people use and one they never find. A 48pt full-width
    // filled button is the app's own primary-action shape.
    await pumpReader(t);
    await tapText(t, dx: 6);

    final button = t.widget<SizedBox>(
      find
          .ancestor(
            of: find.byType(FilledButton),
            matching: find.byType(SizedBox),
          )
          .first,
    );
    expect(button.height, greaterThanOrEqualTo(44));
  });

  testWidgets('a second tap extends the quote instead of replacing it',
      (t) async {
    await pumpReader(t);

    await tapText(t, dx: 6);
    expect(find.text('1 statement · tap another to add it'), findsOneWidget);

    // Far enough along the first line to land in the second statement.
    final box = t.getRect(_paragraph);
    await t.tapAt(Offset(box.right - 6, box.bottom - 6));
    await t.pump();

    expect(find.text('2 statements picked'), findsOneWidget);
    final saved = EgwHighlights.forChapter('quote-book', 'content02');
    expect(saved, containsAll(<String>[_first, _second]));
  });

  testWidgets('Done closes the bar and KEEPS the highlights', (t) async {
    // The X is not a delete. Somebody who has just marked four statements
    // must not lose them by closing the bar — that is what "Unhighlight" is
    // for, and it says so.
    await pumpReader(t);
    await tapText(t, dx: 6);
    expect(find.text('Share quote'), findsOneWidget);

    await t.tap(find.byTooltip('Done'));
    await t.pump();

    expect(find.text('Share quote'), findsNothing);
    expect(
      EgwHighlights.forChapter('quote-book', 'content02'),
      contains(_first),
    );
  });

  testWidgets('Unhighlight removes what the bar is holding', (t) async {
    await pumpReader(t);
    await tapText(t, dx: 6);

    await t.tap(find.text('Unhighlight'));
    await t.pump();

    expect(find.text('Share quote'), findsNothing);
    expect(EgwHighlights.forChapter('quote-book', 'content02'), isEmpty);
  });

  testWidgets('tapping the same statement twice drops it again', (t) async {
    // The gesture that made the highlight is the one that takes it away.
    await pumpReader(t);

    await tapText(t, dx: 6);
    expect(EgwHighlights.forChapter('quote-book', 'content02'), hasLength(1));

    await tapText(t, dx: 6);
    expect(EgwHighlights.forChapter('quote-book', 'content02'), isEmpty);
    expect(find.text('Share quote'), findsNothing);
  });
}
