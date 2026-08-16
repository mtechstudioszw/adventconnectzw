// The Marketplace Code of Conduct gate.
//
// This screen is the evidence trail for a seller ban: whatever it shows is
// what the member is held to. Two things are therefore pinned here — that it
// cannot be walked past without an explicit tick, and that it actually lays
// out at the text sizes real people use. The rule cards use IntrinsicHeight
// around text that scales with the system font, which is the exact shape of
// the overflow bugs this project has shipped before.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/seller/marketplace_guidelines_screen.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

Future<void> _open(WidgetTester t, {double textScale = 1.0}) async {
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: const MarketplaceGuidelinesScreen(),
    ),
  ));
  await t.pump(const Duration(milliseconds: 400));
}

/// The footer's primary control.
InkWell _primaryButton(WidgetTester t, String label) => t.widget<InkWell>(
      find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first,
    );

void main() {
  for (final scale in <double>[1.0, 1.6, 2.5]) {
    testWidgets('lays out at ${scale}x text scale', (t) async {
      t.view.physicalSize = const Size(360, 720);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      await _open(t, textScale: scale);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('the whole document is reachable by scrolling', (t) async {
    t.view.physicalSize = const Size(360, 720);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await _open(t);

    // Consequences now sit AFTER the five commitments rather than opening
    // the screen, so they must still be reachable — a ban clause nobody can
    // scroll to is not a term anyone agreed to.
    await t.scrollUntilVisible(
      find.text('Violations = permanent ban'),
      280,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Violations = permanent ban'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('cannot continue without an explicit tick', (t) async {
    t.view.physicalSize = const Size(360, 720);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await _open(t);

    // Inert, and says so. The old build showed a faded "Continue to setup"
    // that gave no reason for doing nothing when tapped.
    expect(find.text('Tick to agree'), findsOneWidget);
    expect(find.text('Continue to setup'), findsNothing);
    expect(_primaryButton(t, 'Tick to agree').onTap, isNull);
  });

  testWidgets('ticking the box arms the button', (t) async {
    t.view.physicalSize = const Size(360, 720);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await _open(t);

    await t.scrollUntilVisible(
      find.textContaining('I have read and agree'),
      280,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.textContaining('I have read and agree'));
    await t.pumpAndSettle();

    expect(find.text('Continue to setup'), findsOneWidget);
    expect(find.text('Tick to agree'), findsNothing);
    expect(_primaryButton(t, 'Continue to setup').onTap, isNotNull);
  });

  testWidgets('the accepted version is a real, stampable string', (t) async {
    // This is what lands in sellers.terms_version, which is the only record
    // of WHICH rules a banned member agreed to. An empty string here would
    // pass every other test and quietly destroy the audit trail.
    expect(MarketplaceGuidelinesScreen.codeVersion, isNotEmpty);
    expect(MarketplaceGuidelinesScreen.codeVersion, matches(RegExp(r'^v\d')));
  });
}
