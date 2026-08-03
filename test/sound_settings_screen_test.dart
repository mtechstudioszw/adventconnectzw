import 'package:advent_connect_zw/screens/settings/sound_settings_screen.dart';
import 'package:advent_connect_zw/services/quiz_sfx.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sound & haptics in the main settings (#3 A3, 3 Aug 2026).
///
/// Reported as "there is no settings button in quiz — the settings button
/// appears only while quiz is loading". It was literally true: the mute
/// toggle and volume slider lived on `QuizBootScreen`, which is a GATE,
/// not a route — it crossfades into the lobby after ~900ms and is never
/// seen again. So the only volume control in the app was visible for
/// under a second per launch.
Widget _screen() => const MaterialApp(home: SoundSettingsScreen());

void main() {
  testWidgets('offers effects, volume and vibration', (tester) async {
    await tester.pumpWidget(_screen());
    await tester.pumpAndSettle();

    expect(find.text('Sound effects'), findsOneWidget);
    expect(find.text('Vibration'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    // Two independent switches — muting sound must not also kill haptics.
    expect(find.byType(Switch), findsNWidgets(2));
  });

  testWidgets('the volume slider cannot be dragged to silence', (
    tester,
  ) async {
    await tester.pumpWidget(_screen());
    await tester.pumpAndSettle();

    final slider = tester.widget<Slider>(find.byType(Slider));

    expect(
      slider.min,
      QuizSfx.kMinVolume,
      reason: 'silence belongs to the mute toggle, which can be undone',
    );
    expect(slider.min, greaterThan(0.0));
    expect(slider.value, greaterThanOrEqualTo(slider.min));
  });

  testWidgets('turning sound off leaves vibration alone', (tester) async {
    await QuizSfx.setMuted(false);
    await QuizSfx.setHapticsEnabled(true);

    await tester.pumpWidget(_screen());
    await tester.pumpAndSettle();

    // First switch is Sound effects, second is Vibration.
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(QuizSfx.muted, isTrue);
    expect(
      QuizSfx.hapticsEnabled,
      isTrue,
      reason: 'in a quiet room silent feedback is exactly what you want',
    );

    await QuizSfx.setMuted(false);
  });

  for (final scale in const [1.0, 1.6, 2.5]) {
    testWidgets('lays out on a 360dp phone at ${scale}x text', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: _screen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }
}
