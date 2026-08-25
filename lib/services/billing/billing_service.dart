import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../premium_service.dart';
import 'billing_config.dart';
import 'billing_platform.dart';
import 'play_billing_platform.dart';
import 'premium_tier.dart';

/// Where the purchase flow currently is. The Premium screen renders
/// straight off this — there is no second copy of the truth.
enum PremiumFlowState {
  /// Nothing started yet.
  idle,

  /// Asking the store for the product + its localised price.
  loadingOffer,

  /// Price in hand, the button is live.
  ready,

  /// No billing here at all: not Android, no Play services, or Play has
  /// never heard of the product. The screen explains rather than
  /// showing a dead button.
  unavailable,

  /// The store's own sheet is up.
  purchasing,

  /// Paid out-of-band (cash, carrier billing) and not yet cleared. The
  /// user is NOT premium yet.
  pendingPayment,

  /// Money taken; the server is asking the store to confirm.
  verifying,

  /// Verified. Premium is live.
  success,

  /// The user backed out. Not an error.
  cancelled,

  /// Something went wrong. See [BillingService.errorMessage].
  failed,
}

/// Result of asking our server to verify a purchase with the store.
class VerificationResult {
  const VerificationResult({required this.ok, this.message});

  const VerificationResult.success() : ok = true, message = null;
  const VerificationResult.failure(this.message) : ok = false;

  final bool ok;
  final String? message;
}

/// Verifies a purchase server-side. Injectable so the whole flow can be
/// tested without a store or a network.
typedef PurchaseVerifier = Future<VerificationResult> Function(
    BillingPurchase purchase);

/// Drives the purchase flow and nothing else.
///
/// It never decides who is premium. It gets a token from the store,
/// hands it to the server, and if the server says yes it asks
/// [PremiumService] to re-read the truth. That ordering is the whole
/// security model: a client that can grant its own premium hasn't sold a
/// subscription, it has published a suggestion.
class BillingService {
  BillingService._();

  static BillingPlatform? _platform;
  static StreamSubscription<List<BillingPurchase>>? _sub;
  static PurchaseVerifier? _verifier;
  static bool _initialized = false;

  static final ValueNotifier<PremiumFlowState> state =
      ValueNotifier<PremiumFlowState>(PremiumFlowState.idle);

  /// The offer that will be purchased. Its [PremiumOffer.price] is the
  /// store's own localised string — always prefer it to any hardcoded
  /// label.
  ///
  /// With several base plans this is whichever the member SELECTED, so
  /// the price on the button and the price they are charged are the same
  /// object. It defaults to the cheapest, so any path that buys without
  /// an explicit choice can only ever undercharge.
  static PremiumOffer? offer;

  /// Every plan the store offers for this subscription, cheapest first.
  ///
  /// Empty until [loadOffer] runs, and length 1 until an annual base
  /// plan is activated in Play Console.
  static List<PremiumOffer> offers = const [];

  /// Bumps whenever the selected plan changes.
  ///
  /// The picker and the buy bar are separate widgets showing the same
  /// price, so they must rebuild together — a button reading "$3.00"
  /// while the picker shows Yearly selected is a mis-sold subscription
  /// waiting to happen. Both listen to this.
  static final ValueNotifier<int> planRevision = ValueNotifier<int>(0);

  /// Choose which plan [buy] will purchase.
  ///
  /// Deliberately the ONLY way to change [offer]. A screen that assigned
  /// to `offer` directly could set a plan the store never returned, and
  /// the purchase would fail with a message nobody could explain.
  ///
  /// Matched on the BASE PLAN as well as the price. With three plans on
  /// one product id, `productId + rawPrice` no longer identifies a plan
  /// — two plans could share a price after a Play Console edit or a
  /// rounding-heavy currency, and matching loosely would let a Pro
  /// selection resolve to the Plus offer object.
  static void selectPlan(PremiumOffer plan) {
    final known = offers.any((o) =>
        o.productId == plan.productId &&
        o.basePlanId == plan.basePlanId &&
        o.rawPrice == plan.rawPrice);
    if (!known) return;
    offer = plan;
    planRevision.value++;
  }

  /// The tier the currently selected plan would grant. [PremiumTier.plus]
  /// when nothing is selected yet — the lowest paid tier, so a label
  /// rendered a frame early can only ever under-promise.
  static PremiumTier get selectedTier =>
      BillingConfig.tierForBasePlan(offer?.basePlanId);

  /// Plain-English failure text, safe to show a user.
  static String? errorMessage;

  static BillingPlatform get _store => _platform ??= PlayBillingPlatform();

  static PurchaseVerifier get _verify => _verifier ??= _verifyWithServer;

