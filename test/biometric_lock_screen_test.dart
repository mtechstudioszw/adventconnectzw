// The lock screen is the first thing a returning user sees, and its
// heading block (badge + title) sits OUTSIDE the shell's scroll area, so
// a small phone at a large system text scale is exactly where it breaks.
// Full APK builds aren't possible on the dev machine, so this is the only
// thing that proves it lays out.
//
// Before the AuthShell conversion this screen was a Column with two
// Spacers, a hard-coded 216dp badge and no scroll: it overflowed by 49px
// at 2.0x text scale on a 360x640 phone, and 262px at 2.5x. Android's
// accessibility font size reaches 2.0x, so that was reachable in
// production. Hence the scale sweep below.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/splash/biometric_lock_screen.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

Widget _wrap(
  Widget child, {
  double textScale = 1.0,
  bool disableAnimations = false,
}) =>
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: child,
      ),
    );

// autoPrompt: false everywhere — otherwise it calls into the platform
// biometric channel and then routes, neither of which exists in a test.
const _screen = BiometricLockScreen(autoPrompt: false);

void main() {
  for (final scale in <double>[1.0, 1.6, 2.0, 2.5]) {
    testWidgets('lays out on a 360x640 phone at ${scale}x text scale',
        (t) async {
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      await t.pumpWidget(_wrap(_screen, textScale: scale));
      // The ambient light loop and the sonar both repeat forever by
      // design, so this never settles — pump past the entrance instead.
      await t.pump(const Duration(milliseconds: 900));

      expect(t.takeException(), isNull);
      expect(find.text('Welcome back'), findsOneWidget);
    });
  }

  testWidgets('offers no way out — a locked screen has no back affordance',
      (t) async {
    await t.pumpWidget(_wrap(_screen));
    await t.pump(const Duration(milliseconds: 900));
    expect(t.takeException(), isNull);
    expect(find.byIcon(Icons.arrow_back_ios_new), findsNothing);
  });

  testWidgets('honours "remove animations": nothing is left looping',
      (t) async {
    await t.pumpWidget(_wrap(_screen, disableAnimations: true));
    await t.pump(const Duration(milliseconds: 300));
    // The sonar used to ..repeat() straight out of initState regardless
    // of the accessibility flag, so the tree never went quiet. If any
    // controller is still running, pumpAndSettle throws on timeout.
    await t.pumpAndSettle(const Duration(milliseconds: 50));
    expect(t.takeException(), isNull);
  });

  testWidgets('never tells the user the app is waiting', (t) async {
    await t.pumpWidget(_wrap(_screen));
    await t.pump(const Duration(milliseconds: 900));
    // The founder's note: "it says waiting… should be fast like WhatsApp".
    // While the OS sheet is up the SENSOR is working, not the app, and
    // labelling our own button "Waiting…" made a sub-second unlock read
    // as a stall. The badge and status line carry the sensing state now.
    expect(find.textContaining('Waiting'), findsNothing);
    expect(find.text('Unlock'), findsOneWidget);
  });

  testWidgets('the unlock button stays live — a stuck prompt is not a dead end',
      (t) async {
    await t.pumpWidget(_wrap(_screen));
    await t.pump(const Duration(milliseconds: 900));
    // `_busy` used to include the sensing stage, so if the OS prompt
    // never returned the only control on screen was permanently greyed
    // out. Only a successful unlock disables it now.
    final button = t.widget<InkWell>(
      find.ancestor(
        of: find.text('Unlock'),
        matching: find.byType(InkWell),
      ),
    );
    expect(button.onTap, isNotNull);
  });

  testWidgets('shows the fingerprint sensor and its instruction by default',
      (t) async {
    await t.pumpWidget(_wrap(_screen));
    await t.pump(const Duration(milliseconds: 900));
    // No platform channel in a widget test, so primaryKind() never
    // answers and the screen must still be usable — it defaults to
    // fingerprint rather than rendering a blank or generic sensor.
    expect(find.byIcon(Icons.fingerprint), findsWidgets);
    expect(find.textContaining('fingerprint sensor'), findsOneWidget);
  });
}
