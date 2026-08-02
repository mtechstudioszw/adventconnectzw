// The post composer is what opens after the create chooser, so it is the
// second half of "click share". Full APK builds aren't possible on the
// dev machine, so this is what proves it lays out.
//
// Its specific risk is horizontal: the header (title + audience pill +
// Post) and the action row (Add a photo + Preview) are both plain Rows
// whose children are text that scales with the system font. A Row that
// runs out of width throws, unlike the silent vertical clipping the
// filter rail had.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/home/composer_sheet.dart';

Future<void> _openComposer(WidgetTester t, {double textScale = 1.0}) async {
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showPostComposer(ctx),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

void main() {
  for (final scale in <double>[1.0, 1.6, 2.5]) {
    testWidgets('post composer lays out at ${scale}x text scale', (t) async {
      t.view.physicalSize = const Size(360, 720);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      await _openComposer(t, textScale: scale);

      expect(t.takeException(), isNull);
      expect(find.text('New post'), findsOneWidget);
    });
  }

  testWidgets('Post stays inert until there is something to publish',
      (t) async {
    await _openComposer(t);

    // The button filling IS the "ready to publish" signal, so an empty
    // composer must not offer a live one. It used to be a bare TextButton
    // carrying the same visual weight as Preview and Add a photo.
    InkWell postButton() => t.widget<InkWell>(
          find.ancestor(
            of: find.text('Post'),
            matching: find.byType(InkWell),
          ),
        );
    expect(postButton().onTap, isNull);

    await t.enterText(find.byType(TextField).first, 'Praise the Lord');
    await t.pump(const Duration(milliseconds: 400));

    expect(t.takeException(), isNull);
    expect(postButton().onTap, isNotNull);
  });
}
