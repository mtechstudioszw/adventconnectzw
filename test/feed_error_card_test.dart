// Home's feed used to show "Your feed starts here — follow a church" when
// the first page failed with nothing cached, telling a member with no
// signal that they had no friends. FeedErrorCard is what shows instead.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:advent_connect_zw/widgets/home/feed_error_card.dart';

Future<void> _pump(
  WidgetTester t, {
  required bool offline,
  VoidCallback? onRetry,
}) {
  t.view.physicalSize = const Size(360, 720);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  return t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: FeedErrorCard(offline: offline, onRetry: onRetry ?? () {}),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('offline says offline, never "your feed starts here"', (t) async {
    await _pump(t, offline: true);
    expect(find.text("You're offline"), findsOneWidget);
    expect(find.textContaining('Your feed starts here'), findsNothing);
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
  });

  testWidgets('online failure does not blame the connection', (t) async {
    await _pump(t, offline: false);
    expect(find.text("Couldn't load your feed"), findsOneWidget);
    expect(find.text("You're offline"), findsNothing);
  });

  testWidgets('Try again fires the retry', (t) async {
    var retries = 0;
    await _pump(t, offline: true, onRetry: () => retries++);
    await t.tap(find.text('Try again'));
    await t.pump();
    expect(retries, 1);
  });

  testWidgets('lays out at 2.0x text scale without overflow', (t) async {
    t.view.physicalSize = const Size(360, 720);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: FeedErrorCard(offline: true, onRetry: () {}),
            ),
          ),
        ),
      ),
    );
    expect(t.takeException(), isNull);
  });
}
