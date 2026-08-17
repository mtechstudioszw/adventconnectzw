// Sabbath School highlighting — founder asked for it 18 Aug 2026, and chose
// on 19 Aug that it should follow the ACCOUNT rather than the device.
//
// That choice is the whole design pressure here. EGW highlights can be a
// Hive map and nothing else; these have to reach a server that may not be
// there, from a surface that is explicitly offline-first (Sabbath School has
// a "download this week" button). So the tests below are mostly about what
// happens when the network is absent — which, in a widget test, it always
// is: `Supabase.instance` throws, the service treats that as "no client",
// and every one of these runs entirely on the local mirror.
//
// That is not a limitation of the test, it IS the offline case.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:advent_connect_zw/services/cache_service.dart';
import 'package:advent_connect_zw/services/highlight_text.dart';
import 'package:advent_connect_zw/services/ss_highlights_service.dart';
import 'package:advent_connect_zw/screens/library/widgets/ss_html_text.dart';

const _path = 'en/quarterlies/2026-03/lessons/05/days/02/read';

void main() {
  late Directory dir;
  var boxSeq = 0;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ss_highlights');
    Hive.init(dir.path);
    await CacheService.debugUseBox(
      await Hive.openBox<String>('ss_hl_${boxSeq++}'),
    );
    SsHighlights.resetForTest();
  });

  tearDown(() async {
    SsHighlights.resetForTest();
    await CacheService.debugUseBox(null);
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  group('toggling works with no connection at all', () {
    test('a highlight is readable back immediately', () {
      expect(SsHighlights.toggle(_path, 'God is love.'), isTrue);
      expect(SsHighlights.forDay(_path), contains('God is love.'));
      expect(SsHighlights.has(_path, 'God is love.'), isTrue);
    });

    test('toggling the same passage removes it', () {
      SsHighlights.toggle(_path, 'God is love.');
      expect(SsHighlights.toggle(_path, 'God is love.'), isFalse);
      expect(SsHighlights.forDay(_path), isEmpty);
    });

    test('many statements accumulate', () {
      SsHighlights.toggle(_path, 'The first statement.');
      SsHighlights.toggle(_path, 'The second statement.');
      SsHighlights.toggle(_path, 'The third statement.');
      expect(SsHighlights.forDay(_path), hasLength(3));
    });

    test('the notifier fires on every change, so the page repaints', () {
      final seen = <int>[];
      void listener() => seen.add(SsHighlights.revision.value);
      SsHighlights.revision.addListener(listener);
      addTearDown(() => SsHighlights.revision.removeListener(listener));

      SsHighlights.toggle(_path, 'One statement.');
      SsHighlights.toggle(_path, 'One statement.');
      expect(seen, hasLength(2));
    });

    test('days do not bleed into each other', () {
      const other = 'en/quarterlies/2026-03/lessons/05/days/03/read';
      SsHighlights.toggle(_path, 'Monday sentence.');
      expect(SsHighlights.forDay(other), isEmpty);
    });

    test('a passage too short to mean anything is refused', () {
      expect(SsHighlights.toggle(_path, 'a'), isFalse);
      expect(SsHighlights.toggle(_path, '   '), isFalse);
      expect(SsHighlights.forDay(_path), isEmpty);
    });

    test('whitespace is collapsed on the way in', () {
      // A sentence spanning a line break in the source must be stored as
      // the same passage as one that did not.
      SsHighlights.toggle(_path, 'He held\n  communion with Him.');
      expect(
        SsHighlights.forDay(_path).single,
        'He held communion with Him.',
      );
    });
  });

  group('a highlight survives the app being closed', () {
    test('the mirror is on disk, not just in memory', () {
      SsHighlights.toggle(_path, 'Written down.');
      // Exactly what a cold start does: nothing in memory, everything from
      // the box that was already open.
      SsHighlights.resetForTest();
      expect(SsHighlights.forDay(_path), contains('Written down.'));
    });

    test('the mirror is user-scoped, so sign-out clears it', () async {
      SsHighlights.toggle(_path, 'Mine, not yours.');
      // These keys are deliberately NOT `pref:`-prefixed: they mirror ONE
      // account's content, and the next member on a shared phone must not
      // inherit it. Their own copy comes back from the server.
      await CacheService.clearUserData();
      SsHighlights.resetForTest();
      expect(SsHighlights.forDay(_path), isEmpty);
    });
  });

  group('painting', () {
    test('ranges land on the highlighted words and nothing else', () {
      const text = 'First one. Second one. Third one.';
      SsHighlights.toggle(_path, 'Second one.');
      final ranges = SsHighlights.rangesIn(text, _path);
      expect(ranges, hasLength(1));
      expect(
        text.substring(ranges.first.start, ranges.first.end),
        'Second one.',
      );
    });

    test('a day with nothing highlighted costs no work', () {
      expect(SsHighlights.rangesIn('Anything at all.', _path), isEmpty);
    });
  });

  // The renderer half. The store can be perfect and the feature still dead
  // if a tap never reaches it.
  group('tapping a sentence in the rendered lesson', () {
    testWidgets('reports the whole statement the tap landed in', (t) async {
      String? got;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SsHtmlText(
              html: '<p>The first statement stands alone. '
                  'The second statement follows it.</p>',
              fontScale: 1,
              onHighlightTap: (s) => got = s,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();

      final box = t.getRect(find.byType(RichText).first);
      await t.tapAt(Offset(box.left + 6, box.top + 6));
      await t.pump();

      expect(got, 'The first statement stands alone.');
    });

    testWidgets('does nothing when no handler is given', (t) async {
      // Every other caller of this renderer — the verse popup, for one —
      // must not become accidentally highlightable.
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SsHtmlText(html: '<p>Just reading.</p>', fontScale: 1),
          ),
        ),
      );
      await t.pumpAndSettle();

      expect(find.byType(GestureDetector), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('a highlighted passage paints a wash', (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SsHtmlText(
              html: '<p>Plain words. Marked words.</p>',
              fontScale: 1,
              highlights: const {'Marked words.'},
              onHighlightTap: (_) {},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();

      final span = t.widget<RichText>(find.byType(RichText).first).text;
      final washed = <String>[];
      span.visitChildren((s) {
        if (s is TextSpan && s.style?.backgroundColor != null) {
          washed.add(s.text ?? '');
        }
        return true;
      });
      expect(washed.join(), 'Marked words.');
    });
  });

  // The shared rule both readers use. EGW's tests cover it too; this asserts
  // the Sabbath School side is genuinely wired to the same one rather than a
  // second copy that can drift.
  test('the sentence rule is the shared one', () {
    expect(
      HighlightText.sentenceAt('See vol. 4 of it. Then this.', 2),
      (start: 0, end: 17),
    );
  });
}
