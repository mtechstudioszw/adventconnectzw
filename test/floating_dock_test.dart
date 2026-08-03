import 'package:advent_connect_zw/widgets/media/floating_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [FloatingDock] carries the music card and the Watch window (#8, #9).
///
/// Two things are worth pinning.
///
/// **It must not grow.** The card is placed at an explicit size inside an
/// explicit `Positioned`. The predecessor of this widget was an `Align`, and
/// an `Align` shrink-wraps only when the incoming constraint is unbounded —
/// inside an overlay it is bounded, so the child takes the whole screen. That
/// is precisely how a 50dp ad banner became a full-screen one three times
/// (`ad-banner-center-trap`), and a full-screen "mini" player would be the
/// same bug wearing a different hat.
///
/// **The parked anchor is owned by the caller.** These docks are mounted in a
/// rebuilding overlay, and the music one is unmounted entirely while the full
/// player is up. If the position lived in State it would reset to the default
/// every time you changed screens, which is worse than not being draggable.
void main() {
  const size = Size(190, 172);
  const screen = Size(400, 800);

  Future<void> pump(
    WidgetTester tester,
    ValueNotifier<Alignment> anchor, {
    List<Alignment> anchors = const [
      Alignment(0, -1),
      Alignment(0, 0),
      Alignment(0, 1),
    ],
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            FloatingDock(
              size: size,
              anchors: anchors,
              anchor: anchor,
              margin: const EdgeInsets.all(12),
              child: Container(
                key: const ValueKey('card'),
                color: const Color(0xFF0D1B3E),
              ),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('the card keeps its own size instead of filling the screen',
      (tester) async {
    await pump(tester, ValueNotifier(const Alignment(0, 1)));

    expect(tester.getSize(find.byKey(const ValueKey('card'))), size);
  });

  testWidgets('it parks where the anchor says', (tester) async {
    final anchor = ValueNotifier<Alignment>(const Alignment(0, 1));
    await pump(tester, anchor);

    final bottom = tester.getTopLeft(find.byKey(const ValueKey('card')));

    anchor.value = const Alignment(0, -1);
    await tester.pumpAndSettle();
    final top = tester.getTopLeft(find.byKey(const ValueKey('card')));

    expect(top.dy, lessThan(bottom.dy));
    // 12dp margin, per the pump() above.
    expect(top.dy, closeTo(12, 0.5));
    expect(
      bottom.dy,
      closeTo(screen.height - 12 - size.height, 0.5),
    );
  });

  testWidgets('dragging it upward re-parks it at a higher slot',
      (tester) async {
    final anchor = ValueNotifier<Alignment>(const Alignment(0, 1));
    await pump(tester, anchor);

    await tester.drag(
      find.byKey(const ValueKey('card')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    expect(
      anchor.value.y,
      lessThan(1),
      reason: 'a drag up must change the parked slot, not spring back',
    );
  });

  testWidgets('a released drag settles exactly onto an allowed slot',
      (tester) async {
    final anchor = ValueNotifier<Alignment>(const Alignment(0, 1));
    await pump(tester, anchor);

    // Nudge it a little way off its anchor and let go.
    await tester.drag(
      find.byKey(const ValueKey('card')),
      const Offset(0, -60),
    );
    await tester.pumpAndSettle();

    final at = tester.getTopLeft(find.byKey(const ValueKey('card')));
    const free = 800 - 24 - 172.0; // screen - vertical margin - card height
    final allowed = [12.0, 12 + free / 2, 12 + free];

    expect(
      allowed.any((slot) => (slot - at.dy).abs() < 0.5),
      isTrue,
      reason: 'the card must come to rest on a slot, never between two',
    );
  });
}
