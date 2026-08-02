// AuthShell is the frame for every account screen, so a layout mistake
// in it breaks five screens at once. These checks run it on a small
// phone, with a long title, and at a large system text scale — the three
// conditions that actually break auth headers.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/auth/widgets/auth_shell.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

Widget _wrap(Widget child, {double textScale = 1.0}) => MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: child,
      ),
    );

void main() {
  testWidgets('renders heading, content and footer', (t) async {
    await t.pumpWidget(_wrap(
      AuthShell(
        eyebrow: 'Account recovery',
        title: 'Forgot your\npassword?',
        subtitle: 'Enter your email and we will send you a 6-digit code.',
        icon: Icons.lock_reset_rounded,
        onBack: () {},
        footer: const Text('Back to sign in'),
        child: const SizedBox(height: 300, child: Placeholder()),
      ),
    ));
    // The ambient light loop repeats forever by design, so this never
    // settles — pump past the entrance instead.
    await t.pump(const Duration(milliseconds: 900));

    expect(t.takeException(), isNull);
    expect(find.text('ACCOUNT RECOVERY'), findsOneWidget);
    expect(find.text('Forgot your\npassword?'), findsOneWidget);
    expect(find.text('Back to sign in'), findsOneWidget);
  });

  testWidgets('no back chip when onBack is null', (t) async {
    await t.pumpWidget(_wrap(
      const AuthShell(
        title: 'Locked',
        subtitle: 'Unlock to continue.',
        child: SizedBox(height: 100),
      ),
    ));
    // The ambient light loop repeats forever by design, so this never
    // settles — pump past the entrance instead.
    await t.pump(const Duration(milliseconds: 900));
    expect(t.takeException(), isNull);
    // A locked screen must not offer a way back out.
    expect(find.byIcon(Icons.arrow_back_ios_new), findsNothing);
  });

  // 2.5x is past anything Android offers, but iOS accessibility sizes go
  // beyond 3x. The heading used to live OUTSIDE the scroll area, so at
  // these scales it outgrew the viewport on its own and the overflow was
  // unreachable rather than scrollable — it clipped every screen in the
  // flow at once. Heading and content now share one scroll view.
  for (final scale in <double>[1.6, 2.5]) {
    testWidgets('survives a 360dp phone at ${scale}x text scale', (t) async {
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      await t.pumpWidget(_wrap(
        AuthShell(
          eyebrow: 'Verify your email',
          // Deliberately long: real titles wrap, so the heading has to
          // survive growing several lines taller than it was designed for.
          title: 'Check your inbox to finish setting up',
          subtitle: 'We sent a six digit code to your email address. Enter it '
              'on the next screen to confirm it is really you.',
          icon: Icons.mark_email_read_outlined,
          onBack: () {},
          footer: const Text('Resend code'),
          child: const SizedBox(height: 400),
        ),
        textScale: scale,
      ));
      // The ambient light loop repeats forever by design, so this never
      // settles — pump past the entrance instead.
      await t.pump(const Duration(milliseconds: 900));
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('hero replaces the brand ring when given', (t) async {
    await t.pumpWidget(_wrap(
      const AuthShell(
        title: 'Welcome back',
        subtitle: 'Unlock to continue.',
        icon: Icons.church_rounded,
        hero: Icon(Icons.fingerprint, key: ValueKey('badge')),
        child: SizedBox(height: 100),
      ),
    ));
    await t.pump(const Duration(milliseconds: 900));
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('badge')), findsOneWidget);
    // The default ring's glyph must be gone, not stacked above the hero.
    expect(find.byIcon(Icons.church_rounded), findsNothing);
  });
}
