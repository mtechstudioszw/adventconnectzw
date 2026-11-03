import 'package:flutter/foundation.dart';

import '../premium_service.dart';
import 'billing_platform.dart';
import 'billing_service.dart';
import 'small_products.dart';

enum VerifiedPlanFlow {
  idle,
  loading,
  ready,
  unavailable,
  purchasing,
  pendingPayment,
  verifying,
  success,
  cancelled,
  failed,
}

/// The US$1/month Verified plan (patch 309): the gold tick, nothing else.
///
/// A subscription like Premium, so it is verified by the same
/// `verify-purchase` function — which now files it under
/// `profiles.verified_until`, never under Premium.
class VerifiedPlanService {
  VerifiedPlanService._();

  static final ValueNotifier<VerifiedPlanFlow> state = ValueNotifier(
    VerifiedPlanFlow.idle,
  );
  static String? message;
  static PremiumOffer? offer;

  static String get priceLabel =>
      offer?.price ?? SmallProducts.verifiedFallbackPrice;

  static Future<void> loadOffer() async {
    if (offer != null) {
      state.value = VerifiedPlanFlow.ready;
      return;
    }
    state.value = VerifiedPlanFlow.loading;
    message = null;
    final store = BillingService.platform;
    if (!await store.isAvailable()) {
      state.value = VerifiedPlanFlow.unavailable;
      message = 'This needs the Google Play Store.';
      return;
    }
    final offers = await store.loadOffers(SmallProducts.verifiedSku);
    if (offers.isEmpty) {
      state.value = VerifiedPlanFlow.unavailable;
      message = "The Verified plan isn't on sale yet. Check back soon.";
      return;
    }
    offer = offers.first;
    state.value = VerifiedPlanFlow.ready;
  }

  static Future<void> buy() async {
    if (offer == null) await loadOffer();
    final o = offer;
    if (o == null) return;
    BillingService.init();
    message = null;
    state.value = VerifiedPlanFlow.purchasing;
    final started = await BillingService.platform.buy(o);
    if (!started) {
      state.value = VerifiedPlanFlow.failed;
      message = "Couldn't open Google Play checkout. Please try again.";
    }
  }

  /// Called by [BillingService] for every Verified-plan purchase on Play's
  /// stream, including ones replayed after a crash.
  static Future<void> onPurchase(BillingPurchase purchase) async {
    switch (purchase.outcome) {
      case PurchaseOutcome.pending:
        state.value = VerifiedPlanFlow.pendingPayment;
        message = 'Your payment is clearing. The plan starts by itself.';
      case PurchaseOutcome.cancelled:
        state.value = VerifiedPlanFlow.cancelled;
      case PurchaseOutcome.error:
        state.value = VerifiedPlanFlow.failed;
        message = 'Google Play could not complete the purchase.';
      case PurchaseOutcome.purchased:
      case PurchaseOutcome.restored:
        state.value = VerifiedPlanFlow.verifying;
        final result = await BillingService.verifySubscription(purchase);
        if (!result.ok) {
          state.value = VerifiedPlanFlow.failed;
          message =
              result.message ??
              "We couldn't confirm that payment. If you were charged, it "
                  'is retried automatically.';
          return;
        }
        if (purchase.needsCompletion) {
          await BillingService.platform.completePurchase(purchase);
        }
        await PremiumService.refresh();
        state.value = VerifiedPlanFlow.success;
    }
  }
}
