import 'package:advent_connect_zw/screens/onboarding/onboarding_screen.dart';
import 'package:advent_connect_zw/screens/onboarding/widgets/film_scenes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Owner, 4 Nov 2026: the intro took too long (46s, no Skip).
void main() {
  test('dropped scenes are jumped over', () {
    // Prayer (s2) sits between churches and chat.
    expect(OnboardingScreen.jumpTargetFor(FilmTimeline.s1.$2 + 0.001),
        FilmTimeline.s3.$1);
    // Marketplace, Watch (s4, s5) between chat and Library.
    expect(OnboardingScreen.jumpTargetFor(FilmTimeline.s5.$1),
        FilmTimeline.s6.$1);
    // Nothing after the Library: the film ends there and sign-in opens.
    expect(OnboardingScreen.filmEnd, FilmTimeline.s6.$2);
    expect(OnboardingScreen.keptScenes.contains(FilmTimeline.s10), isFalse);
  });

  test('kept scenes play through', () {
    for (final w in OnboardingScreen.keptScenes) {
      expect(OnboardingScreen.jumpTargetFor((w.$1 + w.$2) / 2), isNull);
    }
  });

  test('the whole film now lasts under 16 seconds', () {
    // Played fraction of the master timeline x the controller's 35s.
    var played = 0.0;
    var cursor = 0.0;
    for (final w in OnboardingScreen.keptScenes) {
      final start = w.$1 > cursor ? w.$1 : cursor;
      played += w.$2 - start;
      cursor = w.$2;
    }
    expect(played * 35, lessThan(16));
  });

  testWidgets('when the film ends, sign-in opens by itself', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (_) async => null,
    );
    final router = GoRouter(
      initialLocation: '/onboarding',
      routes: [
        GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
        GoRoute(
          path: '/login',
          name: 'login',
          builder: (_, _) => const Scaffold(body: Text('LOGIN')),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    expect(find.text('Skip'), findsOneWidget);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pumpAndSettle();
    expect(find.text('LOGIN'), findsOneWidget);
  });
}
