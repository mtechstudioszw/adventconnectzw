// The brief's rule (§9) is that a member must never see raw Markdown.
// `**forgiveness**` on screen is worse than no bold at all — it looks
// broken, and in an app people trust for Scripture, looking broken is
// expensive.
//
// These are rendering tests, not parser tests: they assert what ends up
// in front of a member. The renderer is hand-written precisely so it can
// degrade unsupported syntax to plain text rather than leaking symbols,
// and that behaviour is what is pinned here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/advent_ai/widgets/ai_markdown.dart';

/// Every character actually painted, flattened across all Text and
/// RichText widgets in the tree.
String rendered(WidgetTester tester) {
  final buffer = StringBuffer();
  for (final w in tester.widgetList(find.byType(RichText))) {
    buffer.write((w as RichText).text.toPlainText());
  }
  for (final w in tester.widgetList(find.byType(Text))) {
    final t = (w as Text).data;
    if (t != null) buffer.write(t);
  }
  return buffer.toString();
}

Future<void> pump(WidgetTester tester, String markdown,
    {void Function(String)? onVerseTap}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: AiMarkdown(text: markdown, onVerseTap: onVerseTap),
      ),
    ),
  ));
}

void main() {
  group('no raw syntax reaches the member', () {
    testWidgets('bold markers are consumed', (tester) async {
      await pump(tester, 'God is **faithful** always.');
      final out = rendered(tester);
      expect(out, contains('faithful'));
      expect(out, isNot(contains('**')));
    });

    testWidgets('italic markers are consumed', (tester) async {
      await pump(tester, 'This is *grace* indeed.');
      final out = rendered(tester);
      expect(out, contains('grace'));
      // A lone asterisk is the giveaway that parsing failed.
      expect(out, isNot(contains('*')));
    });

    testWidgets('heading hashes are consumed', (tester) async {
      await pump(tester, '## The Sabbath\n\nIt was made for people.');
      final out = rendered(tester);
      expect(out, contains('The Sabbath'));
      expect(out, isNot(contains('#')));
    });

    testWidgets('bullet markers become real bullets', (tester) async {
      await pump(tester, '- pray\n- study\n- rest');
      final out = rendered(tester);
      expect(out, contains('pray'));
      expect(out, contains('study'));
      // The hyphen is replaced by a bullet glyph, not left in the text.
      expect(out, isNot(contains('- pray')));
    });

    testWidgets('numbered lists keep their numbers', (tester) async {
      await pump(tester, '1. first\n2. second');
      final out = rendered(tester);
      expect(out, contains('first'));
      expect(out, contains('second'));
      expect(out, contains('1.'));
    });

    testWidgets('block quotes lose the angle bracket', (tester) async {
      await pump(tester, '> For God so loved the world.');
      final out = rendered(tester);
      expect(out, contains('For God so loved the world.'));
      expect(out, isNot(contains('>')));
    });

    testWidgets('inline code loses its backticks', (tester) async {
      await pump(tester, 'Open `Settings` to change it.');
      final out = rendered(tester);
      expect(out, contains('Settings'));
      expect(out, isNot(contains('`')));
    });
  });

  group('content survives intact', () {
    testWidgets('a plain paragraph renders verbatim', (tester) async {
      const text = 'Jesus wept.';
      await pump(tester, text);
      expect(rendered(tester), contains(text));
    });

    testWidgets('a mixed answer keeps every part', (tester) async {
      await pump(tester, '''
## Forgiveness

The Bible teaches that we **forgive** because we were forgiven.

- Matthew 6:14
- Colossians 3:13

> Be ye kind one to another.
''');
      final out = rendered(tester);
      for (final fragment in [
        'Forgiveness',
        'forgive',
        'Matthew 6:14',
        'Colossians 3:13',
        'Be ye kind one to another.',
      ]) {
        expect(out, contains(fragment), reason: 'lost "$fragment"');
      }
      expect(out, isNot(contains('**')));
      expect(out, isNot(contains('##')));
    });

    testWidgets('empty text does not throw', (tester) async {
      await pump(tester, '');
      expect(tester.takeException(), isNull);
    });

    testWidgets('whitespace-only text does not throw', (tester) async {
      await pump(tester, '   \n\n   ');
      expect(tester.takeException(), isNull);
    });
  });

  group('scripture references', () {
    testWidgets('a reference is tappable when a handler is given',
        (tester) async {
      final tapped = <String>[];
      await pump(tester, 'See John 3:16 for this.',
          onVerseTap: tapped.add);

      // The reference is styled as a link; tapping the text should fire.
      final rich = tester.widget<RichText>(find.byType(RichText).first);
      final spans = <InlineSpan>[];
      rich.text.visitChildren((s) {
        spans.add(s);
        return true;
      });
      final hasRecognizer = spans.any(
          (s) => s is TextSpan && s.recognizer != null);
      expect(hasRecognizer, isTrue,
          reason: 'John 3:16 should be tappable');
    });

    testWidgets('no recognizer is attached when tapping is disabled',
        (tester) async {
      await pump(tester, 'See John 3:16 for this.');
      final rich = tester.widget<RichText>(find.byType(RichText).first);
      final spans = <InlineSpan>[];
      rich.text.visitChildren((s) {
        spans.add(s);
        return true;
      });
      expect(
        spans.any((s) => s is TextSpan && s.recognizer != null),
        isFalse,
      );
    });
  });

  group('streaming', () {
    testWidgets('a partial answer renders without throwing', (tester) async {
      // Mid-stream text is arbitrarily truncated — half a bold marker,
      // an unclosed heading, a dangling backtick. None may crash the
      // transcript, because this rebuilds on every chunk.
      for (final partial in [
        '**forgive',
        '## The Sab',
        'Open `Sett',
        '> For God so',
        '- pray\n- stu',
        '*',
        '#',
        '`',
        '>',
      ]) {
        await pump(tester, partial);
        expect(tester.takeException(), isNull,
            reason: 'crashed on partial "$partial"');
      }
    });

    testWidgets('rebuilding many times does not throw', (tester) async {
      // The real streaming case: one widget, growing text, many rebuilds.
      // This is what leaked TapGestureRecognizers before they were
      // cached and disposed.
      const full = 'Read John 3:16 and Romans 8:28 carefully.';
      for (var i = 1; i <= full.length; i += 3) {
        await pump(tester, full.substring(0, i), onVerseTap: (_) {});
      }
      expect(tester.takeException(), isNull);
      expect(rendered(tester), contains('Romans 8:28'));
    });
  });
}