  /// Wire up the purchase stream. Safe to call more than once.
  ///
  /// Must be running before any purchase is started, and ideally from
  /// app start: Play replays unfinished purchases through this stream,
  /// which is how a purchase interrupted by a crash or a flat battery
  /// still lands.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _sub = _store.purchaseUpdates.listen(
      _onPurchases,
      onError: (Object e) => debugPrint('purchaseStream error: $e'),
    );
  }

  /// Fetch the product and its localised price.
  static Future<void> loadOffer() async {
    state.value = PremiumFlowState.loadingOffer;
    errorMessage = null;

    if (!await _store.isAvailable()) {
      state.value = PremiumFlowState.unavailable;
      errorMessage = 'Subscriptions need the Google Play Store, which '
          "isn't available on this device.";
      return;
    }

    // Every base plan, not just one. A subscription with a monthly and
    // an annual plan returns two, and the picker needs both.
    final loaded = await _store.loadOffers(BillingConfig.monthlyProductId);
    if (loaded.isEmpty) {
      state.value = PremiumFlowState.unavailable;
      errorMessage = "Premium isn't available just yet. Please try again "
          'a little later.';
      return;
    }
    offers = loaded;

    // Default to the FEATURED plan — the annual one (founder's call,
    // 25 Aug 2026: tier 3 "should be selected by default" and carry the
    // promotion badge).
    //
    // This reverses a deliberate old default of "always the cheapest, so
    // an untouched picker cannot surprise anyone with a charge ten times
    // what they expected". That caution was right and is not being
    // waved away — it is satisfied differently now:
    //
    //   * the picker OPENS with the featured plan visibly selected and
    //     its price on the button, so the charge is never a surprise;
    //   * the buy bar reads the same `offer` object the picker shows
    //     (that is what `planRevision` is for), so the two cannot drift;
    //   * and at US$30 against US$5/month, the featured plan is the
    //     cheapest way to hold Pro for a year by a distance — so it is
    //     the honest recommendation as well as the profitable one.
    //
    // Falls back to the cheapest whenever the featured plan is not for
    // sale, which is the state of the world until the annual base plan
    // is created in Play Console.
    PremiumOffer chosen = loaded.reduce(
      (a, b) => a.rawPrice <= b.rawPrice ? a : b,
    );
    for (final o in loaded) {
      if (o.basePlanId == BillingConfig.featuredBasePlanId) {
        chosen = o;
        break;
      }
    }
    offer = chosen;
    planRevision.value++;
    state.value = PremiumFlowState.ready;
  }

  /// Open the store's purchase sheet.
  static Future<void> buy() async {
    final current = offer;
    if (current == null) {
      await loadOffer();
      if (offer == null) return;
    }
    errorMessage = null;
    state.value = PremiumFlowState.purchasing;
    final started = await _store.buy(offer!);
    if (!started) {
      // Couldn't even present the sheet — the result stream will never
      // fire, so fail here or the screen spins forever.
      state.value = PremiumFlowState.failed;
      errorMessage = "Couldn't open Google Play checkout. Please try again.";
    }
  }

  /// Replay an existing subscription onto this device.
  static Future<void> restore() async {
    errorMessage = null;
    state.value = PremiumFlowState.verifying;
    try {
      await _store.restorePurchases();
      // Results arrive on the stream. If nothing comes back the user
      // genuinely has no subscription on this Play account.
      Timer(const Duration(seconds: 6), () {
        if (state.value == PremiumFlowState.verifying &&
            !PremiumService.isActive) {
          state.value = PremiumFlowState.failed;
          errorMessage = 'No subscription found on this Google account.';
        }
      });
    } catch (e) {
      state.value = PremiumFlowState.failed;
      errorMessage = "Couldn't check for an existing subscription.";
    }
  }

  static Future<void> _onPurchases(List<BillingPurchase> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.outcome) {
        case PurchaseOutcome.pending:
          state.value = PremiumFlowState.pendingPayment;

        case PurchaseOutcome.cancelled:
          state.value = PremiumFlowState.cancelled;

        case PurchaseOutcome.error:
          state.value = PremiumFlowState.failed;
          errorMessage = 'Google Play could not complete the purchase.';
          debugPrint('Purchase error: ${purchase.message}');

        case PurchaseOutcome.purchased:
        case PurchaseOutcome.restored:
          await _entitle(purchase);
      }
    }
  }

  /// Verify with the server, then — and only then — acknowledge.
  static Future<void> _entitle(BillingPurchase purchase) async {
    // No receipt, no verification — true of every store, so it belongs
    // here rather than inside any one store's verifier.
    final token = purchase.verificationToken;
    if (token == null || token.isEmpty) {
      state.value = PremiumFlowState.failed;
      errorMessage = 'That purchase came back without a receipt. If you '
          'were charged, tap Restore.';
      return;
    }

    state.value = PremiumFlowState.verifying;

    final result = await _verify(purchase);

    if (!result.ok) {
      state.value = PremiumFlowState.failed;
      errorMessage = result.message ??
          "We couldn't confirm that payment. If you were charged, it will "
              'appear shortly — or tap Restore.';
      // Deliberately NOT completed. Leaving it unacknowledged means Play
      // replays it on the next launch and we get another chance; if it
      // truly never verifies, Play refunds the user automatically after
      // three days. Both outcomes beat quietly keeping their money.
      return;
    }

    // Verified. Tell the store we've delivered, or it refunds in 3 days.
    if (purchase.needsCompletion) {
      await _store.completePurchase(purchase);
    }

    // Re-read the server's truth rather than assuming. Ads disappear the
    // moment this lands.
    await PremiumService.refresh();
    state.value = PremiumFlowState.success;
  }

  /// The real verifier: hands the token to our Edge Function, which asks
  /// the store and writes `profiles.premium_until` with the service role.
  static Future<VerificationResult> _verifyWithServer(
      BillingPurchase purchase) async {
    final token = purchase.verificationToken;
    if (token == null || token.isEmpty) {
      return const VerificationResult.failure(
          'That purchase came back without a receipt.');
    }
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'verify-purchase',
        body: {
          'platform': purchase.store.id,
          'product_id': purchase.productId ?? BillingConfig.monthlyProductId,
          'purchase_token': token,
          'order_id': purchase.orderId,
        },
      );
      // Reaching here at all means the server answered 200. Every OTHER
      // status — 400, 401, 403, 409, 503 — makes functions.invoke() THROW
      // a FunctionException instead of returning it as data. So this
      // branch and the `already_claimed` check below it were dead code:
      // verify-purchase never returns ok:false with a 200, only ever a
      // real error status. Left brief for defensiveness, but the actual
      // error handling lives in the catch block now.
      final data = res.data;
      if (data is Map && data['ok'] == true) {
        return const VerificationResult.success();
      }
      return const VerificationResult.failure(null);
    } on FunctionException catch (e) {
      // The server WAS reached — it answered with a specific status and a
      // JSON body ({"ok": false, "error": "..."} — see verify-purchase's
      // `json()` helper). That is a fundamentally different situation
      // from a network failure, and conflating the two used to tell every
      // paying member "we couldn't reach the server" for errors that were
      // never about reachability at all. Found live 4 Aug 2026: a first
      // real purchase failed because the Android Publisher API wasn't
      // enabled in the Google Cloud project (a 503 from Play lookup
      // failing) — the member saw a generic network-sounding message for
      // what was actually "Google rejected our request to check your
      // purchase," which is a very different thing to be told.
      final body = e.details;
      final code = body is Map ? body['error']?.toString() : null;
      debugPrint('verify-purchase rejected: status=${e.status} error=$code');

      final message = switch (code) {
        'already_claimed' => 'That subscription is already linked to '
            'another Adventist Super App account.',
        'invalid_purchase' => "That purchase doesn't look valid to Google "
            'Play. If you were charged, tap Restore or contact support.',
        'unauthenticated' =>
          'Please sign in again, then try Restore from the Premium screen.',
        // 503 verification_unavailable: OUR server reached Play (or tried
        // to) and the attempt itself failed — an outage, a Play API
        // hiccup, a misconfiguration on our side. Distinct from "no
        // internet": the member's connection is fine, ours or Google's
        // had the problem. Unacknowledged, so Play will redeliver it — see
        // _entitle's comment on why NOT completing here is deliberate.
        'verification_unavailable' =>
          "Google Play didn't respond in time. If you were charged, this "
              'will resolve itself automatically the next time you open '
              'the app — no need to buy it again.',
        _ => "We couldn't confirm that payment (error $code). If you were "
            'charged, it will be retried automatically, or tap Restore.',
      };
      return VerificationResult.failure(message);
    } catch (e) {
      // A genuine network-layer failure — DNS, timeout, no connection —
      // is the ONLY case that reaches here now, so this message is
      // finally describing what actually happened.
      debugPrint('verify-purchase call failed (network): $e');
      return const VerificationResult.failure(
          "We couldn't reach the server to confirm that payment. It will "
          'be retried automatically.');
    }
  }

  static void reset() {
    errorMessage = null;
    state.value =
        PremiumService.isActive ? PremiumFlowState.success : PremiumFlowState.idle;
  }

  static Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _platform?.dispose();
    _initialized = false;
  }

  /// Test seam: swap in a fake store and a fake verifier.
  @visibleForTesting
  static void debugConfigure({
    BillingPlatform? platform,
    PurchaseVerifier? verifier,
  }) {
    _platform = platform;
    _verifier = verifier;
  }

  @visibleForTesting
  static Future<void> debugReset() async {
    await _sub?.cancel();
    _sub = null;
    _platform = null;
    _verifier = null;
    _initialized = false;
    offer = null;
    offers = const [];
    errorMessage = null;
    state.value = PremiumFlowState.idle;
  }
}
