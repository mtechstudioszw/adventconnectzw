import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart'
    show SubscriptionOfferDetailsWrapper;
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

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

      // `.first` was correct only while the subscription had exactly one
      // base plan. `in_app_purchase` returns ONE ProductDetails PER BASE
      // PLAN, so the day an annual plan is added in Play Console this
      // picks whichever Play happened to return first — and a button
      // labelled "$3.00 / month" could start a $30.00 yearly purchase.
      //
      // loadOffers() below returns them all and the UI chooses. This
      // single-offer entry point stays for callers that only need "is
      // there anything to sell", and now deliberately prefers the
      // CHEAPEST plan so a mislabelled fallback can only ever undercharge.
      final all = response.productDetails.toList()
        ..sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
      final p = all.first;
      return PremiumOffer(
        productId: p.id,
        title: p.title,
        description: p.description,
        price: p.price,
        currencyCode: p.currencyCode,
        rawPrice: p.rawPrice,
        basePlanId: _basePlanId(p),
        native: p,
      );
    } catch (e) {
      debugPrint('PlayBilling.loadOffer threw: $e');
      return null;
    }
  }

  /// Every purchasable plan for [productId], cheapest first.
  ///
  /// A Play subscription may carry several base plans (monthly, annual,
  /// …) and `queryProductDetails` returns one entry for each. The plan
  /// picker needs all of them; anything that just needs a price can use
  /// [loadOffer].
  @override
  Future<List<PremiumOffer>> loadOffers(String productId) async {
    try {
      final response = await _iap.queryProductDetails({productId});
      if (response.error != null) {
        debugPrint('PlayBilling.loadOffers error: ${response.error}');
      }
      // One entry per BASE PLAN. Play returns one ProductDetails per
      // offer, so a plan with a free-trial offer comes back twice — once
      // plain, once with the trial. Keep the trial one: Play only returns
      // it to members eligible for it, and buying through it is what
      // actually starts the trial.
      final byPlan = <String, PremiumOffer>{};
      for (final p in response.productDetails) {
        final o = _toOffer(p);
        final key = o.basePlanId ?? o.productId;
        final had = byPlan[key];
        if (had == null || (had.trialPeriod == null && o.trialPeriod != null)) {
          byPlan[key] = o;
        }
      }
      return byPlan.values.toList()
        ..sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
    } catch (e) {
      debugPrint('PlayBilling.loadOffers threw: $e');
      return const [];
    }
  }

  /// Which base plan a returned offer belongs to.
  ///
  /// Since all three tiers are base plans on ONE product id (see
  /// [PremiumTier]), `p.id` is the same string for every plan and tells
  /// us nothing. `queryProductDetails` returns one [ProductDetails] per
  /// base plan, and on Android each is a [GooglePlayProductDetails]
  /// carrying the index of the offer it was built from — that is where
  /// the base plan id lives.
  ///
  /// Defensive at every step. This is the one place a plugin upgrade
  /// could quietly change shape, and the failure it would cause —
  /// everyone billed correctly by Play but granted the wrong tier by us
  /// — is exactly the kind that shows up as support tickets rather than
  /// as a crash. Null here means [BillingConfig.tierForBasePlan] falls
  /// back to the lowest paid tier.
  ///
  /// Note the price is NOT used to identify the plan. It is localised,
  /// it changes with a Play Console edit, and two plans can share one in
  /// a currency with big rounding — inferring entitlement from it would
  /// be a bug waiting for a promotion.
  PremiumOffer _toOffer(ProductDetails p) {
    var price = p.price;
    var rawPrice = p.rawPrice;
    String? trial;
    final offer = _offerDetails(p);
    final phases = offer?.pricingPhases ?? const [];
    if (phases.isNotEmpty) {
      // A trial is a FREE first phase; the last phase is what renews.
      if (phases.length > 1 && phases.first.priceAmountMicros == 0) {
        trial = phases.first.billingPeriod;
      }
      final recurring = phases.last;
      price = recurring.formattedPrice;
      rawPrice = recurring.priceAmountMicros / 1000000.0;
    }
    return PremiumOffer(
      productId: p.id,
      title: p.title,
      description: p.description,
      price: price,
      currencyCode: p.currencyCode,
      rawPrice: rawPrice,
      basePlanId: _basePlanId(p),
      trialPeriod: trial,
      native: p,
    );
  }

  SubscriptionOfferDetailsWrapper? _offerDetails(ProductDetails p) {
    if (p is! GooglePlayProductDetails) return null;
    final index = p.subscriptionIndex;
    final offers = p.productDetails.subscriptionOfferDetails;
    if (index == null || offers == null) return null;
    if (index < 0 || index >= offers.length) return null;
    return offers[index];
  }

  String? _basePlanId(ProductDetails p) {
    if (p is! GooglePlayProductDetails) return null;
    final index = p.subscriptionIndex;
    final offers = p.productDetails.subscriptionOfferDetails;
    if (index == null || offers == null) return null;
    if (index < 0 || index >= offers.length) return null;
    return offers[index].basePlanId;
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
  Future<bool> buyConsumable(PremiumOffer offer, {String? accountTag}) async {
    final details = offer.native;
    if (details is! ProductDetails) return false;
    try {
      // autoConsume OFF: the plugin would otherwise spend the purchase
      // the moment it arrives, before our server has granted the boost —
      // and a crash in between would take the member's money for nothing.
      return await _iap.buyConsumable(
        purchaseParam: PurchaseParam(
          productDetails: details,
          applicationUserName: accountTag,
        ),
        autoConsume: false,
      );
    } catch (e) {
      debugPrint('PlayBilling.buyConsumable threw: $e');
      return false;
    }
  }

  @override
  Future<void> consume(BillingPurchase purchase) async {
    final native = purchase.native;
    if (native is! PurchaseDetails) return;
    try {
      final addition = _iap
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      await addition.consumePurchase(native);
    } catch (e) {
      // Not money lost: the server already granted and acknowledged it.
      // It only blocks buying the same boost again until the next launch
      // replays it and this runs once more.
      debugPrint('PlayBilling.consume failed: $e');
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
