// The onboarding film can't be eyeballed here, so this walks every new
// scene across its whole timeline window and fails on any layout error
// (overflow, infinite constraint) or paint exception.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/onboarding/widgets/film_scenes.dart';
import 'package:advent_connect_zw/screens/onboarding/widgets/film_scenes_library.dart';

Widget _stage(Widget child) => MaterialApp(
      home: Scaffold(
        body: SafeArea(
          // Mirrors OnboardingScreen._buildStage.
          child: Padding(
            padding: const EdgeInsets.only(bottom: 120),
            child: Stack(alignment: Alignment.center, children: [child]),
          ),
        ),
      ),
    );

void main() {
  // Every scene, and the window it must survive. All ten — the original
  // seven are covered too, because the failure this test first caught
  // (an easeOutBack progress fed straight to Opacity, which overshoots
  // 1.0 and trips an assert) is a mistake the whole file is exposed to.
  final scenes = <String, (({double a, double b}), Widget Function(double))>{
    'brand': (
      (a: FilmTimeline.s0.$1, b: FilmTimeline.s0.$2),
      (t) => SceneBrandOpen(t: t)
    ),
    'church': (
      (a: FilmTimeline.s1.$1, b: FilmTimeline.s1.$2),
      (t) => SceneChurch(t: t)
    ),
    'prayer': (
      (a: FilmTimeline.s2.$1, b: FilmTimeline.s2.$2),
      (t) => ScenePrayer(t: t)
    ),
    'chat': (
      (a: FilmTimeline.s3.$1, b: FilmTimeline.s3.$2),
      (t) => SceneChatMarket(t: t)
    ),
    'market': (
      (a: FilmTimeline.s4.$1, b: FilmTimeline.s4.$2),
      (t) => SceneMarketJobs(t: t)
    ),
    'watch': (
      (a: FilmTimeline.s5.$1, b: FilmTimeline.s5.$2),
      (t) => SceneWatch(t: t)
    ),
    'library': (
      (a: FilmTimeline.s6.$1, b: FilmTimeline.s6.$2),
      (t) => SceneLibrary(t: t)
    ),
    'feed': (
      (a: FilmTimeline.s7.$1, b: FilmTimeline.s7.$2),
      (t) => SceneFeed(t: t)
    ),
    'quiz': (
      (a: FilmTimeline.s8.$1, b: FilmTimeline.s8.$2),
      (t) => SceneQuiz(t: t)
    ),
    'finale': (
      (a: FilmTimeline.s9.$1, b: FilmTimeline.s9.$2),
      (t) => SceneSabbathFinale(t: t)
    ),
  };

  for (final entry in scenes.entries) {
    testWidgets('${entry.key} scene renders across its window', (t) async {
      final (window, build) = entry.value;
      // Sample densely — a scene can be fine at its midpoint and
      // overflow during a scale/translate beat.
      for (var i = 0; i <= 40; i++) {
        final v = window.a + (window.b - window.a) * (i / 40);
        await t.pumpWidget(_stage(build(v)));
        await t.pump(const Duration(milliseconds: 16));
        expect(
          t.takeException(),
          isNull,
          reason: '${entry.key} threw at t=${v.toStringAsFixed(4)}',
        );
      }
    });
  }

  // The default test surface is 800x600 — WIDER than any phone this ships
  // to. Re-run the whole film on a 360x640 budget device, which is where
  // a fixed 300px stage and a 280px card actually get squeezed.
  testWidgets('every scene survives a 360dp phone', (t) async {
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    for (final entry in scenes.entries) {
      final (window, build) = entry.value;
      for (var i = 0; i <= 20; i++) {
        final v = window.a + (window.b - window.a) * (i / 20);
        await t.pumpWidget(_stage(build(v)));
        await t.pump(const Duration(milliseconds: 16));
        expect(
          t.takeException(),
          isNull,
          reason: '${entry.key} threw at 360dp, t=${v.toStringAsFixed(4)}',
        );
      }
    }
  });

  testWidgets('timeline windows are ordered, overlapping and complete',
      (t) async {
    const windows = [
      FilmTimeline.s0,
      FilmTimeline.s1,
      FilmTimeline.s2,
      FilmTimeline.s3,
      FilmTimeline.s4,
      FilmTimeline.s5,
      FilmTimeline.s6,
      FilmTimeline.s7,
      FilmTimeline.s8,
      FilmTimeline.s9,
    ];
    expect(windows.first.$1, 0.0);
    expect(windows.last.$2, 1.0);
    for (var i = 1; i < windows.length; i++) {
      // Each scene starts BEFORE the previous ends, so exits are
      // entrances and the film never shows a gap.
      expect(
        windows[i].$1,
        lessThan(windows[i - 1].$2),
        reason: 'scene $i does not overlap scene ${i - 1}',
      );
      expect(windows[i].$2, greaterThan(windows[i - 1].$2));
    }
    // One tap target per scene.
    expect(FilmTimeline.boundaries.length, windows.length);
  });
}
