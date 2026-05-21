// Render tests for AuthScreen.
//
// These exercise the initial layout + form validation only — i.e. the
// parts that don't touch Supabase. The Continue button and the Google
// button call AuthService.emailExists / signInWithGoogle, which would
// hit a live Supabase backend, so we don't tap those here. Live auth
// flows need an instrumented device test, not a widget test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/auth/auth_screen.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: child);
}

void main() {
  group('AuthScreen — initial render', () {
    testWidgets('shows headline, Google button, OR divider, and email field',
        (tester) async {
      await tester.pumpWidget(_wrap(const AuthScreen()));
      await tester.pump();

      // Stage-0 headline copy
      expect(find.textContaining('Build community.'), findsOneWidget);
      expect(find.textContaining('Find your home.'), findsOneWidget);

      // Social login button
      expect(find.text('Continue with Google'), findsOneWidget);

      // Divider literal
      expect(find.text('OR'), findsOneWidget);

      // Email field hint
      expect(find.text('Email address'), findsOneWidget);

      // Primary CTA reflects the email-entry stage
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('legal line is shown', (tester) async {
      await tester.pumpWidget(_wrap(const AuthScreen()));
      await tester.pump();

      expect(
        find.textContaining('Terms & Conditions'),
        findsOneWidget,
      );
    });
  });

  group('AuthScreen — email validation', () {
    testWidgets('rejects empty email with "Email is required"',
        (tester) async {
      await tester.pumpWidget(_wrap(const AuthScreen()));
      await tester.pump();

      // Tap Continue without entering anything.
      await tester.tap(find.text('Continue'));
      await tester.pump();

      expect(find.text('Email is required'), findsOneWidget);
    });

    testWidgets('rejects malformed email with "Enter a valid email"',
        (tester) async {
      await tester.pumpWidget(_wrap(const AuthScreen()));
      await tester.pump();

      await tester.enterText(
        find.byType(TextFormField).first,
        'not-an-email',
      );
      await tester.tap(find.text('Continue'));
      await tester.pump();

      expect(find.text('Enter a valid email'), findsOneWidget);
    });
  });
}
