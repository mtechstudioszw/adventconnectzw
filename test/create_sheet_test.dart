import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/home/create_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The "What would you like to share?" chooser.
///
/// It used to be eight identical glass tiles two-across. The redesign splits
/// them: Post and Story as a primary pair, the other six as full-width rows.
///
/// The rows are the part worth pinning. Their labels are long ("Reviewed
/// before it goes live") and they scale with the system font — a tighter
/// grid would either truncate them or overflow. A `Row` that runs out of
/// width THROWS rather than clipping quietly, and this project has shipped
/// that bug before, so every text scale gets a pass here.
Future<void> _open(WidgetTester t, double scale) async {
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showCreateSheet(ctx),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 700));
}

void main() {
  for (final scale in <double>[1.0, 1.6, 2.5]) {
    testWidgets('create sheet lays out at ${scale}x text scale', (t) async {
      t.view.physicalSize = const Size(360, 720);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      await _open(t, scale);

      expect(t.takeException(), isNull);
      expect(find.text('Post'), findsOneWidget);
      expect(find.text('Story'), findsOneWidget);
    });
  }

  testWidgets('every create option is still reachable', (t) async {
    t.view.physicalSize = const Size(360, 720);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await _open(t, 1.0);

    // The split into primary/secondary must not have dropped one on the
    // floor — that is the obvious way to break this refactor, and it would
    // silently remove a whole way of contributing to the app.
    for (final label in const [
      'Post',
      'Story',
      'Event',
      'Prayer request',
      'Church notice',
      'Advent News',
      'Sell something',
      'Job opening',
    ]) {
      expect(
        find.text(label),
        findsOneWidget,
        reason: '$label disappeared from the create sheet',
      );
    }
  });

  testWidgets('choosing an option returns its kind', (t) async {
    t.view.physicalSize = const Size(360, 720);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    CreateKind? chosen;
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () async => chosen = await showCreateSheet(ctx),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 700));

    // A secondary row, since those are the ones that changed shape.
    await t.tap(find.text('Job opening'));
    await t.pumpAndSettle();

    expect(chosen, CreateKind.job);
  });
}
