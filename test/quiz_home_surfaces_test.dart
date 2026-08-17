// Getting into the quiz from Home.
//
// Founder decision, 17 Aug: BOTH a Daily Challenge card in the Today slot
// (the habit) and a live signal for "someone wants you" (the interrupt).
// Live match is the only real-time, person-to-person feature in the app and
// it sat two taps deep behind a tile — most of why only ~11 members have
// ever played one.
//
// The behaviour worth defending is the RESTRAINT. The old lobby tile
// promised "head to head, same clock" whether forty people were online or
// nobody, so members tapped it at a quiet hour, waited out a search, found
// no one, and concluded the feature was broken. An empty arena is the
// common case, so Home says nothing at all unless there is something true
// to say.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/quiz_round.dart';
import 'package:advent_connect_zw/services/quiz_home_signal.dart';
import 'package:advent_connect_zw/services/quiz_launch_intent.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/home/quiz_live_strip.dart';

Widget _host({bool dark = false}) => MaterialApp(
  theme: AppTheme.light,
  darkTheme: AppTheme.dark,
  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
  home: const Scaffold(body: QuizLiveStrip()),
);

void main() {
  setUp(() {
    QuizHomeSignal.resetForSignOut();
    QuizLaunchIntent.clear();
  });
  tearDown(() {
    QuizHomeSignal.resetForSignOut();
    QuizLaunchIntent.clear();
  });

  group('the live strip stays silent unless it is true', () {
    testWidgets('renders NOTHING with no invites and an empty arena',
        (t) async {
      await t.pumpWidget(_host());
      await t.pumpAndSettle();

      // Not a placeholder, not "nobody online" — nothing at all. Home does
      // not advertise an empty arena.
      expect(find.byIcon(Icons.bolt_rounded), findsNothing);
      expect(find.textContaining('Live match'), findsNothing);
    });

    testWidgets('appears when somebody has challenged you', (t) async {
      QuizHomeSignal.invites.value = 1;
      await t.pumpWidget(_host());
      await t.pumpAndSettle();

      // Notification-grade wording — this is the interrupt, not a label.
      expect(find.text('Someone wants to play'), findsOneWidget);
      expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
    });

    testWidgets('pluralises several challengers', (t) async {
      QuizHomeSignal.invites.value = 3;
      await t.pumpWidget(_host());
      await t.pumpAndSettle();

      expect(find.text('3 people want to play'), findsOneWidget);
    });

    testWidgets('an invite outranks the online count', (t) async {
      // Somebody waiting for you matters more than a crowd you have not
      // met, so the invite wording wins.
      QuizHomeSignal.invites.value = 2;
      await t.pumpWidget(_host());
      await t.pumpAndSettle();

      expect(find.textContaining('want to play'), findsOneWidget);
      expect(find.textContaining('online now'), findsNothing);
    });

    testWidgets('survives a dark app without throwing', (t) async {
      QuizHomeSignal.invites.value = 1;
      await t.pumpWidget(_host(dark: true));
      await t.pumpAndSettle();

      expect(find.text('Someone wants to play'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('lays out at 2.5x text scale', (t) async {
      // Every string here is in a Row, and an unflexed Text in a Row THROWS
      // rather than clipping. This project has shipped that bug before.
      QuizHomeSignal.invites.value = 4;
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2.5)),
            child: Scaffold(body: QuizLiveStrip()),
          ),
        ),
      );
      await t.pumpAndSettle();

      expect(t.takeException(), isNull);
    });
  });

  group('the Daily Challenge card skips the lobby', () {
    test('hands the lobby a mode to start', () {
      // Home does NOT run the round itself. The lobby owns results, the
      // streak write, challenge submit/send and the pending-opponent
      // claim; a second copy of that flow would drift, and quietly.
      QuizLaunchIntent.mode = QuizMode.daily;
      expect(QuizLaunchIntent.take(), QuizMode.daily);
    });

    test('take() clears, so the round does not replay', () {
      // Without clearing, returning to the lobby from the results screen
      // would immediately start another round.
      QuizLaunchIntent.mode = QuizMode.daily;
      QuizLaunchIntent.take();
      expect(QuizLaunchIntent.take(), isNull);
    });

    test('an ordinary visit to the lobby starts nothing', () {
      expect(QuizLaunchIntent.take(), isNull);
    });
  });
}
