// The reflowable EGW reader.
//
// The founder's brief was "remove the pdf feel, make it premium". Everything
// asserted here is something a PDF viewer structurally could not do, because
// `flutter_pdfview` renders page IMAGES and exposes no text layer:
//
//   * real reading grounds (Day / Sepia / Night) rather than an inverted scan;
//   * the printed page number as a quiet marginal mark instead of "[18]"
//     sitting inside the sentence;
//   * scripture rendered as a link, using the reference the EPUB already
//     tagged;
//   * a quote card that cites the CANONICAL page.
//
// Reading grounds are asserted by CONTRAST, not by exact colour, so the
// palettes can be retuned without the tests becoming a colour changelog.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/egw_book_model.dart';
import 'package:advent_connect_zw/screens/library/egw_reader_screen.dart';
import 'package:advent_connect_zw/services/egw_reader_prefs.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

/// WCAG relative-contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

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
            EgwSpan(text: 'He held communion with Him '),
            EgwSpan(text: 'Colossians 2:3', scriptureRef: 'Colossians 2:3'),
            EgwSpan(text: '. His motives would be alien to '),
            EgwSpan(text: '', page: 18),
            EgwSpan(text: 'those that actuate the sinless dwellers.'),
          ],
        ),
      ],
    ),
    EgwChapter(
      id: 'content03',
      title: 'Chapter 3—Repentance',
      blocks: [
        EgwBlock(
          kind: EgwBlockKind.paragraph,
          spans: [EgwSpan(text: 'How shall a man be just with God?')],
        ),
      ],
    ),
  ],
);

Widget _host({required bool dark}) => MaterialApp(
  theme: AppTheme.light,
  darkTheme: AppTheme.dark,
  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
  home: EgwReaderScreen(book: _book(), bookId: 'test-book'),
);

