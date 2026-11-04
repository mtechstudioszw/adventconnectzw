import 'package:advent_connect_zw/screens/onboarding/onboarding_screen.dart';
import 'package:advent_connect_zw/screens/onboarding/widgets/film_scenes.dart';
import 'package:flutter_test/flutter_test.dart';

/// Owner, 4 Nov 2026: the intro took too long (46s, no Skip).
void main() {
  test('dropped scenes are jumped over', () {
    // Prayer (s2) sits between churches and chat.
    expect(OnboardingScreen.jumpTargetFor(FilmTimeline.s1.$2 + 0.001),
        FilmTimeline.s3.$1);
    // Marketplace, Watch (s4, s5) between chat and Library.
    expect(OnboardingScreen.jumpTargetFor(FilmTimeline.s5.$1),
        FilmTimeline.s6.$1);
    // Feed, quiz, Advent AI before the finale.
    expect(OnboardingScreen.jumpTargetFor(FilmTimeline.s8.$1),
        FilmTimeline.s10.$1);
  });

  test('kept scenes play through', () {
    for (final w in OnboardingScreen.keptScenes) {
      expect(OnboardingScreen.jumpTargetFor((w.$1 + w.$2) / 2), isNull);
    }
  });

  test('the whole film now lasts under 20 seconds', () {
    // Played fraction of the master timeline x the controller's 35s.
    var played = 0.0;
    var cursor = 0.0;
    for (final w in OnboardingScreen.keptScenes) {
      final start = w.$1 > cursor ? w.$1 : cursor;
      played += w.$2 - start;
      cursor = w.$2;
    }
    expect(played * 35, lessThan(20));
  });
}
