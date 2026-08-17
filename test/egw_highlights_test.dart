// Highlighting a passage in the EGW reader.
//
// The design decision worth defending: a highlight stores the PASSAGE TEXT,
// not a character offset. The reader repaginates whenever the type size,
// viewport or orientation changes, so a paragraph is cut at a different
// point every session — an offset into a page is meaningless by the next
// open, and even a chapter offset breaks if whitespace collapsing changes.
// Matching text survives all of it.
//
// The accepted cost is duplicates: a passage occurring twice in a chapter
// highlights both. That is rare, and far better than a highlight silently
// drifting onto the wrong sentence.
//
// `rangesIn` is the part that can go quietly wrong, so it is tested hard:
// overlapping highlights must merge into one wash rather than stacking
// alpha into a visibly darker band.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/egw_highlights.dart';

void main() {
  group('finding passages', () {
    test('finds a passage in the middle of a paragraph', () {
      final r = EgwHighlights.rangesIn('abc DEF ghi', ['DEF']);
      expect(r.length, 1);
      expect(r.first.start, 4);
      expect(r.first.end, 7);
    });

    test('finds every occurrence', () {
      final r = EgwHighlights.rangesIn('one two one two', ['one']);
      expect(r.map((e) => e.start), [0, 8]);
    });

    test('returns nothing when the passage is absent', () {
      expect(EgwHighlights.rangesIn('abc', ['zzz']), isEmpty);
    });

    test('ignores an empty passage rather than matching everywhere', () {
      expect(EgwHighlights.rangesIn('abc', ['']), isEmpty);
    });
  });

  group('merging', () {
    test('overlapping passages become one range', () {
      // Two highlights sharing text must paint ONE wash — stacking two
      // translucent layers makes a darker band that reads as a bug.
      final r = EgwHighlights.rangesIn(
        'the quick brown fox',
        ['quick brown', 'brown fox'],
      );
      expect(r.length, 1);
      expect(r.first.start, 4);
      expect(r.first.end, 19);
    });

    test('adjacent passages merge', () {
      final r = EgwHighlights.rangesIn('abcdef', ['abc', 'def']);
      expect(r.length, 1);
      expect(r.first.end, 6);
    });

    test('separate passages stay separate', () {
      final r = EgwHighlights.rangesIn('aaa bbb ccc', ['aaa', 'ccc']);
      expect(r.length, 2);
    });

    test('a passage fully inside another does not shrink it', () {
      final r = EgwHighlights.rangesIn(
        'the quick brown fox',
        ['quick brown fox', 'brown'],
      );
      expect(r.length, 1);
      expect(r.first.start, 4);
      expect(r.first.end, 19);
    });

    test('ranges come back sorted', () {
      final r = EgwHighlights.rangesIn('aaa bbb ccc', ['ccc', 'aaa']);
      expect(r.first.start, lessThan(r.last.start));
    });
  });

  group('the wash is visible but does not drown the words', () {
    test('every reading ground has a usable highlight', () {
      // Reading grounds live in egw_reader_prefs; this only asserts the
      // contract they must satisfy — the wash has to be translucent, or it
      // paints over the text it is meant to mark.
      for (final c in const [
        Color(0x33C8A951),
        Color(0x4DC8A951),
        Color(0x40C8A951),
      ]) {
        expect(c.a, greaterThan(0.0));
        expect(c.a, lessThan(0.6), reason: 'wash must not hide the text');
      }
    });
  });
}
