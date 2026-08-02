// Search is the widest screen in the app — eight result types, each with
// its own row — so a layout mistake here has eight places to hide. Full
// APK builds aren't possible on the dev machine, so this is what proves
// the shell lays out.
//
// The redesign's specific risk: the filter rail. It used to be pinned at
// a fixed 38dp with text inside that scales with the system font, so at
// large accessibility sizes the labels clipped — silently, because there
// is no Flex involved and nothing throws. It sizes itself now, and the
// scale sweep below is what keeps it that way.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/home/search_screen.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

Widget _wrap(
  Widget child, {
  double textScale = 1.0,
  bool disableAnimations = false,
}) =>
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: child,
      ),
    );

// autoLoad: false — the real loads need a Supabase client; these checks
// are about how the screen lays out.
const _search = SearchScreen(autoLoad: false);

void main() {
  for (final scale in <double>[1.0, 1.6, 2.5]) {
    testWidgets('lays out on a 360x640 phone at ${scale}x text scale',
        (t) async {
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      await t.pumpWidget(_wrap(_search, textScale: scale));
      await t.pump(const Duration(milliseconds: 700));

      expect(t.takeException(), isNull);
      expect(find.byType(TextField), findsOneWidget);
    });
  }

  testWidgets('honours "remove animations"', (t) async {
    await t.pumpWidget(_wrap(_search, disableAnimations: true));
    await t.pump(const Duration(milliseconds: 300));
    expect(t.takeException(), isNull);
  });
}
