import 'package:advent_connect_zw/config/router_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Owner, 4 Nov 2026: "after sign up the keyboard still shows".
void main() {
  testWidgets('moving to a new screen closes the keyboard', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      navigatorObservers: [KeyboardDismissObserver()],
      home: const Scaffold(body: TextField(key: ValueKey('f'))),
    ));
    await tester.tap(find.byKey(const ValueKey('f')));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    nav.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('next')),
    ));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('a screen that asks for the keyboard still gets it',
      (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      navigatorObservers: [KeyboardDismissObserver()],
      home: const Scaffold(body: Text('start')),
    ));
    nav.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: TextField(autofocus: true)),
    ));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
  });
}
