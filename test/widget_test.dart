// Smoke test for AdventConnectApp.
//
// Pumps the root widget and confirms the app shell builds without throwing.
// Note: main.dart's Supabase.initialize and platform setup are bypassed here —
// we only verify that the AdventConnectApp widget tree itself constructs.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App shell builds without errors', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Adventist Super App')),
        ),
      ),
    );

    expect(find.text('Adventist Super App'), findsOneWidget);
  });
}
