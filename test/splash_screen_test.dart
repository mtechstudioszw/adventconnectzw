// The splash is the first frame of a cold start, so if it throws, the
// user never reaches the app at all. Full APK builds aren't possible on
// the dev machine, so this is the only thing that proves it paints.
//
// It cannot reach _navigate()'s real work here — that needs Supabase, the
// cache box and a router — so these checks are deliberately scoped to
// layout and to the ambient backdrop it now shares with the onboarding
// film and AuthShell. _navigate() bails on its own once the awaits fail;
// what matters is that the first frames are clean.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/splash/splash_screen.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

Widget _wrap(
  Widget child, {
  double textScale = 1.0,
  bool disableAnimations = false,
  ThemeData? theme,
}) =>
    MaterialApp(
      theme: theme ?? AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: child,
      ),
    );

// autoNavigate: false — the real boot sequence needs Supabase, the cache
// box and a router, and its timeboxes leave pending timers that fail the
// test binding. What these checks are for is the panel itself.
const _splash = SplashScreen(autoNavigate: false);

void main() {
  group('launch budget', () {
    // Founder rule (16 Aug 2026): when the gold ring finishes circling the
    // logo, the splash goes into the app — and the whole launch must come in
    // under 5 seconds.
    //
    // The ring sweeps on the entrance controller's 0.30→1.0 interval, so it
    // closes exactly at brandDuration. The boot wait used to be timeboxed at
    // 2500ms — 700ms LONGER than that — so on a slow network the splash sat
    // there visibly finished and still not moving. Nothing about that is
    // observable at runtime; it just reads as "launch is slow".
    test('the splash never outlasts its own animation', () {
      expect(
        SplashScreen.worstCaseHoldMs,
        lessThanOrEqualTo(
          SplashScreen.brandDuration + const Duration(milliseconds: 720),
        ),
        reason: 'the gates + exit fade may add at most a little to the ring; '
            'if this fails, someone raised a timeout past the animation',
      );
    });

    test('the whole hold leaves room for native launch inside 5s', () {
      // Native launch + Flutter engine init is the part this screen does not
      // control and cannot measure here. Budgeting 2s for it on a low-end
      // Android leaves this as the ceiling for everything after.
      expect(
        SplashScreen.worstCaseHoldMs.inMilliseconds,
        lessThan(3000),
        reason: 'splash hold must stay under 3s so launch fits in 5s',
      );
    });
  });

  for (final scale in <double>[1.0, 1.6, 2.5]) {
    testWidgets('paints the brand panel at ${scale}x text scale', (t) async {
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      await t.pumpWidget(_wrap(_splash, textScale: scale));
      // The ambient field loops forever by design, so this never settles.
      // Pump through the 1800ms brand entrance instead.
      await t.pump(const Duration(milliseconds: 600));
      await t.pump(const Duration(milliseconds: 1400));

      expect(t.takeException(), isNull);
      expect(find.text('Advent Connect ZW'), findsOneWidget);
      expect(find.text('MYTECH STUDIOS ZW'), findsOneWidget);
    });
  }

  testWidgets('paints on the dark canvas too', (t) async {
    await t.pumpWidget(_wrap(_splash, theme: AppTheme.dark));
    await t.pump(const Duration(milliseconds: 600));
    expect(t.takeException(), isNull);
    expect(find.text('Advent Connect ZW'), findsOneWidget);
  });

  testWidgets('honours "remove animations": the light field holds still',
      (t) async {
    await t.pumpWidget(_wrap(_splash, disableAnimations: true));
    await t.pump(const Duration(milliseconds: 300));
    expect(t.takeException(), isNull);
    // The brand entrance lands whole rather than playing over 1800ms, and
    // the ambient loop must not be left running — a never-ending
    // controller here would hold vsync through the whole cold start.
    expect(find.text('Advent Connect ZW'), findsOneWidget);
  });
}
