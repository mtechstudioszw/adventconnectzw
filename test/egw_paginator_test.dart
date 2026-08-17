// Splitting a chapter into turnable pages.
//
// The founder asked for the reader to feel "like an actual book" — pages you
// turn, not a column you scroll. That needs the text measured and cut into
// screen-sized pages, and the two things that can go wrong there are both
// serious:
//
//   * losing text at a cut, which silently deletes scripture from a book;
//   * failing to terminate, which hangs the app on a long paragraph.
//
// Both are asserted here as invariants rather than by example, so they hold
// for any viewport and any type size.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/egw_book_model.dart';
import 'package:advent_connect_zw/services/egw_paginator.dart';

const _body = TextStyle(fontSize: 17.5, height: 1.62);
const _heading = TextStyle(fontSize: 24, height: 1.25);

EgwBlock _para(String text) => EgwBlock(
  kind: EgwBlockKind.paragraph,
  spans: [EgwSpan(text: text)],
);

/// A paragraph far taller than any page, to force splitting.
EgwBlock _long([int sentences = 120]) => _para(
  List.generate(
    sentences,
    (i) => 'Sentence number $i about the need of Christ and of grace. ',
  ).join(),
);

List<EgwPage> _run(
  List<EgwBlock> blocks, {
  Size viewport = const Size(320, 560),
}) {
  return EgwPaginator.paginate(
    chapter: EgwChapter(id: 'c', title: 'Chapter', blocks: blocks),
    chapterIndex: 0,
    viewport: viewport,
    bodyStyle: _body,
    headingStyle: _heading,
    devicePixelRatio: 3.0,
  );
}

String _joined(List<EgwPage> pages) =>
    pages.expand((p) => p.blocks).map((b) => b.text).join();

void main() {
  group('packing', () {
    test('short blocks share a page', () {
      final pages = _run([_para('One.'), _para('Two.'), _para('Three.')]);
      expect(pages.length, 1);
      expect(pages.first.blocks.length, 3);
    });

    test('a chapter always yields at least one page', () {
      // The pager indexes into this list; a zero-length range would throw.
      expect(_run(const []).length, 1);
    });

    test('blocks that overflow start a new page', () {
      final pages = _run(List.generate(40, (i) => _para('Paragraph $i.')));
      expect(pages.length, greaterThan(1));
    });
  });

  group('splitting a long paragraph', () {
    test('breaks it across several pages', () {
      final pages = _run([_long()]);
      expect(pages.length, greaterThan(2));
    });

    test('loses not one character', () {
      // The invariant that matters most: cutting must not delete scripture.
      final block = _long();
      final pages = _run([block]);
      expect(_joined(pages), block.text);
    });

    test('loses nothing when mixed with other blocks', () {
      final blocks = [
        _para('Before.'),
        _long(60),
        _para('After.'),
        _long(40),
      ];
      final pages = _run(blocks);
      expect(_joined(pages), blocks.map((b) => b.text).join());
    });

    test('terminates on a viewport too small for a single line', () {
      // Degenerate, but a device with a huge system font can approach it,
      // and spinning here would hang the reader.
      expect(
        () => _run([_long()], viewport: const Size(320, 4)),
        returnsNormally,
      );
    });

    test('every page fits, give or take one line', () {
      final pages = _run([_long()]);
      for (final page in pages) {
        var height = 0.0;
        for (final b in page.blocks) {
          final painter = TextPainter(
            text: TextSpan(text: b.text, style: _body),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: 320);
          height += painter.height + EgwPaginator.gapAfter(b.kind);
        }
        // One line of slack: the cut is made on a line boundary measured
        // from the remainder, so rounding can put it a hair over.
        expect(height, lessThan(560 + _body.fontSize! * _body.height!));
      }
    });
  });

  group('citation survives the cut', () {
    test('a page knows the printed page in force on it', () {
      final block = EgwBlock(
        kind: EgwBlockKind.paragraph,
        spans: [
          const EgwSpan(text: 'Before the break. '),
          const EgwSpan(text: '', page: 18),
          EgwSpan(text: 'After it. ${_long(80).text}'),
        ],
      );
      final pages = _run([block]);
      expect(pages.first.printedPage, 18);
    });

    test('slice keeps a marker that falls inside the range', () {
      const block = EgwBlock(
        kind: EgwBlockKind.paragraph,
        spans: [
          EgwSpan(text: 'abc'),
          EgwSpan(text: '', page: 7),
          EgwSpan(text: 'def'),
        ],
      );
      // The marker sits at offset 3, inside both halves' boundaries.
      expect(block.slice(0, 3).spans.any((s) => s.page == 7), isTrue);
      expect(block.slice(3, 6).spans.any((s) => s.page == 7), isTrue);
      // ...and outside a range that ends before it.
      expect(block.slice(0, 2).spans.any((s) => s.page == 7), isFalse);
    });

    test('slice preserves scripture refs and italics', () {
      const block = EgwBlock(
        kind: EgwBlockKind.paragraph,
        spans: [
          EgwSpan(text: 'See '),
          EgwSpan(text: 'John 3:16', scriptureRef: 'John 3:16'),
          EgwSpan(text: ' now', italic: true),
        ],
      );
      final cut = block.slice(4, 17);
      expect(cut.text, 'John 3:16 now');
      expect(cut.spans.first.scriptureRef, 'John 3:16');
      expect(cut.spans.last.italic, isTrue);
    });
  });
}
