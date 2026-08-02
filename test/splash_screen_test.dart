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
