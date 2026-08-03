import 'package:advent_connect_zw/screens/quiz/arena/widgets/burst_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression, 3 Aug 2026.
///
/// `BurstLayer` held its Ticker in a lazy `late final`:
///
///     late final Ticker _ticker = createTicker(_onTick);
///
/// The field is only touched by `_onFire`, which runs when a burst is
/// actually fired — and the quiz only fires bursts on a CORRECT answer.
/// Back out of the arena without getting one right and the first touch is
/// `_ticker.dispose()` inside `dispose()`, so the ticker was CREATED
/// during disposal. `createTicker` reads TickerMode off the context, and
/// by then the element is deactivated:
///
///     Looking up a deactivated widget's ancestor is unsafe.
///
/// That aborts `dispose()` part-way, so everything after it is skipped —
/// which is how the quiz round screen came to leak its pending-advance
/// Timer and its animation controllers when a player left early. The
/// framework reports it and carries on, so nothing crashed and nothing
/// showed up in review.
Future<Object?> _mountThenUnmount(
  WidgetTester tester, {
  required bool fireABurst,
}) async {
  final controller = BurstController();
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: BurstLayer(controller: controller))),
  );
  await tester.pump();

  if (fireABurst) {
    controller.fire(const Offset(50, 50), count: 4);
    await tester.pump();
  }

  await tester.pumpWidget(const SizedBox.shrink());
  final error = tester.takeException();
  controller.dispose();
  return error;
}

void main() {
  testWidgets('tears down cleanly when no burst was ever fired', (
    tester,
  ) async {
    // The failing case: this is what leaving the arena without a correct
    // answer looks like, and it is the common one for a new player.
    expect(await _mountThenUnmount(tester, fireABurst: false), isNull);
  });

  testWidgets('tears down cleanly after a burst has fired', (tester) async {
    // Always passed, because firing forced the ticker into existence
    // while the element was still alive. Kept so the fix is pinned from
    // both sides.
    expect(await _mountThenUnmount(tester, fireABurst: true), isNull);
  });
}
