// Chat privacy: the redesign, and the setting the founder asked for.
//
// "Who can message me" is three mutually exclusive options each carrying
// two or three lines of explanatory text — by some distance the most
// wrappable text on any settings screen in the app, and fixed-height rows
// next to scaling text are this project's most repeated overflow source.
// So it gets the 1.0x / 1.6x / 2.5x sweep on a 360dp phone.
//
// "Who can follow me" uses the same three labels in its own card, so every
// finder here is scoped to a card by key: a bare find.text('Everyone')
// would match both. ("Who can call me" was removed 29 Oct 2026 — the app
// has no calls.)
//
// The Save button is gone: each control writes on change. A member who
// flipped "Online status" off and walked away used to keep broadcasting.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/messaging/chat_privacy_screen.dart';
import 'package:advent_connect_zw/services/follow_service.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

Future<void> _pump(WidgetTester t, {double textScale = 1.0}) async {
  t.view.physicalSize = const Size(360, 720);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: const ChatPrivacyScreen(autoLoad: false),
      ),
    ),
  );
  await t.pump();
}

/// The messaging option card. Scoping to it keeps the identical labels in
/// the follow card from doubling every match.
final _messageCard = find.byKey(const ValueKey('who-can-message-card'));

Finder _inCard(Finder card, Finder matching) =>
    find.descendant(of: card, matching: matching);

void main() {
  testWidgets('offers all three message settings and every section', (t) async {
    await _pump(t);

    // The friends-vs-followers card now sits first, so scroll to each
    // option card before reading it.
    await t.scrollUntilVisible(_messageCard, 120);
    for (final option in const ['Everyone', 'Friends only', 'Nobody']) {
      expect(_inCard(_messageCard, find.text(option)), findsOneWidget);
    }
    // No calling feature exists, so no calls setting either.
    expect(find.text('Who can call me'.toUpperCase()), findsNothing);

    // The option cards sit above the visibility toggles, so these
    // start below the fold on a 360x720 phone and the ListView has not
    // built them yet. Scroll down to each in turn — they are in this
    // order on screen, so one downward sweep reaches all three.
    for (final toggle in const [
      'Last seen',
      'Online status',
      'Read receipts',
    ]) {
      await t.scrollUntilVisible(find.text(toggle), 120);
      expect(find.text(toggle), findsOneWidget);
    }
  });

  testWidgets('the one-message rule is stated on the option itself', (t) async {
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
    expect(
      _inCard(_messageCard, find.byIcon(Icons.radio_button_checked)),
      findsOneWidget,
    );
    expect(
      _inCard(_messageCard, find.byIcon(Icons.radio_button_unchecked)),
      findsNWidgets(2),
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

      // The last toggle is the far end of the scroll extent at every scale.
      final last = find.text('Read receipts');
      await t.scrollUntilVisible(last, 120);
      expect(last, findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  group('Privacy: following beside messaging (28 Oct 2026)', () {
    Future<void> pumpWithFollow(WidgetTester t) async {
      t.view.physicalSize = const Size(360, 720);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const ChatPrivacyScreen(
            autoLoad: false,
            initialWhoCanFollow: WhoCanFollow.nobody,
          ),
        ),
      );
      await t.pump();
    }

    final followCard = find.byKey(const ValueKey('allow-followers-card'));

    testWidgets('states how friends and followers differ', (t) async {
      await pumpWithFollow(t);
      final card = find.byKey(const ValueKey('friends-vs-followers'));
      expect(card, findsOneWidget);
      expect(_inCard(card, find.text('Friends')), findsOneWidget);
      expect(_inCard(card, find.text('Followers')), findsOneWidget);
      expect(
        _inCard(card, find.textContaining('never lets them message')),
        findsOneWidget,
      );
      // It must never read as if you can't follow someone back.
      expect(
        _inCard(card, find.textContaining('can follow back')),
        findsOneWidget,
      );
    });

    testWidgets('followers: one switch, off by default (patch_287)', (t) async {
      await pumpWithFollow(t);
      await t.scrollUntilVisible(followCard, 120);
      expect(_inCard(followCard, find.text('Allow followers')), findsOneWidget);
      final sw = t.widget<SwitchListTile>(
        find.descendant(of: followCard, matching: find.byType(SwitchListTile)),
      );
      expect(sw.value, isFalse);
      expect(
        _inCard(followCard, find.textContaining('Personal account')),
        findsOneWidget,
      );
      expect(
        _inCard(followCard, find.textContaining('Off by default')),
        findsOneWidget,
      );
      // No three-way choice any more.
      expect(_inCard(followCard, find.text('Friends only')), findsNothing);
    });

    testWidgets('no follow section before patch_282 answers', (t) async {
      await _pump(t);
      expect(followCard, findsNothing);
    });
  });
}
