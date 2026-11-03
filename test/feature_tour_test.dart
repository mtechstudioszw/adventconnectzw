import 'dart:io';

import 'package:advent_connect_zw/services/cache_service.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/tour/feature_tour.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

const _steps = [
  TourStep(anchor: 'a', title: 'First thing', body: 'Does the first job.'),
  TourStep(anchor: 'missing', title: 'Not here', body: 'Skipped.'),
  TourStep(anchor: 'b', title: 'Second thing', body: 'Does the second job.'),
];

Widget _app(void Function(BuildContext) onReady) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: Builder(
      builder: (context) {
        WidgetsBinding.instance.addPostFrameCallback((_) => onReady(context));
        return const Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TourAnchor(id: 'a', child: Icon(Icons.add, size: 48)),
            TourAnchor(id: 'b', child: Icon(Icons.chat, size: 48)),
          ],
        );
      },
    ),
  ),
);

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('tour');
    Hive.init(dir.path);
    await CacheService.debugUseBox(await Hive.openBox<String>('t'));
  });
  tearDown(() async {
    await CacheService.debugUseBox(null);
    await dir.delete(recursive: true);
  });

  testWidgets('spotlights each anchor, skips missing ones, then never again', (
    t,
  ) async {
    Future<bool>? run;
    await t.pumpWidget(
      _app((c) {
        run ??= FeatureTour.run(c, tourId: 'test_v1', steps: _steps);
      }),
    );
    await t.pumpAndSettle();

    expect(find.text('First thing'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget); // 'missing' was skipped
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    expect(find.text('Second thing'), findsOneWidget);
    await t.tap(find.text('Got it'));
    await t.pumpAndSettle();
    // The "done" flag is a real disk write: let it finish in real time.
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await t.pumpAndSettle();
    expect(find.text('Second thing'), findsNothing);
    expect(await t.runAsync(() => run!), isTrue);
    expect(FeatureTour.isDone('test_v1'), isTrue);

    // Second time: nothing shows.
    Future<bool>? again;
    await t.pumpWidget(
      _app((c) {
        again ??= FeatureTour.run(c, tourId: 'test_v1', steps: _steps);
      }),
    );
    await t.pumpAndSettle();
    expect(await t.runAsync(() => again!), isFalse);
    expect(find.text('First thing'), findsNothing);
  });

  testWidgets('Skip tour ends it and marks it done', (t) async {
    await t.pumpWidget(
      _app((c) {
        FeatureTour.run(c, tourId: 'skip_v1', steps: _steps);
      }),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Skip tour'));
    await t.pumpAndSettle();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await t.pumpAndSettle();
    expect(find.text('First thing'), findsNothing);
    expect(FeatureTour.isDone('skip_v1'), isTrue);
  });
}
