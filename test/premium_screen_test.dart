// Render test for the Premium screen.
//
// It has two completely different faces â€” the pitch and the "you're
// already subscribed" view â€” and the pitch quotes a real ad count back
// at the user, which is a number that comes from disk. Both faces are
// rendered here at 1.0x / 1.6x / 2.5x system text on a 360dp phone,
// because a fixed-height box holding wrappable text is this project's
// most repeated overflow, and at 2.5x it fails silently.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/premium/premium_screen.dart';
import 'package:advent_connect_zw/services/ads/ad_impression_counter.dart';
import 'package:advent_connect_zw/services/billing/billing_service.dart';
import 'package:advent_connect_zw/services/ai/ai_tiers.dart';
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
      // autoLoad: false keeps Supabase and the Play Store out of it â€”
      // the constructor seam this project uses for exactly this.
      child: const PremiumScreen(autoLoad: false),
    ),
  ));
  // StaggeredReveal arms a delay timer per card and the ad counter
  // animates up, so settle rather than pump â€” a bare pump leaves those
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

    testWidgets('leads with Advent AI, not with ad removal', (t) async {
      // The screen was rebuilt (23 Aug 2026) around a POSITIVE benefit.
      // Premium's whole pitch used to be the absence of advertising â€”
      // "pay us and we will stop doing this to you" â€” which is a weak
      // offer and, in a church app, an off-putting one. Advent AI is the
      // first thing Premium has ever had that a member actually WANTS,
      // so it is what they see first.
      await _pump(t);
      await t.pumpAndSettle();

      // Advent AI is the FIRST card, so it is on screen without
      // scrolling â€” that is the whole point of the reordering.
      expect(find.text('Advent AI'), findsWidgets);
      expect(
        find.textContaining('${AiTiers.premium.monthlyMessages}'),
        findsWidgets,
        reason: 'the Premium allowance is the headline number',
      );
    });

    testWidgets('shows a worked example rather than a claim', (t) async {
      // Every other line on a paywall is an assertion about how good the
      // thing is. A real exchange is evidence, and it is the reason this
      // card converts at all.
      await _pump(t);
      await t.pumpAndSettle();
      expect(
        find.textContaining('Matthew 11:28'),
        findsOneWidget,
        reason: 'the sample answer quotes a real verse',
      );
    });

    testWidgets('the ad count still appears, but no longer leads',
        (t) async {
      // Not deleted â€” a real number of ads someone has sat through is
      // honest and worth saying. It just is not the opening argument any
      // more, so it now sits BELOW the fold and the test has to scroll
      // to reach it. That scroll is the assertion: if this card ever
      // creeps back to the top, the test starts passing without one.
      AdImpressionCounter.debugSet(count: 214);
      await _pump(t);
      await t.pumpAndSettle();

      expect(
        find.textContaining('ads shown to you'),
        findsNothing,
        reason: 'ad guilt must not be the first thing a member reads',
      );

      await t.scrollUntilVisible(
        find.textContaining('ads shown to you'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(find.textContaining('ads shown to you'), findsOneWidget);
    });

    testWidgets('declining never shames the member', (t) async {
      // This used to read "Keep watching ads for now", which makes the
      // member say something unpleasant about themselves in order to
      // refuse. That is confirmshaming, and the brief bans dark
      // patterns. Plainly "Not now".
      await _pump(t);
      expect(find.text('Not now'), findsOneWidget);
      expect(
        find.text('Keep watching ads for now'),
        findsNothing,
        reason: 'the confirmshaming decline must not come back',
      );
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

