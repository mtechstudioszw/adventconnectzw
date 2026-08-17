// Founder, 18 Aug 2026: *"now its lying tt people are onlive for live
// match"*.
//
// He was right, and it was three separate faults stacked on one line:
//
//  1. **It counted the person reading it.** The presence channel is
//     created with `self: true`, so you are always in your own roster. The
//     lobby's copy of this said "1 online now" to someone sitting alone.
//  2. **The number was app-wide, not arena-wide.** `online_users` is the
//     whole app's presence channel, so it counts members reading the news
//     feed or in a chat. Saying "play someone" promised a queued opponent
//     that nothing in the app had any way to know about — members tapped,
//     searched, found nobody, and concluded live match was broken.
//  3. **The lobby's copy never updated**, because it read the roster once
//     at build time with nothing listening.
//
// A truthful "N waiting in the arena" needs a server-side count of open
// queue entries, which is still to do. Until then the strip may only
// promise what it can keep: those members are reachable, so it offers a
// challenge.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/presence_service.dart';
import 'package:advent_connect_zw/services/quiz_home_signal.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/home/quiz_live_strip.dart';

const _me = 'me-user-id';

Future<void> _pump(
  WidgetTester t, {
  required Set<String> online,
  int invites = 0,
  double textScale = 1.0,
}) async {
  QuizHomeSignal.invites.value = invites;
  PresenceService.debugSetRoster(online);
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(360, 780),
        textScaler: TextScaler.linear(textScale),
      ),
      child: const Scaffold(
        body: SingleChildScrollView(child: QuizLiveStrip(viewerId: _me)),
      ),
    ),
  ));
  await t.pump();
}

void main() {
  tearDown(() {
    PresenceService.debugSetRoster(const {});
    QuizHomeSignal.invites.value = 0;
  });

  testWidgets('alone in the app, the strip says nothing at all', (t) async {
    // The exact complaint: you are the only one there and it claims
    // somebody is around to play.
    await _pump(t, online: {_me});

    expect(t.getSize(find.byType(QuizLiveStrip)), Size.zero);
  });

  testWidgets('an empty roster says nothing either', (t) async {
    await _pump(t, online: const {});
    expect(t.getSize(find.byType(QuizLiveStrip)), Size.zero);
  });

  testWidgets('one other member is counted as one, not two', (t) async {
    await _pump(t, online: {_me, 'someone-else'});

    expect(find.textContaining('1 member in the app'), findsOneWidget);
  });

  testWidgets('a member who hid their online status is not miscounted',
      (t) async {
    // They never join the roster at all, so the old `length - 1` was one
    // short for them. Filtering by id is correct either way.
    await _pump(t, online: {'a', 'b'});

    expect(find.textContaining('2 members in the app'), findsOneWidget);
  });

  testWidgets('it never promises an opponent is queued and waiting',
      (t) async {
    await _pump(t, online: {_me, 'a', 'b'});

    expect(find.textContaining('play someone'), findsNothing,
        reason: 'this number cannot know whether anyone is in the arena');
    expect(find.textContaining('challenge'), findsOneWidget);
  });

  testWidgets('an actual invite outranks the online count', (t) async {
    // Somebody really did challenge you — that IS a queued opponent, and
    // it is the one case the strip may be emphatic about.
    await _pump(t, online: {_me}, invites: 1);

    expect(find.text('Someone wants to play'), findsOneWidget);
    expect(t.getSize(find.byType(QuizLiveStrip)).height, greaterThan(0),
        reason: 'an invite shows even when nobody else is online');
  });

  for (final scale in const [1.6, 2.5]) {
    testWidgets('lays out at ${scale}x text scale', (t) async {
      await _pump(t, online: {_me, 'a', 'b'}, textScale: scale);
      expect(t.takeException(), isNull);
    });
  }
}
