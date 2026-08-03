import 'package:advent_connect_zw/screens/settings/sound_settings_screen.dart';
import 'package:advent_connect_zw/services/quiz_music.dart';
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
  testWidgets('offers effects, music and vibration', (tester) async {
    await tester.pumpWidget(_screen());
    await tester.pumpAndSettle();

    expect(find.text('Sound effects'), findsOneWidget);
    expect(find.text('Quiz music'), findsOneWidget);
    expect(find.text('Vibration'), findsOneWidget);
    // Three independent switches. Muting the effects must not also kill
    // the music or the haptics — that was the founder's whole ask.
    expect(find.byType(Switch), findsNWidgets(3));
    // One volume slider each for effects and music.
    expect(find.byType(Slider), findsNWidgets(2));
  });

  testWidgets('no volume slider can be dragged to silence', (tester) async {
    await tester.pumpWidget(_screen());
    await tester.pumpAndSettle();

    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    expect(sliders, hasLength(2));

    for (final slider in sliders) {
      expect(
        slider.min,
        greaterThan(0.0),
        reason: 'silence belongs to the toggle above it, which can be undone',
      );
      expect(slider.value, greaterThanOrEqualTo(slider.min));
    }

    // Each control keeps its own floor rather than sharing one.
    expect(sliders.first.min, QuizSfx.kMinVolume);
    expect(sliders.last.min, QuizMusic.kMinVolume);
  });

  testWidgets('the music sits under the effects by default', (tester) async {
    await tester.pumpWidget(_screen());
    await tester.pumpAndSettle();

    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    expect(
      sliders.last.value,
      lessThan(sliders.first.value),
      reason: 'a soundtrack competing with the answer sounds reads as muddy',
    );
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
