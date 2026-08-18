// Founder, 18 Aug 2026: *"the quiz live banner is lying tt some people
// online to play quiz live when one will be in the lobby"*.
//
// This is the third pass at the same complaint, and the first one that
// changes the SIGNAL rather than the wording. The earlier faults were real
// and are all fixed:
//
//  1. **It counted the person reading it.** The presence channel is created
//     with `self: true`, so you are always in your own roster — the lobby
//     said "1 online now" to somebody sitting alone.
//  2. **The lobby's copy never updated**, because it read the roster once at
//     build time with nothing listening.
//  3. **The number was app-wide, not arena-wide.**
//
// Fixing 1 and 2 made the strip an accurate count of people who are NOT
// playing — members reading the feed, in a chat, watching a video. Softening
// the copy to "in the app · challenge one" was tried twice and did not help,
// because a green live-match strip that appears BECAUSE people are around
// reads as "there is a game here", and then the arena is empty.
//
// So the number is now the live-match queue itself — `quiz_arena_waiting()`,
// patch_212, the same rows `quiz_match_find` would pair you with. What these
// tests hold is that presence can never creep back in: the strip must be
// silent when nobody is queued, however many people have the app open.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/presence_service.dart';
import 'package:advent_connect_zw/services/quiz_home_signal.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/home/quiz_live_strip.dart';

const _me = 'me-user-id';

Future<void> _pump(
  WidgetTester t, {
  int waiting = 0,
  int invites = 0,
  Set<String> online = const {},
  double textScale = 1.0,
}) async {
  QuizHomeSignal.invites.value = invites;
  QuizHomeSignal.waiting.value = waiting;
  // Set even though the strip must ignore it — a roster full of people is
  // precisely the condition under which the old strip lied.
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
    QuizHomeSignal.waiting.value = 0;
  });

  testWidgets('a busy app with an empty arena says NOTHING', (t) async {
    // The complaint, exactly. Five members are using the app; not one of
    // them is in the live-match queue. The strip must not appear.
    await _pump(t, online: {_me, 'a', 'b', 'c', 'd'});

    expect(t.getSize(find.byType(QuizLiveStrip)), Size.zero);
  });

  testWidgets('alone in the app, the strip says nothing at all', (t) async {
    await _pump(t, online: {_me});
    expect(t.getSize(find.byType(QuizLiveStrip)), Size.zero);
  });

  testWidgets('an empty roster says nothing either', (t) async {
    await _pump(t, online: const {});
    expect(t.getSize(find.byType(QuizLiveStrip)), Size.zero);
  });

  testWidgets('one player queued reads as one waiting in the arena',
      (t) async {
    await _pump(t, waiting: 1);

    expect(
      find.textContaining('1 player waiting in the arena'),
      findsOneWidget,
    );
  });

  testWidgets('several queued players are counted', (t) async {
    await _pump(t, waiting: 3, online: {_me});

    expect(
      find.textContaining('3 players waiting in the arena'),
      findsOneWidget,
    );
  });

  testWidgets('it never advertises members who are merely in the app',
      (t) async {
    // The wording that was wrong twice. If either of these strings comes
    // back, the strip has gone back to promising something it cannot know.
    await _pump(t, waiting: 2, online: {_me, 'a', 'b', 'c'});

    expect(find.textContaining('in the app'), findsNothing);
    expect(find.textContaining('play someone'), findsNothing);
  });

  testWidgets('an actual invite outranks the queue count', (t) async {
    // Somebody really did challenge you — the one case the strip may be
    // emphatic about, and it shows even with nobody queued.
    await _pump(t, invites: 1);

    expect(find.text('Someone wants to play'), findsOneWidget);
    expect(
      t.getSize(find.byType(QuizLiveStrip)).height,
      greaterThan(0),
      reason: 'an invite shows even when the arena is empty',
    );
  });

  for (final scale in const [1.6, 2.5]) {
    testWidgets('lays out at ${scale}x text scale', (t) async {
      await _pump(t, waiting: 3, textScale: scale);
      expect(t.takeException(), isNull);
    });
  }
}
