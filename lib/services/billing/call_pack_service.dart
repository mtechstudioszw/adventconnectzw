import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'billing_platform.dart';
import 'billing_service.dart';
import 'call_pack_catalog.dart';

/// Where a minute-pack purchase is. The pack sheet renders off this.
enum CallPackFlow {
  idle,
  loading,
  ready,

  /// No Play billing here, or the products aren't live in Play Console.
  unavailable,
  purchasing,
  pendingPayment,
  verifying,
  success,
  cancelled,
  failed,
}

/// Buying extra call minutes (patch 305). Same security model as boosts:
/// this class only gets a token from Play and hands it to `verify-boost`;
/// only the server can add minutes, after Google confirms the payment.
class CallPackService {
  CallPackService._();

  static final ValueNotifier<CallPackFlow> state = ValueNotifier(
    CallPackFlow.idle,
  );

  /// Plain-English text for the current state, safe to show.
  static String? message;

  /// Minutes granted by the last successful purchase.
  static int? lastMinutes;

  /// Bumped after a pack lands, so minute counters refresh.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static final Map<CallPack, PremiumOffer> _offers = {};

  static SupabaseClient get _client => Supabase.instance.client;

  static PremiumOffer? offerFor(CallPack pack) => _offers[pack];

  /// Fetch both packs' localised prices.
  static Future<void> loadOffers() async {
    state.value = CallPackFlow.loading;
    message = null;
    final store = BillingService.platform;
    if (!await store.isAvailable()) {
      state.value = CallPackFlow.unavailable;
      message = 'Buying minutes needs the Google Play Store.';
      return;
    }
    for (final p in CallPack.values) {
      final offer = await store.loadOffer(p.sku);
      if (offer != null) _offers[p] = offer;
    }
    if (_offers.isEmpty) {
      state.value = CallPackFlow.unavailable;
      message = "Minute packs aren't on sale yet. Check back soon.";
      return;
    }
    state.value = CallPackFlow.ready;
  }

  /// Open Play's purchase sheet for [pack].
  static Future<void> buy(CallPack pack) async {
    final offer = _offers[pack];
    if (offer == null) return;
    BillingService.init();
    message = null;
    state.value = CallPackFlow.purchasing;
    final started = await BillingService.platform.buyConsumable(
      offer,
      accountTag: CallPack.accountTag,
    );
    if (!started) {
      state.value = CallPackFlow.failed;
      message = "Couldn't open Google Play checkout. Please try again.";
    }
  }

  /// Called by [BillingService] for every pack purchase on Play's stream —
  /// new ones and ones replayed after a crash.
  static Future<void> onPurchase(BillingPurchase purchase) async {
    switch (purchase.outcome) {
      case PurchaseOutcome.pending:
        state.value = CallPackFlow.pendingPayment;
        message =
            'Your payment is clearing. The minutes are added by themselves '
            'when it does.';
      case PurchaseOutcome.cancelled:
        state.value = CallPackFlow.cancelled;
      case PurchaseOutcome.error:
        state.value = CallPackFlow.failed;
        message = 'Google Play could not complete the purchase.';
      case PurchaseOutcome.purchased:
      case PurchaseOutcome.restored:
        await _grant(purchase);
    }
  }

  static Future<void> _grant(BillingPurchase purchase) async {
    state.value = CallPackFlow.verifying;
    final result = await _verify(purchase);
    if (!result.ok) {
      state.value = CallPackFlow.failed;
      message =
          result.message ??
          "We couldn't confirm that payment. If you were charged, it is "
              'retried automatically — or refunded by Google within 3 days.';
      // Not consumed: Play replays it next launch, or refunds it.
      return;
    }
    await BillingService.platform.consume(purchase);
    lastMinutes = result.minutes;
    state.value = CallPackFlow.success;
    revision.value++;
  }

  static Future<({bool ok, int? minutes, String? message})> _verify(
    BillingPurchase purchase,
  ) async {
    final token = purchase.verificationToken;
    if (token == null || token.isEmpty) {
      return (ok: false, minutes: null, message: null);
    }
    try {
      final res = await _client.functions.invoke(
        'verify-boost',
        body: {
          'platform': purchase.store.id,
          'product_id': purchase.productId,
          'purchase_token': token,
        },
      );
      final data = res.data;
      if (data is Map && data['ok'] == true) {
        return (
          ok: true,
          minutes: (data['minutes'] as num?)?.toInt(),
          message: null,
        );
      }
      return (ok: false, minutes: null, message: null);
    } on FunctionException catch (e) {
      final body = e.details;
      final code = body is Map ? body['error']?.toString() : null;
      debugPrint('verify-boost (pack) rejected: ${e.status} $code');
      return (
        ok: false,
        minutes: null,
        message: switch (code) {
          'pending' => 'Your payment is still clearing.',
          'verification_unavailable' =>
            "Google Play didn't answer in time. It will be retried — you "
                "won't be charged twice.",
          _ => null,
        },
      );
    } catch (e) {
      debugPrint('verify-boost (pack) failed: $e');
      return (
        ok: false,
        minutes: null,
        message:
            "We couldn't reach the server. It will be retried automatically.",
      );
    }
  }
}
