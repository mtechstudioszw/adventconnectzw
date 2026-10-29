import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/admin/verification_review_screen.dart';
import 'package:advent_connect_zw/screens/premium/get_verified_screen.dart';
import 'package:advent_connect_zw/screens/premium/widgets/plan_perks_card.dart';
import 'package:advent_connect_zw/screens/premium/widgets/plan_picker.dart';
import 'package:advent_connect_zw/services/billing/billing_config.dart';
import 'package:advent_connect_zw/services/billing/billing_platform.dart';
import 'package:advent_connect_zw/services/billing/billing_service.dart';
import 'package:advent_connect_zw/services/billing/boost_catalog.dart';
import 'package:advent_connect_zw/widgets/premium/boost_sheet.dart';

import '../test/helpers/fake_supabase.dart';
import 'shot.dart';

PremiumOffer _offer(String plan, double price) => PremiumOffer(
  productId: BillingConfig.monthlyProductId,
  basePlanId: plan,
  title: 'Premium',
  description: plan,
  price: 'US\$${price.toStringAsFixed(2)}',
  currencyCode: 'USD',
  rawPrice: price,
);

final _offers = [
  _offer('monthly', 3),
  _offer('pro-monthly', 5),
  _offer('business-monthly', 10),
  _offer('annualpermanent', 30),
];

/// A store that sells a boost for US\$1, so the sheet renders its real
/// paid state without the Play plugin.
class _ShotStore implements BillingPlatform {
  @override
  BillingStore get store => BillingStore.googlePlay;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<PremiumOffer?> loadOffer(String productId) async => PremiumOffer(
    productId: productId,
    title: 'Boost',
    description: '',
    price: 'US\$1.00',
    currencyCode: 'USD',
    rawPrice: 1,
  );
  @override
  Future<List<PremiumOffer>> loadOffers(String productId) async => const [];
  @override
  Future<bool> buy(PremiumOffer offer) async => false;
  @override
  Future<bool> buyConsumable(PremiumOffer offer, {String? accountTag}) async =>
      false;
  @override
  Future<void> consume(BillingPurchase purchase) async {}
  @override
  Stream<List<BillingPurchase>> get purchaseUpdates => const Stream.empty();
  @override
  Future<void> restorePurchases() async {}
  @override
  Future<void> completePurchase(BillingPurchase purchase) async {}
  @override
  void dispose() {}
}

void main() {
  setUpAll(() async {
    await loadShotFonts();
    await initFakeSupabase((req) {
      final path = req.url.path;
      if (path.contains('verification_requests')) {
        if (req.url.query.contains('pending')) {
          return [
            {
              'id': 'a1',
              'user_id': 'u1',
              'kind': 'person',
              'legal_name': 'Tendai Moyo',
              'category': 'pastor',
              'status': 'pending',
              'created_at': '2026-10-28T10:00:00Z',
              'id_doc_path': 'u1/1_id.jpg',
              'selfie_path': 'u1/1_selfie.jpg',
              'profiles': {'full_name': 'Pastor T. Moyo'},
            },
          ];
        }
        return <Object>[];
      }
      return <Object>[];
    });
    await signInFake('00000000-0000-4000-8000-000000000001');
  });

  testWidgets('plans', (t) async {
    await pumpShot(
      t,
      Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              PlanPicker(
                offers: _offers,
                selected: _offers.last,
                onSelect: (_) {},
              ),
              const SizedBox(height: 12),
              const GoldTickPromoCard(),
            ],
          ),
        ),
      ),
      dark: false,
      size: const Size(412, 1100),
    );
    await saveShot(t, 'premium_plans');
  });

  testWidgets('get verified', (t) async {
    await pumpShot(t, const GetVerifiedScreen(), dark: false,
        size: const Size(412, 1500));
    await saveShot(t, 'get_verified');
  });

  testWidgets('admin review', (t) async {
    await pumpShot(t, const VerificationReviewScreen(), dark: true,
        size: const Size(412, 900));
    await saveShot(t, 'verify_admin');
  });

  testWidgets('boost sheet', (t) async {
    // ignore: invalid_use_of_visible_for_testing_member
    BillingService.debugConfigure(platform: _ShotStore());
    await pumpShot(
      t,
      const Scaffold(
        backgroundColor: Colors.transparent,
        body: Align(
          alignment: Alignment.bottomCenter,
          child: BoostSheet(
            kind: BoostKind.listing,
            targetId: 1,
            targetTitle: 'Solid wood dining table, 6 seater',
          ),
        ),
      ),
      dark: false,
      size: const Size(412, 700),
    );
    await saveShot(t, 'boost_sheet');
  });
}
