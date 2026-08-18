// Chat privacy: the redesign, and the setting the founder asked for.
//
// "Who can message me" is three mutually exclusive options each carrying
// two or three lines of explanatory text — by some distance the most
// wrappable text on any settings screen in the app, and fixed-height rows
// next to scaling text are this project's most repeated overflow source.
// So it gets the 1.0x / 1.6x / 2.5x sweep on a 360dp phone.
//
// The Save button is gone: each control writes on change. A member who
// flipped "Online status" off and walked away used to keep broadcasting.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/messaging/chat_privacy_screen.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

Future<void> _pump(WidgetTester t, {double textScale = 1.0}) async {
  t.view.physicalSize = const Size(360, 720);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  await t.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: const ChatPrivacyScreen(autoLoad: false),
    ),
  ));
  await t.pump();
}

void main() {
  testWidgets('offers all three message settings and both sections',
      (t) async {
    await _pump(t);

    expect(find.text('Everyone'), findsOneWidget);
    expect(find.text('Friends only'), findsOneWidget);
    expect(find.text('Nobody'), findsOneWidget);

    expect(find.text('Last seen'), findsOneWidget);
    expect(find.text('Online status'), findsOneWidget);
    expect(find.text('Read receipts'), findsOneWidget);
  });

  testWidgets('the one-message rule is stated on the option itself',
      (t) async {
    await _pump(t);

    // A member picking "Everyone" should be able to see exactly how much a
    // stranger gets, without opening help.
    expect(find.textContaining('one message'), findsOneWidget);
  });

  testWidgets('there is no Save button left to forget', (t) async {
    await _pump(t);

    expect(find.text('Save changes'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('exactly one message option is selected at a time', (t) async {
    await _pump(t);

    // Defaults to everyone, so exactly one filled radio.
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(2));
  });

  for (final scale in <double>[1.0, 1.6, 2.5]) {
    testWidgets('lays out at ${scale}x text scale', (t) async {
      await _pump(t, textScale: scale);

      expect(t.takeException(), isNull);
      // Scroll to the option rather than assuming it starts on screen.
      // At 2.5x on a 360dp phone the scope note and section label push it
      // past the fold, and a ListView does not build what it does not
      // show — so a bare find.text would report "missing" for something
      // that is merely below. The overflow sweep is what this test is
      // for, and it is asserted on both sides of the scroll.
      await t.scrollUntilVisible(find.text('Everyone'), 120);
      expect(find.text('Everyone'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
