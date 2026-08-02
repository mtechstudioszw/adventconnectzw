// Announcement reactions: the optimistic tap, and the bar that shows it.
//
// The backend shipped on 2 Aug 2026 and was verified against production;
// this is the UI half. The part worth testing is the local prediction:
// the bar fills the instant you tap, and `set_announcement_reaction`
// answers a round trip later. If the two disagree the count visibly jumps
// under the member's thumb, so `afterTapping` has to mirror the RPC's
// rules exactly — including that tapping the face you already left CLEARS
// it rather than setting it again.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/church_service.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/announcement_reaction_bar.dart';

AnnouncementReactionState _state(
  Map<AnnouncementReaction, int> counts, {
  AnnouncementReaction? mine,
}) =>
    AnnouncementReactionState(counts: counts, mine: mine);

void main() {
  group('afterTapping mirrors set_announcement_reaction', () {
    test('a first reaction adds one and becomes mine', () {
      final next = _state({}).afterTapping(AnnouncementReaction.amen);

      expect(next.mine, AnnouncementReaction.amen);
      expect(next.counts[AnnouncementReaction.amen], 1);
      expect(next.total, 1);
    });

    test('tapping my own reaction clears it', () {
      final before = _state(
        {AnnouncementReaction.amen: 3},
        mine: AnnouncementReaction.amen,
      );

      final next = before.afterTapping(AnnouncementReaction.amen);

      expect(next.mine, isNull);
      expect(next.counts[AnnouncementReaction.amen], 2);
      expect(next.total, 2);
    });

    test('clearing the last one drops the key rather than leaving a zero',
        () {
      final before =
          _state({AnnouncementReaction.love: 1}, mine: AnnouncementReaction.love);

      final next = before.afterTapping(AnnouncementReaction.love);

      // A lingering `love: 0` would render an empty chip with a 0 on it.
      expect(next.counts.containsKey(AnnouncementReaction.love), isFalse);
      expect(next.total, 0);
    });

    test('switching reactions moves the count, it does not double-count', () {
      final before = _state(
        {AnnouncementReaction.amen: 2, AnnouncementReaction.pray: 5},
        mine: AnnouncementReaction.amen,
      );

      final next = before.afterTapping(AnnouncementReaction.pray);

      expect(next.mine, AnnouncementReaction.pray);
      expect(next.counts[AnnouncementReaction.amen], 1);
      expect(next.counts[AnnouncementReaction.pray], 6);
      expect(next.total, 7);
    });

    test('reacting to other people\'s reactions leaves theirs alone', () {
      final before = _state({AnnouncementReaction.praise: 4});

      final next = before.afterTapping(AnnouncementReaction.praise);

      expect(next.mine, AnnouncementReaction.praise);
      expect(next.counts[AnnouncementReaction.praise], 5);
    });

    test('the round trip is stable: tap and untap returns the start', () {
      final before = _state(
        {AnnouncementReaction.amen: 2, AnnouncementReaction.love: 1},
      );

      final next = before
          .afterTapping(AnnouncementReaction.love)
          .afterTapping(AnnouncementReaction.love);

      expect(next.mine, isNull);
      expect(next.counts[AnnouncementReaction.amen], 2);
      expect(next.counts[AnnouncementReaction.love], 1);
    });
  });

  group('AnnouncementReactionState.fromJson', () {
    test('drops zero counts and unknown reactions', () {
      final state = AnnouncementReactionState.fromJson({
        'counts': {'amen': 3, 'praise': 0, 'shout': 9},
        'mine': 'amen',
      });

      expect(state.counts[AnnouncementReaction.amen], 3);
      expect(state.counts.containsKey(AnnouncementReaction.praise), isFalse);
      // A reaction added to the DB after this build shipped must not crash
      // the list.
      expect(state.total, 3);
      expect(state.mine, AnnouncementReaction.amen);
    });

    test('an absent mine means the member has not reacted', () {
      final state = AnnouncementReactionState.fromJson({
        'counts': {'amen': 1},
      });

      expect(state.mine, isNull);
    });
  });

  group('AnnouncementReactionBar', () {
    Future<void> pump(
      WidgetTester t,
      AnnouncementReactionState state, {
      ValueChanged<AnnouncementReaction>? onReact,
      double textScale = 1.0,
    }) async {
      t.view.physicalSize = const Size(360, 720);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: AnnouncementReactionBar(
                state: state,
                onReact: onReact ?? (_) {},
              ),
            ),
          ),
        ),
      ));
      await t.pump(const Duration(milliseconds: 400));
    }

    testWidgets('shows every face, and counts only where there are some',
        (t) async {
      await pump(t, _state({AnnouncementReaction.amen: 2}));

      for (final kind in AnnouncementReaction.values) {
        expect(find.text(kind.emoji), findsOneWidget);
      }
      expect(find.text('2'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('the tally appears only once someone has responded',
        (t) async {
      await pump(t, _state({}));
      expect(find.textContaining('response'), findsNothing);

      await pump(t, _state({AnnouncementReaction.amen: 1}));
      expect(find.text('1 response'), findsOneWidget);

      await pump(t, _state(
        {AnnouncementReaction.amen: 1, AnnouncementReaction.love: 2},
      ));
      expect(find.text('3 responses'), findsOneWidget);
    });

    testWidgets('tapping a face reports which one', (t) async {
      final taps = <AnnouncementReaction>[];
      await pump(t, _state({}), onReact: taps.add);

      await t.tap(find.text(AnnouncementReaction.pray.emoji));
      await t.pump();

      expect(taps, [AnnouncementReaction.pray]);
    });

    for (final scale in <double>[1.0, 1.6, 2.5]) {
      testWidgets('lays out at ${scale}x text scale', (t) async {
        await pump(
          t,
          _state(
            {
              AnnouncementReaction.amen: 12,
              AnnouncementReaction.praise: 8,
              AnnouncementReaction.pray: 30,
              AnnouncementReaction.love: 5,
            },
            mine: AnnouncementReaction.pray,
          ),
          textScale: scale,
        );

        expect(t.takeException(), isNull);
      });
    }
  });
}
