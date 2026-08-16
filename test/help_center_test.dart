// Settings → Help center.
//
// The reason this test exists: `settings_screen.dart` pushed the route name
// 'help_center' and no such route was ever registered. GoRouter throws on an
// unknown name, so the entry was dead — and nothing caught it, because a
// route name is just a string until someone taps it.
//
// So the first test here is not about the content at all. It asserts the name
// resolves, which is the class of bug that actually shipped.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/config/router_config.dart';
import 'package:advent_connect_zw/screens/legal/help_center_screen.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

void main() {
  test('the help_center route name resolves', () {
    // namedLocation throws GoError if the name is not registered — which is
    // exactly what Settings was walking into.
    expect(
      () => appRouter.configuration.namedLocation('help_center'),
      returnsNormally,
    );
    expect(
      appRouter.configuration.namedLocation('help_center'),
      '/help',
    );
  });

  for (final scale in <double>[1.0, 2.0]) {
    testWidgets('the guide lays out at ${scale}x text scale', (t) async {
      t.view.physicalSize = const Size(360, 720);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: const HelpCenterScreen(),
        ),
      ));
      await t.pump(const Duration(milliseconds: 400));

      expect(t.takeException(), isNull);
      expect(find.text('How to use the app'), findsOneWidget);
    });
  }

  testWidgets('it carries the sections a member actually needs', (t) async {
    t.view.physicalSize = const Size(360, 720);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(const MaterialApp(home: HelpCenterScreen()));
    await t.pump(const Duration(milliseconds: 400));

    final scrollable = find.byType(Scrollable).first;
    // Getting started is the section the intro points at, and Getting help
    // is where someone lands when nothing else answered them. If either is
    // missing the page is decorative.
    for (final section in ['Getting started', 'Getting help']) {
      await t.scrollUntilVisible(find.text(section), 300,
          scrollable: scrollable);
      expect(find.text(section), findsOneWidget, reason: section);
    }
    expect(t.takeException(), isNull);
  });
}
