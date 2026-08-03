// Render test for the Premium screen.
//
// It has two completely different faces — the pitch and the "you're
// already subscribed" view — and the pitch quotes a real ad count back
// at the user, which is a number that comes from disk. Both faces are
// rendered here at 1.0x / 1.6x / 2.5x system text on a 360dp phone,
// because a fixed-height box holding wrappable text is this project's
// most repeated overflow, and at 2.5x it fails silently.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/premium/premium_screen.dart';
import 'package:advent_connect_zw/services/ads/ad_impression_counter.dart';
import 'package:advent_connect_zw/services/billing/billing_service.dart';
import 'package:advent_connect_zw/services/premium_service.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

Future<void> _pump(
  WidgetTester t, {
  double textScale = 1.0,
  ThemeData? theme,
}) async {
  await t.pumpWidget(MaterialApp(
    theme: theme ?? AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(360, 780),
        textScaler: TextScaler.linear(textScale),
      ),
      // autoLoad: false keeps Supabase and the Play Store out of it —
      // the constructor seam this project uses for exactly this.
      child: const PremiumScreen(autoLoad: false),
    ),
  ));
  // StaggeredReveal arms a delay timer per card and the ad counter
  // animates up, so settle rather than pump — a bare pump leaves those
  // timers pending and the teardown fails on them.
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    PremiumService.debugReset();
    await BillingService.debugReset();
    AdImpressionCounter.debugSet(count: 0);
  });

  tearDown(() async {
    PremiumService.debugReset();
    await BillingService.debugReset();
    AdImpressionCounter.debugSet(count: 0);
  });

  group('the pitch', () {
    testWidgets('renders for a free user', (t) async {
      await _pump(t);
      expect(find.text('Go Premium'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('quotes the real ad count once there is one worth quoting',
        (t) async {
      AdImpressionCounter.debugSet(count: 214);
      await _pump(t);
      // The counter animates up from zero, so settle before reading it.
      await t.pumpAndSettle();
      expect(find.text('214'), findsOneWidget);
      expect(find.textContaining('ads shown to you'), findsOneWidget);
    });

    testWidgets('shows no hollow zero on a fresh install', (t) async {
      // A brand-new user has seen nothing. "0 ads shown to you" would be
      // both useless and faintly absurd, so the copy switches instead.
      AdImpressionCounter.debugSet(count: 0);
      await _pump(t);
      await t.pumpAndSettle();
      expect(find.text('0'), findsNothing);
      expect(
        find.text('Read, watch and pray without interruption'),
        findsOneWidget,
      );
    });

    testWidgets('offers a way out that is one clear tap', (t) async {
      await _pump(t);
      expect(find.text('Keep watching ads for now'), findsOneWidget);
    });
  });

  group('already subscribed', () {
    testWidgets('shows the renewal date, not the pitch', (t) async {
      PremiumService.debugSet(premium: true);
      await _pump(t);
      expect(find.text('Your Premium'), findsOneWidget);
      expect(find.text('Premium is active'), findsOneWidget);
      expect(find.text('Keep watching ads for now'), findsNothing);
    });

    testWidgets('swaps face the moment a purchase lands', (t) async {
      await _pump(t);
      expect(find.text('Go Premium'), findsOneWidget);

      PremiumService.debugSet(premium: true);
      await t.pumpAndSettle();

      expect(find.text('Premium is active'), findsOneWidget);
    });
  });

  group('text scaling on a 360dp phone', () {
    for (final scale in const [1.0, 1.6, 2.5]) {
      testWidgets('the pitch survives ${scale}x', (t) async {
        AdImpressionCounter.debugSet(count: 214);
        await _pump(t, textScale: scale);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });

      testWidgets('the active view survives ${scale}x', (t) async {
        PremiumService.debugSet(premium: true);
        await _pump(t, textScale: scale);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });

  testWidgets('renders in dark mode', (t) async {
    AdImpressionCounter.debugSet(count: 214);
    await _pump(t, theme: AppTheme.dark);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
