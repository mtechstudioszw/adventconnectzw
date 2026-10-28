import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/home/create_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The "What would you like to share?" chooser.
///
/// Now a "studio" (28 Oct 2026): Post and Story as format cards with
/// previews, the other five as tool cards — two across, or one column at
/// large text sizes.
///
/// The tool labels are the part worth pinning. Their labels are long ("Reviewed
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
      expect(find.text('Write'), findsOneWidget);
      expect(find.text('Text story'), findsOneWidget);
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
    //
    // 'Church notice' is deliberately NOT in this list (23 Aug 2026). It was
    // removed from the sheet on purpose, not dropped: `notices` has no
    // church_id column, so it was never attached to a church; every
    // authenticated member could read every notice; there was no admin gate
    // on either the client or the RLS policy; and the table held 0 rows from
    // 0 posters since launch. Founder's call, given those findings.
    //
    // The guard this test provides is unchanged for the seven that remain —
    // the point is to catch an ACCIDENTAL drop, and this one was a decision.
    // If the feature is rebuilt properly (church_id + an
    // is_approved_church_admin policy), add it back here at the same time.
    for (final label in const [
      'Write',
      'Photo',
      'Text story',
      'Photo story',
      'Event',
      'Prayer',
      'News',
      'Sell',
      'Hire',
    ]) {
      expect(
        find.text(label),
        findsOneWidget,
        reason: '$label disappeared from the create sheet',
      );
    }

    // The other half of the same rule: it must not come BACK by accident.
    // Restoring the tile without the schema and the policy behind it would
    // re-open a hole where any member publishes what reads as official
    // church communication to everybody — which is what it did before.
    expect(
      find.text('Church notice'),
      findsNothing,
      reason:
          'Church notice is ungated — it needs notices.church_id and an '
          'is_approved_church_admin policy before it goes back on the sheet',
    );
  });

  testWidgets('choosing an option returns its kind', (t) async {
    t.view.physicalSize = const Size(360, 720);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    CreateRequest? chosen;
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

    // A dock tool. It sits below the fold on a short phone, so scroll to
    // it the way a member would.
    await t.ensureVisible(find.text('Hire'));
    await t.pump();
    await t.tap(find.text('Hire'));
    await t.pumpAndSettle();

    expect(chosen?.kind, CreateKind.job);
  });
}
