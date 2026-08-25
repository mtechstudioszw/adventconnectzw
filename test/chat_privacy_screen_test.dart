// Chat privacy: the redesign, and the setting the founder asked for.
//
// "Who can message me" is three mutually exclusive options each carrying
// two or three lines of explanatory text — by some distance the most
// wrappable text on any settings screen in the app, and fixed-height rows
// next to scaling text are this project's most repeated overflow source.
// So it gets the 1.0x / 1.6x / 2.5x sweep on a 360dp phone.
//
// "Who can call me" is the same three labels again, one card below. Every
// finder here is therefore scoped to a card by key: a bare
// find.text('Everyone') matches both sections and reports "too many",
// which is precisely how this file broke when calling was added.
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

/// The messaging option card. Scoping to it keeps the identical labels in
/// the calling card from doubling every match.
final _messageCard = find.byKey(const ValueKey('who-can-message-card'));
final _callCard = find.byKey(const ValueKey('who-can-call-card'));

Finder _inCard(Finder card, Finder matching) =>
    find.descendant(of: card, matching: matching);

void main() {
  testWidgets('offers all three message settings and every section',
      (t) async {
    await _pump(t);

    for (final option in const ['Everyone', 'Friends only', 'Nobody']) {
      expect(_inCard(_messageCard, find.text(option)), findsOneWidget);
      expect(_inCard(_callCard, find.text(option)), findsOneWidget);
    }

    // Two option cards now sit above the visibility toggles, so these
    // start below the fold on a 360x720 phone and the ListView has not
    // built them yet. Scroll down to each in turn — they are in this
    // order on screen, so one downward sweep reaches all three.
    for (final toggle in const ['Last seen', 'Online status', 'Read receipts']) {
      await t.scrollUntilVisible(find.text(toggle), 120);
      expect(find.text(toggle), findsOneWidget);
    }
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

    // Messaging defaults to everyone, so exactly one filled radio.
    expect(_inCard(_messageCard, find.byIcon(Icons.radio_button_checked)),
        findsOneWidget);
    expect(_inCard(_messageCard, find.byIcon(Icons.radio_button_unchecked)),
        findsNWidgets(2));
  });

  testWidgets('exactly one call option is selected at a time', (t) async {
    await _pump(t);

    // Calling starts at 'friends' — tighter than messaging, because a
    // ringing phone interrupts harder than an unread badge.
    expect(_inCard(_callCard, find.byIcon(Icons.radio_button_checked)),
        findsOneWidget);
    expect(_inCard(_callCard, find.byIcon(Icons.radio_button_unchecked)),
        findsNWidgets(2));
    expect(
      _inCard(_callCard, find.textContaining('This is the default')),
      findsOneWidget,
    );
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
      final everyone = _inCard(_messageCard, find.text('Everyone'));
      await t.scrollUntilVisible(everyone, 120);
      expect(everyone, findsOneWidget);
      expect(t.takeException(), isNull);

      // The calling card sits below the messaging one, so reaching it
      // exercises the far end of the scroll extent at every scale.
      final calling = _inCard(_callCard, find.text('Nobody'));
      await t.scrollUntilVisible(calling, 120);
      expect(calling, findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
