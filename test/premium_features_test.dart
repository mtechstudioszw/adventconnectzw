// Premium features (patch 289): the four levels, the gold tick's ID check,
// boosts, and the rule that none of it is reachable on iPhone yet.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/config/platform_flags.dart';
import 'package:advent_connect_zw/config/share_config.dart';
import 'package:advent_connect_zw/screens/premium/get_verified_screen.dart';
import 'package:advent_connect_zw/screens/premium/widgets/plan_picker.dart';
import 'package:advent_connect_zw/services/ai/ai_tiers.dart';
import 'package:advent_connect_zw/services/billing/billing_config.dart';
import 'package:advent_connect_zw/services/billing/billing_platform.dart';
import 'package:advent_connect_zw/services/billing/boost_catalog.dart';
import 'package:advent_connect_zw/services/billing/premium_tier.dart';
import 'package:advent_connect_zw/widgets/premium/boost_sheet.dart';

import 'helpers/fake_supabase.dart';

PremiumOffer _offer(String plan, double price) => PremiumOffer(
  productId: BillingConfig.monthlyProductId,
  basePlanId: plan,
  title: 'Premium',
  description: plan,
  price: 'US\$${price.toStringAsFixed(2)}',
  currencyCode: 'USD',
  rawPrice: price,
);

void main() {
  group('the levels', () {
    test('business parses and ranks above pro', () {
      expect(PremiumTier.parse('business'), PremiumTier.business);
      expect(PremiumTier.business.atLeast(PremiumTier.pro), isTrue);
      expect(PremiumTier.pro.atLeast(PremiumTier.business), isFalse);
    });

    test('each base plan grants the level it is sold as', () {
      expect(BillingConfig.tierForBasePlan('monthly'), PremiumTier.plus);
      expect(BillingConfig.tierForBasePlan('pro-monthly'), PremiumTier.pro);
      // The real yearly id — the one the database once didn't know.
      expect(BillingConfig.tierForBasePlan('annualpermanent'), PremiumTier.pro);
      expect(
        BillingConfig.tierForBasePlan('business-monthly'),
        PremiumTier.business,
      );
    });

    test('what each level buys matches patch 289', () {
      expect(TierBenefits.free.goldTick, isFalse);
      expect(TierBenefits.plus.goldTick, isTrue);
      expect(TierBenefits.plus.featuredShop, isFalse);
      const b = TierBenefits.business;
      expect(b.featuredShop, isTrue);
      expect(b.listingBoostsPerMonth, 4); // boost_credit_allowance('product')
      expect(b.jobBoostsPerMonth, 2); // boost_credit_allowance('job')
      expect(b.pageTick, isTrue);
      expect(b.aiQuestionsPerMonth, TierBenefits.pro.aiQuestionsPerMonth);
      expect(AiTiers.forPremiumTier(PremiumTier.business), AiTiers.pro);
    });
  });

  group('boost catalog', () {
    test('mirrors verify-boost', () {
      expect(BoostKind.forSku('boost_listing_7d'), BoostKind.listing);
      expect(BoostKind.forSku('boost_job_14d'), BoostKind.job);
      expect(BoostKind.isBoostSku('premium_monthly'), isFalse);
      expect(BoostKind.listing.days, 7);
      expect(BoostKind.job.days, 14);
      expect(BoostKind.job.accountTag(9), 'boost:j:9');
    });
  });

  group('plan picker with Business', () {
    testWidgets('yearly leads, Business sits last, and the saving is '
        'measured against Pro monthly — not the dearer Business plan', (
      t,
    ) async {
      final offers = [
        _offer('monthly', 3),
        _offer('pro-monthly', 5),
        _offer('business-monthly', 10),
        _offer('annualpermanent', 30),
      ];
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlanPicker(
                offers: offers,
                selected: offers.last,
                onSelect: (_) {},
              ),
            ),
          ),
        ),
      );
      final yearly = t.getTopLeft(find.text('Pro yearly')).dy;
      final business = t.getTopLeft(find.text('Business monthly')).dy;
      final plus = t.getTopLeft(find.text('Plus monthly')).dy;
      expect(yearly, lessThan(plus));
      expect(business, greaterThan(plus));
      // 12 − 30/5 = 6. Against Business it would have said 9.
      expect(find.text('6 months free'), findsOneWidget);
      expect(find.textContaining('Featured shop'), findsOneWidget);
      expect(find.textContaining('Gold tick after an ID check'), findsWidgets);
    });
  });

  group('iPhone shows no paid features', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('no ads and only App Store links on iPhone', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(kHideAds, isTrue);
      expect(appDownloadUrl, 'https://apps.apple.com/app/id6819068736');
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(kHideAds, isFalse);
      expect(appDownloadUrl, contains('play.google.com'));
    });

    test('payments are hidden on iOS only', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(kHidePayments, isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(kHidePayments, isFalse);
    });

    testWidgets('the boost sheet refuses to open on iOS', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      bool? opened;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => opened = await showBoostSheet(
                context,
                kind: BoostKind.listing,
                targetId: 1,
                targetTitle: 'Chair',
              ),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await t.tap(find.text('go'));
      await t.pump();
      expect(opened, isFalse);
      expect(find.byType(BoostSheet), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('get verified', () {
    setUpAll(() async {
      await initFakeSupabase((req) => <Object>[]);
      await signInFake('00000000-0000-4000-8000-000000000001');
    });

    testWidgets('sending needs a name, both photos and consent', (t) async {
      t.view.physicalSize = const Size(1080, 2800);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(const MaterialApp(home: GetVerifiedScreen()));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('What the gold tick means'), findsOneWidget);
      expect(find.byKey(const Key('verify-legal-name')), findsOneWidget);
      expect(find.byKey(const Key('verify-id-photo')), findsOneWidget);
      expect(find.byKey(const Key('verify-selfie')), findsOneWidget);

      await t.enterText(
        find.byKey(const Key('verify-legal-name')),
        'Tanatswa Mikuwa',
      );
      // The form's rule is what matters here, not hit-testing a tall
      // list in a test window: tick consent through its own handler.
      t
          .widget<CheckboxListTile>(find.byKey(const Key('verify-consent')))
          .onChanged!(true);
      await t.pump();
      expect(
        t.widget<CheckboxListTile>(find.byKey(const Key('verify-consent'))).value,
        isTrue,
      );
      // No photos yet: the button stays disabled.
      final button = t.widget<Opacity>(
        find
            .ancestor(
              of: find.text('Send for review'),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(button.opacity, lessThan(1));
    });
  });
}
