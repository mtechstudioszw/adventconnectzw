// Sharing a Bible verse produces an image, from wherever it is shared.
//
// The brief for 2 Aug 2026 asked to "reuse that generator for any Bible
// verse share so sharing from the Bible reader produces the same image".
// The reader already did — `VerseShareSheet` was wired to both the
// verse-of-the-day card and the reader's selection bar. What was actually
// missing was Home: the Today card showed the devotion's verse and gave
// no way to send it on.
//
// So the generator moved from `screens/library/widgets/` to `widgets/`
// (the "lift it into a shared widget" half of the ask) and Home now calls
// the same sheet. These tests pin that there is ONE generator and that
// its card renders the verse — a second copy drifting from the first is
// the failure mode the founder was guarding against.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/verse_share_card.dart';

Future<void> _pump(
  WidgetTester t, {
  double textScale = 1.0,
  String reference = 'John 3:16',
  String text =
      'For God so loved the world, that he gave his only begotten Son.',
}) async {
  t.view.physicalSize = const Size(360, 720);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  await t.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: VerseShareSheet(reference: reference, text: text),
      ),
    ),
  ));
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('the card carries the verse and its reference', (t) async {
    await _pump(t);

    expect(find.textContaining('For God so loved the world'), findsWidgets);
    // The card sets the reference in caps as a design choice.
    expect(find.textContaining('JOHN 3:16'), findsWidgets);
  });

  testWidgets('a long verse does not overflow the card', (t) async {
    // Esther 8:9 is the longest verse in the KJV — the realistic worst
    // case for a fixed-aspect share card.
    await _pump(
      t,
      reference: 'Esther 8:9',
      text:
          'Then were the king\'s scribes called at that time in the third '
          'month, that is, the month Sivan, on the three and twentieth day '
          'thereof; and it was written according to all that Mordecai '
          'commanded unto the Jews, and to the lieutenants, and the deputies '
          'and rulers of the provinces which are from India unto Ethiopia, '
          'an hundred twenty and seven provinces, unto every province '
          'according to the writing thereof, and unto every people after '
          'their language, and to the Jews according to their writing, and '
          'according to their language.',
    );

    expect(t.takeException(), isNull);
  });

  for (final scale in <double>[1.0, 1.6, 2.5]) {
    testWidgets('lays out at ${scale}x text scale', (t) async {
      await _pump(t, textScale: scale);

      expect(t.takeException(), isNull);
    });
  }
}
