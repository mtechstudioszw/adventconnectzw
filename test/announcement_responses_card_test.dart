// The admin half of announcement reactions, plus the empty state of the
// screen that carries the member half.
//
// The reaction bar overflowed by 144px at 2.5x text before its own test
// caught it, and this card packs strictly more text onto one line — a
// title, four emoji-and-count pairs and a rate sentence. So it gets the
// same 1.0x / 1.6x / 2.5x sweep on a 360dp phone.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/church_model.dart';
import 'package:advent_connect_zw/screens/churches/church_announcements_screen.dart';
import 'package:advent_connect_zw/services/church_service.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/announcement_responses_card.dart';

AnnouncementReactionStat _stat({
  String title = 'Sabbath programme change',
  int readCount = 40,
  Map<AnnouncementReaction, int> counts = const {},
}) {
  return AnnouncementReactionStat(
    id: '1',
    title: title,
    category: 'general',
    createdAt: DateTime(2026, 8, 1),
    readCount: readCount,
    reactions: AnnouncementReactionState(counts: counts),
  );
}

Future<void> _pump(WidgetTester t, Widget child,
    {double textScale = 1.0}) async {
  t.view.physicalSize = const Size(360, 720);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  await t.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  ));
  await t.pump();
}

void main() {
  group('AnnouncementResponsesCard', () {
    testWidgets('totals the responses across announcements', (t) async {
      await _pump(
        t,
        AnnouncementResponsesCard(stats: [
          _stat(counts: const {AnnouncementReaction.amen: 3}),
          _stat(counts: const {
            AnnouncementReaction.love: 2,
            AnnouncementReaction.pray: 1,
          }),
        ]),
      );

      expect(find.text('6 responses'), findsOneWidget);
      expect(find.text('Last 2 announcements, newest first.'), findsOneWidget);
    });

    testWidgets('distinguishes "not opened" from "opened but silent"',
        (t) async {
      await _pump(
        t,
        AnnouncementResponsesCard(stats: [
          _stat(title: 'Unread notice', readCount: 0),
          _stat(title: 'Read but quiet', readCount: 12),
        ]),
      );

      // An admin needs to tell a delivery problem from a content problem.
      expect(find.text('Not opened yet'), findsOneWidget);
      expect(find.text('Opened, no responses'), findsOneWidget);
    });

    testWidgets('rates responses against opens, not sends', (t) async {
      await _pump(
        t,
        AnnouncementResponsesCard(stats: [
          _stat(readCount: 40, counts: const {AnnouncementReaction.amen: 10}),
        ]),
      );

      expect(find.text('25% of 40 who opened'), findsOneWidget);
    });

    testWidgets('shows newest first', (t) async {
      // The service returns oldest-first for the reach sparkline.
      await _pump(
        t,
        AnnouncementResponsesCard(stats: [
          _stat(title: 'Older', counts: const {AnnouncementReaction.amen: 1}),
          _stat(title: 'Newer', counts: const {AnnouncementReaction.amen: 1}),
        ]),
      );

      final newer = t.getTopLeft(find.text('Newer'));
      final older = t.getTopLeft(find.text('Older'));
      expect(newer.dy, lessThan(older.dy));
    });

    for (final scale in <double>[1.0, 1.6, 2.5]) {
      testWidgets('lays out at ${scale}x text scale', (t) async {
        await _pump(
          t,
          AnnouncementResponsesCard(stats: [
            _stat(
              title: 'A rather long announcement title that will not fit',
              readCount: 120,
              counts: const {
                AnnouncementReaction.amen: 30,
                AnnouncementReaction.praise: 12,
                AnnouncementReaction.pray: 8,
                AnnouncementReaction.love: 44,
              },
            ),
          ]),
          textScale: scale,
        );

        expect(t.takeException(), isNull);
      });
    }
  });

  group('ChurchAnnouncementsScreen', () {
    testWidgets('renders its empty state without a network', (t) async {
      t.view.physicalSize = const Size(360, 720);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      // The screen brings its own Scaffold, so it is the root here — put
      // it inside a scroll view and its height is unbounded.
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const ChurchAnnouncementsScreen(
          church: Church(
            id: '1',
            name: 'Harare Central SDA',
            city: 'Harare',
            membersCount: 0,
          ),
          autoLoad: false,
        ),
      ));
      await t.pump();

      expect(find.text('Nothing yet'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
