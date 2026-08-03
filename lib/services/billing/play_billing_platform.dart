import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'billing_platform.dart';

/// Google Play, behind the [BillingPlatform] seam.
///
/// This is the ONLY file in the app that imports `in_app_purchase`. That
/// is deliberate: it is what lets StoreKit be added later as a sibling
/// file rather than a refactor, and what stops Play-specific concepts
/// leaking into the UI or the database.
class PlayBillingPlatform implements BillingPlatform {
  PlayBillingPlatform({InAppPurchase? iap})
      : _iap = iap ?? InAppPurchase.instance;

  final InAppPurchase _iap;

  @override
  BillingStore get store => BillingStore.googlePlay;

  @override
  Future<bool> isAvailable() async {
    // in_app_purchase has no Android-only guard of its own, and this app
    // ships Play-only billing for now. Anywhere else, billing is simply
    // absent — the Premium screen says so rather than failing oddly.
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await _iap.isAvailable();
    } catch (e) {
      debugPrint('PlayBilling.isAvailable failed: $e');
      return false;
    }
  }

  @override
  Future<PremiumOffer?> loadOffer(String productId) async {
    try {
      final response = await _iap.queryProductDetails({productId});
      if (response.error != null) {
        debugPrint('PlayBilling.loadOffer error: ${response.error}');
      }
      if (response.notFoundIDs.contains(productId)) {
        // Almost always a Play Console state problem rather than a code
        // one: product not created, base plan not activated, no regional
        // price set, or the build's applicationId/track can't see it.
        debugPrint(
          'PlayBilling: Play has no product "$productId". Check that the '
          'subscription exists AND its base plan is ACTIVE, and that this '
          'build is signed and on a track the account can buy from.',
        );
        return null;
      }
      if (response.productDetails.isEmpty) return null;

      final p = response.productDetails.first;
      return PremiumOffer(
        productId: p.id,
        title: p.title,
        description: p.description,
        price: p.price,
        currencyCode: p.currencyCode,
        rawPrice: p.rawPrice,
        native: p,
      );
    } catch (e) {
      debugPrint('PlayBilling.loadOffer threw: $e');
      return null;
    }
  }

  @override
  Future<bool> buy(PremiumOffer offer) async {
    final details = offer.native;
    if (details is! ProductDetails) return false;
    try {
      // A subscription is non-consumable: it is an entitlement that
      // persists, not something spent.
      return await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: details),
      );
    } catch (e) {
      debugPrint('PlayBilling.buy threw: $e');
      return false;
    }
  }

  @override
  Stream<List<BillingPurchase>> get purchaseUpdates =>
      _iap.purchaseStream.map(
        (list) => list.map(_toBillingPurchase).toList(growable: false),
      );

  @override
  Future<void> restorePurchases() => _iap.restorePurchases();

  @override
  Future<void> completePurchase(BillingPurchase purchase) async {
    final native = purchase.native;
    if (native is! PurchaseDetails) return;
    if (!native.pendingCompletePurchase) return;
    try {
      await _iap.completePurchase(native);
    } catch (e) {
      // Worth shouting about: an unacknowledged Play subscription is
      // auto-refunded after three days, so the user would silently lose
      // what they paid for.
      debugPrint('PlayBilling.completePurchase FAILED (refund risk): $e');
    }
  }

  BillingPurchase _toBillingPurchase(PurchaseDetails d) {
    final outcome = switch (d.status) {
      PurchaseStatus.purchased => PurchaseOutcome.purchased,
      PurchaseStatus.restored => PurchaseOutcome.restored,
      PurchaseStatus.pending => PurchaseOutcome.pending,
      PurchaseStatus.canceled => PurchaseOutcome.cancelled,
      PurchaseStatus.error => PurchaseOutcome.error,
    };
    return BillingPurchase(
      outcome: outcome,
      store: BillingStore.googlePlay,
      productId: d.productID,
      // On Play this is the purchase token — the handle the server gives
      // to the Play Developer API.
      verificationToken: d.verificationData.serverVerificationData,
      orderId: d.purchaseID,
      message: d.error?.message,
      native: d,
      needsCompletion: d.pendingCompletePurchase,
    );
  }

  @override
  void dispose() {}
}
