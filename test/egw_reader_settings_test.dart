// Founder, 18 Aug 2026: *"text size, day, sepia dosent work"* in the EGW
// reader — tapping the controls appeared to do nothing.
//
// The notifier wiring was never the problem, and the temptation to "add the
// missing rebuild" would have changed a correct line: the reader's build is
// already wrapped in a `ValueListenableBuilder` on `EgwReaderPrefs.revision`
// and both setters bump it.
//
// What was wrong is WHEN they bump it. Both setters read
//
//     await CacheService.writePref(...);   // a Hive write — real disk
//     revision.value++;                    // the UI, second
//
// so the page could not change until the handset had finished a disk write.
// Hive serialises a box behind one queue, and `CacheService.initialize()`
// kicks off a prune + `compact()` of a box that grows on every feed refresh
// — so on a real phone that `await` is not free, and while it is outstanding
// the reader, the swatches and the slider thumb all sit exactly where they
// were. From the outside that is "the button does nothing".
//
// These tests pump ONE frame after each tap and never call `runAsync`, so
// nothing disk-bound can complete. That is the slow handset, made
// deterministic: a control that only works once storage has caught up fails
// here, and a control that answers the finger first passes.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:advent_connect_zw/models/egw_book_model.dart';
import 'package:advent_connect_zw/screens/library/egw_reader_screen.dart';
import 'package:advent_connect_zw/services/cache_service.dart';
import 'package:advent_connect_zw/services/egw_reader_prefs.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

EgwBook _book() => const EgwBook(
  title: 'Steps to Christ',
  author: 'Ellen G. White',
  chapters: [
    EgwChapter(
      id: 'content02',
      title: "Chapter 2—The Sinner's Need of Christ",
      blocks: [
        EgwBlock(
          kind: EgwBlockKind.heading,
          spans: [EgwSpan(text: "Chapter 2—The Sinner's Need of Christ")],
        ),
        EgwBlock(
          kind: EgwBlockKind.paragraph,
          spans: [
            EgwSpan(
              text: 'He held communion with Him, and his motives would be '
                  'alien to those that actuate the sinless dwellers in the '
                  'courts above.',
            ),
          ],
        ),
      ],
    ),
  ],
);

Widget _host() => MaterialApp(
  theme: AppTheme.light,
  darkTheme: AppTheme.dark,
  themeMode: ThemeMode.light,
  home: EgwReaderScreen(book: _book(), bookId: 'test-book'),
);

/// The reader's own ground — what the member is actually looking at.
Color? _pageGround(WidgetTester t) =>
    t.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor;

/// The largest type size currently laid out, which tracks the scale setting
/// (body is 17.5x, heading 24x). Asserting the RENDERED size rather than the
/// stored preference is the point: the complaint was about the page, not
/// about storage.
double _largestType(WidgetTester t) {
  final sizes = t
      .widgetList<RichText>(find.byType(RichText))
      .map((w) => w.text.style?.fontSize ?? 0)
      .toList();
  sizes.sort();
  return sizes.isEmpty ? 0 : sizes.last;
}

Future<void> _openSettings(WidgetTester t) async {
  await t.tap(find.byIcon(Icons.text_fields_rounded));
  await t.pumpAndSettle();
}

