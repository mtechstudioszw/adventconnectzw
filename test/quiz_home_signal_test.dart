// Home's "someone wants to play" signal.
//
// Live match is the only real-time, person-to-person feature in the app and
// it sat two taps deep behind a tile in the quiz lobby — which is most of
// why only ~11 members have ever played one. The founder's fix (17 Aug) was
// to surface it on Home: a dot on the Quiz pill for "someone wants you".
//
// The trap this file guards is not the dot, it is the plumbing behind it.
// `QuizMatchService.invites()` is a ONE-SHOT RPC, not a stream, so a naive
// implementation fires a network round trip from `build` on the busiest
// screen in the app. QuizHomeSignal caches it; these tests pin the caching
// rules and — separately — that the count cannot leak across a sign-out,
// which is the standing static-state trap in this codebase.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/quiz_home_signal.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/home/library_tiles.dart';

Widget _host({required bool dark}) => MaterialApp(
  theme: AppTheme.light,
  darkTheme: AppTheme.dark,
  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
  home: const Scaffold(body: Center(child: LibraryTiles())),
);

/// Every circular Container currently painted.
Iterable<Color> _dots(WidgetTester t) => t
    .widgetList<Container>(find.byType(Container))
    .map((c) => c.decoration)
    .whereType<BoxDecoration>()
    .where((d) => d.shape == BoxShape.circle)
    .map((d) => d.color)
    .whereType<Color>();

void main() {
  setUp(QuizHomeSignal.resetForSignOut);
  tearDown(QuizHomeSignal.resetForSignOut);

  group('the dot', () {
    testWidgets('is absent when nobody is waiting', (t) async {
      t.view.physicalSize = const Size(1400, 260);
      t.view.devicePixelRatio = 2.0;
      addTearDown(t.view.reset);

      await t.pumpWidget(_host(dark: false));
      await t.pumpAndSettle();

      expect(_dots(t), isEmpty, reason: 'quiet Home must show no dot');
    });

    testWidgets('appears when an invite lands, with no rebuild of Home',
        (t) async {
      t.view.physicalSize = const Size(1400, 260);
      t.view.devicePixelRatio = 2.0;
      addTearDown(t.view.reset);

      await t.pumpWidget(_host(dark: false));
      await t.pumpAndSettle();
      expect(_dots(t), isEmpty);

      // The notifier alone drives it — nothing calls setState on Home.
      QuizHomeSignal.invites.value = 1;
      await t.pumpAndSettle();

      expect(_dots(t), isNotEmpty, reason: 'invite must light the dot');
    });

    testWidgets('is legible on the dark page', (t) async {
      t.view.physicalSize = const Size(1400, 260);
      t.view.devicePixelRatio = 2.0;
      addTearDown(t.view.reset);

      QuizHomeSignal.invites.value = 2;
      await t.pumpWidget(_host(dark: true));
      await t.pumpAndSettle();

      final dot = _dots(t).first;
      // The light-mode green (#2E7D32) is murky on #0B1124, and this dot is
      // the only thing on Home saying someone is waiting.
      expect(
        dot.computeLuminance(),
        greaterThan(0.25),
        reason: 'dark-mode dot is too dim to notice',
      );
    });
  });

  group('caching', () {
    test('markSeen clears the count immediately', () {
      QuizHomeSignal.invites.value = 3;
      QuizHomeSignal.markSeen();
      expect(QuizHomeSignal.invites.value, 0);
    });

    test('sign-out drops the count', () {
      // Statics outlive a sign-out — the isolate is not restarted — so
      // without this the next account on the same handset opens Home to
      // the previous player's live dot.
      QuizHomeSignal.invites.value = 4;
      QuizHomeSignal.resetForSignOut();
      expect(QuizHomeSignal.invites.value, 0);
    });

    test('a listener survives reset, so Home keeps working after sign-out',
        () {
      // resetForSignOut must not dispose the notifier: LibraryTiles holds a
      // ValueListenableBuilder on it for the whole life of the app, and a
      // disposed notifier would throw on the next sign-in.
      var seen = 0;
      void listener() => seen++;
      QuizHomeSignal.invites.addListener(listener);
      addTearDown(() => QuizHomeSignal.invites.removeListener(listener));

      QuizHomeSignal.invites.value = 2;
      QuizHomeSignal.resetForSignOut();
      QuizHomeSignal.invites.value = 1;

      expect(seen, 3, reason: 'notifier must stay alive across a reset');
    });
  });
}
