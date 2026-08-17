// Founder, 18 Aug 2026: *"when click text in egw it should highlight a
// statement from were it starts to where it end n u can hight many
// statements"*.
//
// Two halves are tested here. The sentence boundary is pure logic and is
// tested as such — it is where this feature is most likely to be quietly
// wrong, because these books are dense with the exact constructions a naive
// "split on full stop" gets wrong: initials (E. G. White), abbreviations
// (Mrs., vol., p.) and verse references (Col. 2:3). Highlighting two words
// of a statement looks far more broken than not highlighting at all.
//
// The gesture is tested against the real reader, because the offset a tap
// produces is an offset into the PAINTED paragraph, which is not the same
// string as the block's own text: a page anchor contributes no characters
// to the source but is painted as a WidgetSpan, which occupies one.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:advent_connect_zw/models/egw_book_model.dart';
import 'package:advent_connect_zw/screens/library/egw_reader_screen.dart';
import 'package:advent_connect_zw/services/cache_service.dart';
import 'package:advent_connect_zw/services/egw_highlights.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

/// The book's paragraph, not the chrome. The reader paints several
/// `RichText`s — the title in the top bar, the page counter in the bottom —
/// and tapping one of those would prove nothing.
final _paragraph = find.byWidgetPredicate(
  (w) =>
      w is RichText &&
      w.text.toPlainText().contains('The first statement stands alone'),
);

String _sentenceAround(String text, int offset) {
  final r = EgwHighlights.sentenceAt(text, offset);
  return text.substring(r.start, r.end);
}

void main() {
  group('where a statement starts and ends', () {
    test('a plain sentence in the middle of a paragraph', () {
      const text = 'He held communion. His motives were alien. God is love.';
      expect(_sentenceAround(text, 25), 'His motives were alien.');
    });

    test('the first and last statements are reachable', () {
      const text = 'One thing is sure. Another follows it. And a third.';
      expect(_sentenceAround(text, 2), 'One thing is sure.');
      expect(_sentenceAround(text, 45), 'And a third.');
    });

    test('initials do not end a statement', () {
      // The single most common construction in this whole shelf.
      const text = 'This was written by E. G. White in 1892. Then came more.';
      expect(
        _sentenceAround(text, 25),
        'This was written by E. G. White in 1892.',
      );
    });

    test('an abbreviation does not end a statement', () {
      const text = 'See vol. 4 of the series. It follows on.';
      expect(_sentenceAround(text, 2), 'See vol. 4 of the series.');
    });

    test('a verse reference does not end a statement', () {
      const text = 'He is our wisdom, Col. 2:3 says so plainly. Rest there.';
      expect(
        _sentenceAround(text, 5),
        'He is our wisdom, Col. 2:3 says so plainly.',
      );
    });

    test('a closing quote belongs to the statement it closes', () {
      const text = 'He said, "Come unto me." The invitation stands.';
      expect(_sentenceAround(text, 5), 'He said, "Come unto me."');
    });

    test('a question or an exclamation ends one too', () {
      const text = 'What shall a man give? Nothing at all! Rest there.';
      expect(_sentenceAround(text, 5), 'What shall a man give?');
      expect(_sentenceAround(text, 25), 'Nothing at all!');
    });

    test('text with no break at all is one statement', () {
      // A one-line quotation, and the case where a stricter rule would
      // return nothing and silently do nothing on tap.
      const text = 'Without a terminator anywhere in it';
      expect(_sentenceAround(text, 10), text);
    });

    test('an offset past the end still resolves', () {
      const text = 'A short line. And another.';
      expect(_sentenceAround(text, 999), 'And another.');
      expect(EgwHighlights.sentenceAt('', 0), (start: 0, end: 0));
    });
  });

  group('a stored passage is found again in the source', () {
    test('even when the source wrapped across a line', () {
      // Passages are stored with whitespace collapsed; the book keeps its
      // own line breaks. A plain indexOf misses this, and the highlight
      // then stores correctly and simply never paints — which from the
      // outside is identical to the feature not working.
      const source = 'His motives would be alien\nto those that actuate';
      final found = EgwHighlights.rangesIn(
        source,
        ['His motives would be alien to those that actuate'],
      );
      expect(found, hasLength(1));
      expect(source.substring(found.first.start, found.first.end), source);
    });

    test('an exact match still wins unchanged', () {
      final found = EgwHighlights.rangesIn('one two three', ['two']);
      expect(found, [(start: 4, end: 7)]);
    });
  });

  group('tapping a statement in the reader', () {
    late Directory dir;
    var boxSeq = 0;

    EgwBook book() => const EgwBook(
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
                EgwSpan(text: 'The first statement stands alone. '),
                // A page anchor: no characters in the source, one character
                // in the painted paragraph.
                EgwSpan(text: '', page: 18),
                EgwSpan(text: 'The second statement follows it.'),
              ],
            ),
          ],
        ),
      ],
    );

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('egw_tap_highlight');
      Hive.init(dir.path);
      await CacheService.debugUseBox(
        await Hive.openBox<String>('tap_highlight_${boxSeq++}'),
      );
    });

    tearDown(() async {
      await CacheService.debugUseBox(null);
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    Future<void> pumpReader(WidgetTester t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: EgwReaderScreen(book: book(), bookId: 'tap-book'),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('tapping the first words highlights that statement only',
        (t) async {
      await pumpReader(t);

      // The very start of the paragraph — unambiguously inside statement one.
      final box = t.getRect(_paragraph);
      await t.tapAt(Offset(box.left + 6, box.top + 6));
      await t.pump();

      final saved = EgwHighlights.forChapter('tap-book', 'content02');
      expect(saved, hasLength(1));
      expect(saved.single, 'The first statement stands alone.');
    });

    testWidgets('tapping the same statement again removes it', (t) async {
      await pumpReader(t);

      final box = t.getRect(_paragraph);
      await t.tapAt(Offset(box.left + 6, box.top + 6));
      await t.pump();
      expect(EgwHighlights.forChapter('tap-book', 'content02'), hasLength(1));

      await t.tapAt(Offset(box.left + 6, box.top + 6));
      await t.pump();
      expect(EgwHighlights.forChapter('tap-book', 'content02'), isEmpty);
    });

    testWidgets('many statements accumulate', (t) async {
      // "u can hight many statements" — the part that makes it a reading
      // tool rather than a single marker.
      await pumpReader(t);

      final box = t.getRect(_paragraph);
      await t.tapAt(Offset(box.left + 6, box.top + 6));
      await t.pump();
      // Far enough along to be inside the second statement.
      await t.tapAt(Offset(box.right - 10, box.bottom - 6));
      await t.pump();

      final saved = EgwHighlights.forChapter('tap-book', 'content02');
      expect(saved, hasLength(2));
      expect(saved, contains('The first statement stands alone.'));
      expect(saved, contains('The second statement follows it.'));
    });
  });
}
