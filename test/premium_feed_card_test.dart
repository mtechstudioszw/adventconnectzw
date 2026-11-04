import 'package:advent_connect_zw/services/billing/billing_platform.dart';
import 'package:advent_connect_zw/services/billing/premium_tier.dart';
import 'package:advent_connect_zw/services/feed_mixer.dart';
import 'package:advent_connect_zw/services/premium_promo_service.dart';
import 'package:advent_connect_zw/widgets/premium/feed_premium_card.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 4, 12);

  group('feed card rules', () {
    test('free member sees it from day one', () {
      expect(PremiumPromoService.feedCardFor(tier: PremiumTier.none, now: now),
          FeedPromo.goPremium);
    });
    test('Not now snoozes 3 days, then 10 after three refusals', () {
      final d2 = now.subtract(const Duration(days: 2));
      final d4 = now.subtract(const Duration(days: 4));
      expect(PremiumPromoService.feedCardFor(
              tier: PremiumTier.none, now: now, cardDismissed: d2, dismissals: 1),
          FeedPromo.none);
      expect(PremiumPromoService.feedCardFor(
              tier: PremiumTier.none, now: now, cardDismissed: d4, dismissals: 1),
          FeedPromo.goPremium);
      expect(PremiumPromoService.feedCardFor(
              tier: PremiumTier.none, now: now, cardDismissed: d4, dismissals: 3),
          FeedPromo.none);
    });
    test('Plus is offered Pro at most monthly; Pro and Business never', () {
      expect(PremiumPromoService.feedCardFor(tier: PremiumTier.plus, now: now),
          FeedPromo.upgradePro);
      expect(PremiumPromoService.feedCardFor(
              tier: PremiumTier.plus,
              now: now,
              upgradeDismissed: now.subtract(const Duration(days: 20))),
          FeedPromo.none);
      expect(PremiumPromoService.feedCardFor(tier: PremiumTier.pro, now: now),
          FeedPromo.none);
      expect(PremiumPromoService.feedCardFor(tier: PremiumTier.business, now: now),
          FeedPromo.none);
    });
  });

  test('promo sheet: weekly in the first month, fortnightly after', () {
    bool show(DateTime first, DateTime last) => PremiumPromoService.shouldShow(
          isPremium: false,
          route: '/home',
          isTyping: false,
          shownThisSession: false,
          now: now,
          lastShown: last,
          firstSeen: first,
        );
    final eightDaysAgo = now.subtract(const Duration(days: 8));
    expect(show(now.subtract(const Duration(days: 10)), eightDaysAgo), isTrue);
    expect(show(now.subtract(const Duration(days: 90)), eightDaysAgo), isFalse);
  });

  test('feed mixer places the card after the 4th post', () {
    final blocks = FeedMixer.mix(posts: 6, premiumAfterPost: 4);
    final i = blocks.indexWhere((b) => b.kind == FeedBlockKind.premium);
    final postsBefore =
        blocks.take(i).where((b) => b.kind == FeedBlockKind.post).length;
    expect(postsBefore, 4);
  });

  test('trial labels', () {
    expect(trialLabelFor('P7D'), '7-day');
    expect(trialLabelFor('P1W'), '1-week');
    expect(trialLabelFor('P2W'), '14-day');
    expect(trialLabelFor('P1M'), '1-month');
    expect(trialLabelFor('junk'), isNull);
    expect(trialDurationFor('P7D'), '7 days');
    expect(trialDurationFor('P1M'), '1 month');
  });

  test('pitches rotate daily', () {
    final a = FeedPremiumCard.pitchFor(DateTime(2026, 1, 1));
    final b = FeedPremiumCard.pitchFor(DateTime(2026, 1, 2));
    expect(a, isNot(b));
  });

  for (final kind in [FeedPromo.goPremium, FeedPromo.upgradePro]) {
    testWidgets('card renders without overflow: $kind', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: ListView(children: [FeedPremiumCard(kind: kind)])),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(FeedPremiumCard), findsOneWidget);
    });
  }
}
