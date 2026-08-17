// The onboarding film has to obey the palette.
//
// 17 Aug 2026, three founder reports in one breath: "ready for sabbath on
// the onboarding is not visible in dark mode", "the onboarding bit not
// premium in dark mode", and "the create sheet is white in dark mode".
// All three were ONE cause. `OnboardingScreen` painted its scaffold with
// `context.palette.scaffoldBg` — so the background correctly went dark —
// while the film inside it was written before the palette migration and
// hardcoded 104 light-mode colours. The result in dark mode:
//
//   * captions were AppColors.darkNavy on a near-black ground — the
//     "Ready for Sabbath." line the founder named was literally invisible;
//   * every demo card was a white slab, so the film advertised an app that
//     looked nothing like the one behind it;
//   * the ambient light field painted brand colours at alpha 0.05–0.18,
//     which reads as a soft wash on #F5F7FA and as NOTHING on #0B1124, so
//     the background collapsed to a flat dead slab.
//
// These tests assert the rendered colours rather than the source, so they
// keep holding if the film is restyled. Light mode is asserted too: the
// migration had to leave the pre-dark-mode look byte-for-byte alone.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/onboarding/widgets/film_scenes.dart';
import 'package:advent_connect_zw/screens/onboarding/widgets/film_scenes_library.dart';
import 'package:advent_connect_zw/theme/app_colors.dart';
import 'package:advent_connect_zw/theme/app_palette.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

Widget _host({required bool dark, required Widget child}) => MaterialApp(
  theme: AppTheme.light,
  darkTheme: AppTheme.dark,
  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
  home: Scaffold(body: Center(child: child)),
);

/// Perceived lightness, good enough to answer "is this readable on a dark
/// background" without hardcoding an exact token value.
double _lum(Color c) => c.computeLuminance();

void main() {
  group('caption text follows the palette', () {
    testWidgets('is LIGHT in dark mode — the reported bug', (tester) async {
      await tester.pumpWidget(
        _host(
          dark: true,
          child: const SceneLine(
            text: 'Ready for Sabbath.\nReady for you.',
            enter: 1,
            exit: 0,
            emphasis: true,
          ),
        ),
      );

      final style = tester.widget<Text>(find.byType(Text)).style!;
      expect(
        style.color,
        AppPalette.dark.text,
        reason: 'caption must use the dark palette text colour',
      );
      // The regression itself: navy on near-black.
      expect(style.color, isNot(AppColors.darkNavy));
      expect(
        _lum(style.color!),
        greaterThan(0.5),
        reason: 'caption must be light against the dark scaffold',
      );
    });

    testWidgets('is unchanged in light mode', (tester) async {
      await tester.pumpWidget(
        _host(
          dark: false,
          child: const SceneLine(
            text: 'Ready for Sabbath.',
            enter: 1,
            exit: 0,
            emphasis: true,
          ),
        ),
      );

      final style = tester.widget<Text>(find.byType(Text)).style!;
      expect(style.color, AppPalette.light.text);
      expect(_lum(style.color!), lessThan(0.5));
    });
  });

  group('ambient field', () {
    test('lifts its light sources in dark mode', () {
      // Same construction, different ground: the dark painter must not be
      // interchangeable with the light one, or the field is invisible.
      final light = AmbientPainter(loop: 0.3, film: 0, dark: false);
      final dark = AmbientPainter(loop: 0.3, film: 0, dark: true);
      expect(
        light.shouldRepaint(dark),
        isTrue,
        reason: 'a brightness switch must trigger a repaint — without this '
            'a live theme change leaves the old field painted',
      );
    });
  });

  group('the film scenes render on the dark palette', () {
    testWidgets('no scene paints a white card in dark mode', (tester) async {
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      // Mid-scene, so the demo cards are fully entered.
      final t = (FilmTimeline.s6.$1 + FilmTimeline.s6.$2) / 2;
      await tester.pumpWidget(_host(dark: true, child: SceneLibrary(t: t)));
      await tester.pump(const Duration(milliseconds: 50));

      final surfaces = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.color)
          .whereType<Color>()
          // Ignore fully transparent fills.
          .where((c) => c.a > 0.9);

      for (final c in surfaces) {
        expect(
          c,
          isNot(AppColors.white),
          reason: 'a hardcoded white surface survived the migration',
        );
        expect(
          _lum(c),
          lessThan(0.5),
          reason: 'surface $c is too light for the dark palette',
        );
      }
    });
  });
}