void main() {
  group('reading grounds', () {
    test('every ground is comfortably readable', () {
      for (final theme in EgwReadingTheme.values) {
        final p = EgwReadingPalette.of(theme);
        expect(
          _contrast(p.text, p.page),
          greaterThan(7.0),
          reason: '${theme.name} body text fails AAA on its own page',
        );
        expect(
          _contrast(p.muted, p.page),
          greaterThan(3.0),
          reason: '${theme.name} muted text is too faint',
        );
        expect(
          _contrast(p.accent, p.page),
          greaterThan(3.0),
          reason: '${theme.name} scripture links are too faint to read',
        );
      }
    });

    test('no ground uses pure black or pure white paper', () {
      // Pure values are what make long reading tiring; this is the whole
      // difference between a reading ground and a background colour.
      for (final theme in EgwReadingTheme.values) {
        final page = EgwReadingPalette.of(theme).page;
        expect(page, isNot(const Color(0xFFFFFFFF)), reason: theme.name);
        expect(page, isNot(const Color(0xFF000000)), reason: theme.name);
      }
    });

    test('sepia is genuinely warm, not day with a tint', () {
      final sepia = EgwReadingPalette.sepia.page;
      final day = EgwReadingPalette.day.page;
      expect(sepia.r, greaterThan(sepia.b), reason: 'sepia must be warm');
      expect(
        (sepia.r - sepia.b).abs(),
        greaterThan((day.r - day.b).abs()),
        reason: 'sepia must be warmer than day, or it is pointless',
      );
    });
  });

  group('first open follows the app', () {
    testWidgets('a dark app opens the reader on the night ground',
        (t) async {
      // "Dark mode doesn't work in EGW" was exactly this: a blazing white
      // page inside a dark app. An untouched preference must follow the app.
      await t.pumpWidget(_host(dark: true));
      await t.pump();

      final scaffold = t.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, EgwReadingPalette.night.page);
    });

    testWidgets('a light app opens on the day ground', (t) async {
      await t.pumpWidget(_host(dark: false));
      await t.pump();

      final scaffold = t.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, EgwReadingPalette.day.page);
    });
  });

  group('the page stops feeling like a PDF', () {
    testWidgets('renders the chapter body', (t) async {
      await t.pumpWidget(_host(dark: false));
      await t.pump();

      expect(find.textContaining('sinless dwellers'), findsWidgets);
      expect(t.takeException(), isNull);
    });

    testWidgets('the printed page number is a mark, not "[18]" in the text',
        (t) async {
      await t.pumpWidget(_host(dark: false));
      await t.pump();

      // The number survives — it is what makes a quote citable...
      expect(find.text('18'), findsOneWidget);
      // ...but the bracketed print artefact never appears in the prose.
      final texts = t
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .join(' ');
      expect(texts, isNot(contains('[18]')));
    });

    testWidgets('chapter navigation moves and persists nothing surprising',
        (t) async {
      await t.pumpWidget(_host(dark: false));
      await t.pump();

      expect(find.textContaining('sinless dwellers'), findsWidgets);
      await t.tap(find.byIcon(Icons.chevron_right_rounded));
      await t.pumpAndSettle();

      expect(find.textContaining('just with God'), findsWidgets);
      expect(t.takeException(), isNull);
    });

    testWidgets('tapping the MIDDLE toggles the chrome away', (t) async {
      await t.pumpWidget(_host(dark: false));
      await t.pump();
      expect(find.byIcon(Icons.list_rounded), findsOneWidget);

      // Chrome hiding is most of what separates a reader from a viewer.
      // The middle, specifically: the outer thirds turn pages.
      final size = t.view.physicalSize / t.view.devicePixelRatio;
      await t.tapAt(Offset(size.width / 2, size.height / 2));
      await t.pumpAndSettle();

      expect(find.byIcon(Icons.list_rounded), findsNothing);
    });
  });

  // "Like an actual book" (founder, 17 Aug). The reader paginates and turns
  // pages rather than scrolling; a scrolling column is the thing that makes
  // long-form reading feel like a web page.
  group('turning pages', () {
    testWidgets('the chapter is cut into pages, not one scroll', (t) async {
      await t.pumpWidget(_host(dark: false));
      await t.pump();

      expect(find.byType(PageView), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('tapping the right edge turns forward', (t) async {
      await t.pumpWidget(_host(dark: false));
      await t.pumpAndSettle();

      final size = t.view.physicalSize / t.view.devicePixelRatio;
      final pager = t.widget<PageView>(find.byType(PageView)).controller!;
      expect(pager.page?.round(), 0);

      await t.tapAt(Offset(size.width * 0.9, size.height / 2));
      await t.pumpAndSettle();

      expect(pager.page?.round(), 1);
    });

    testWidgets('tapping the left edge turns back', (t) async {
      await t.pumpWidget(_host(dark: false));
      await t.pumpAndSettle();

      final size = t.view.physicalSize / t.view.devicePixelRatio;
      final pager = t.widget<PageView>(find.byType(PageView)).controller!;

      await t.tapAt(Offset(size.width * 0.9, size.height / 2));
      await t.pumpAndSettle();
      expect(pager.page?.round(), 1);

      await t.tapAt(Offset(size.width * 0.1, size.height / 2));
      await t.pumpAndSettle();
      expect(pager.page?.round(), 0);
    });

    testWidgets('swiping turns too', (t) async {
      await t.pumpWidget(_host(dark: false));
      await t.pumpAndSettle();

      final pager = t.widget<PageView>(find.byType(PageView)).controller!;
      await t.fling(find.byType(PageView), const Offset(-300, 0), 1000);
      await t.pumpAndSettle();

      expect(pager.page?.round(), greaterThan(0));
    });

    testWidgets('a viewport change re-measures without overflowing',
        (t) async {
      // Pagination is measured against a viewport AND a type size. If the
      // measurer and the renderer drift, the page overflows — which is
      // deliberately left visible rather than cushioned, so it shows up
      // here rather than in somebody's book.
      //
      // Both sizes are real phones. physicalSize must be set WITH a
      // devicePixelRatio: setting it alone leaves the default ratio and
      // yields a 200x300 logical screen, which no device has and which
      // nothing can be laid out for.
      t.view.devicePixelRatio = 3.0;
      t.view.physicalSize = const Size(1170, 2532); // iPhone 13
      addTearDown(t.view.reset);

      await t.pumpWidget(_host(dark: false));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);

      t.view.physicalSize = const Size(1080, 1920); // smaller Android
      await t.pumpAndSettle();

      expect(t.takeException(), isNull);
      expect(find.byType(PageView), findsOneWidget);
    });
  });

  group('contents', () {
    testWidgets('lists chapters with their printed start page', (t) async {
      await t.pumpWidget(_host(dark: false));
      await t.pump();

      await t.tap(find.byIcon(Icons.list_rounded));
      await t.pumpAndSettle();

      expect(find.text('Chapter 3—Repentance'), findsOneWidget);
      // The citation anchor, surfaced where a reader picks a chapter.
      expect(find.text('p. 18'), findsOneWidget);
    });
  });
}