void main() {
  late Directory dir;
  var boxSeq = 0;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('egw_reader_prefs_test');
    Hive.init(dir.path);
    // A fresh box NAME per test, rather than `Hive.deleteFromDisk()` in
    // teardown. These tests deliberately leave a write outstanding — that is
    // the condition being reproduced — and closing a box waits on its write
    // queue, which cannot drain once the fake-async zone the write started
    // in has gone. Teardown then sat out the ten-minute test timeout and the
    // whole file read as a hang rather than as failing assertions.
    await CacheService.debugUseBox(
      await Hive.openBox<String>('reader_prefs_${boxSeq++}'),
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

  group('the reading ground answers the finger', () {
    testWidgets('tapping Sepia changes the page on the next frame', (t) async {
      await t.pumpWidget(_host());
      await t.pumpAndSettle();
      expect(_pageGround(t), EgwReadingPalette.day.page);

      await _openSettings(t);
      await t.tap(find.text('Sepia'));
      await t.pump();

      expect(
        _pageGround(t),
        EgwReadingPalette.sepia.page,
        reason: 'the page must not wait on a disk write to change ground',
      );
    });

    testWidgets('the sheet changes ground with the page', (t) async {
      // The second half of the complaint, and the half a fix aimed only at
      // the reader would leave behind. The sheet covers the bottom of the
      // screen and the rest of the page sits behind a modal scrim, so if the
      // sheet keeps its original colour there is almost nothing left to see
      // change — the tap reads as ignored even when it was not.
      await t.pumpWidget(_host());
      await t.pumpAndSettle();

      await _openSettings(t);
      await t.tap(find.text('Night'));
      await t.pump();

      // The NEAREST enclosing Material is the sheet's own ground. The
      // furthest is the modal route's, which is transparent by design.
      final sheet = t.widget<Material>(
        find
            .ancestor(
              of: find.text('TEXT SIZE'),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(sheet.color, EgwReadingPalette.night.page);
    });

    testWidgets('the chosen swatch is the one that reads as selected',
        (t) async {
      await t.pumpWidget(_host());
      await t.pumpAndSettle();

      await _openSettings(t);
      await t.tap(find.text('Sepia'));
      await t.pump();

      // Selected is drawn with a 2px accent border; the others get a 1px
      // rule. Whichever swatch is heavier is the one the member believes is
      // active, so this is the control's own feedback, not a detail.
      final borders = <String, double>{};
      for (final label in ['Day', 'Sepia', 'Night']) {
        final box = t.widget<Container>(
          find
              .ancestor(of: find.text(label), matching: find.byType(Container))
              .first,
        );
        final decoration = box.decoration as BoxDecoration;
        borders[label] = decoration.border!.top.width;
      }
      expect(borders['Sepia'], greaterThan(borders['Day']!));
      expect(borders['Sepia'], greaterThan(borders['Night']!));
    });
  });

  group('text size answers the finger', () {
    testWidgets('dragging the slider reflows the page immediately', (t) async {
      await t.pumpWidget(_host());
      await t.pumpAndSettle();
      final before = _largestType(t);
      expect(before, greaterThan(0));

      await _openSettings(t);
      await t.drag(find.byType(Slider), const Offset(300, 0));
      await t.pump();

      expect(
        _largestType(t),
        greaterThan(before),
        reason: 'the page must reflow while the thumb is still under the '
            'finger, not after storage catches up',
      );
    });

    testWidgets('the thumb follows the drag', (t) async {
      await t.pumpWidget(_host());
      await t.pumpAndSettle();

      await _openSettings(t);
      expect(t.widget<Slider>(find.byType(Slider)).value, 1.0);

      await t.drag(find.byType(Slider), const Offset(300, 0));
      await t.pump();

      expect(
        t.widget<Slider>(find.byType(Slider)).value,
        greaterThan(1.0),
        reason: 'a thumb that springs back is the clearest possible way to '
            'tell someone their tap was ignored',
      );
    });
  });

  // Answering the finger first must not mean losing the setting. The write
  // still happens — it just no longer stands between the tap and the page.
  testWidgets('the choice still reaches storage', (t) async {
    await t.pumpWidget(_host());
    await t.pumpAndSettle();

    await _openSettings(t);
    await t.tap(find.text('Night'));
    await t.pump();

    // Readable back immediately: the write is started synchronously and
    // Hive updates its in-memory keystore before the first `await`. Only
    // the flush to disk is still outstanding, and nothing on screen — or
    // here — depends on it.
    expect(CacheService.readPref('pref:egw_reader_theme'), 'night');
    expect(EgwReaderPrefs.theme(), EgwReadingTheme.night);
  });
}
