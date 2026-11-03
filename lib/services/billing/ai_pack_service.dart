import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'billing_platform.dart';
import 'billing_service.dart';
import 'small_products.dart';

enum AiPackFlow {
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

/// US$1 for 50 Advent AI questions that never expire (patch 309). Granted
/// only by `verify-boost` after Google confirms the payment.
///
/// Never on sale while Advent AI itself is switched off on the server —
/// selling questions nobody can ask would be taking money for nothing.
class AiPackService {
  AiPackService._();

  static final ValueNotifier<AiPackFlow> state = ValueNotifier(AiPackFlow.idle);
  static String? message;
  static PremiumOffer? offer;

  /// Bumped after a pack lands, so balances refresh.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static SupabaseClient get _client => Supabase.instance.client;

  static String get priceLabel =>
      offer?.price ?? SmallProducts.aiPackFallbackPrice;

  /// Is Advent AI actually answering right now? Read from the server's
  /// own balance check, which says `service_suspended` when it is not.
  static Future<bool> aiIsLive() async {
    try {
      final rows = await _client.rpc('ai_my_balance');
      final row = rows is List && rows.isNotEmpty ? rows.first : rows;
      if (row is Map) return row['reason'] != 'service_suspended';
    } catch (_) {}
    return false;
  }

  static Future<void> loadOffer() async {
    state.value = AiPackFlow.loading;
    message = null;
    if (!await aiIsLive()) {
      state.value = AiPackFlow.unavailable;
      message = 'Advent AI is resting right now, so questions are not on sale.';
      return;
    }
    final store = BillingService.platform;
    if (!await store.isAvailable()) {
      state.value = AiPackFlow.unavailable;
      message = 'This needs the Google Play Store.';
      return;
    }
    offer = await store.loadOffer(SmallProducts.aiPackSku);
    if (offer == null) {
      state.value = AiPackFlow.unavailable;
      message = "Question packs aren't on sale yet. Check back soon.";
      return;
    }
    state.value = AiPackFlow.ready;
  }

  static Future<void> buy() async {
    final o = offer;
    if (o == null) return;
    BillingService.init();
    message = null;
    state.value = AiPackFlow.purchasing;
    final started = await BillingService.platform.buyConsumable(o);
    if (!started) {
      state.value = AiPackFlow.failed;
      message = "Couldn't open Google Play checkout. Please try again.";
    }
  }

  static Future<void> onPurchase(BillingPurchase purchase) async {
    switch (purchase.outcome) {
      case PurchaseOutcome.pending:
        state.value = AiPackFlow.pendingPayment;
        message = 'Your payment is clearing. The questions are added then.';
      case PurchaseOutcome.cancelled:
        state.value = AiPackFlow.cancelled;
      case PurchaseOutcome.error:
        state.value = AiPackFlow.failed;
        message = 'Google Play could not complete the purchase.';
      case PurchaseOutcome.purchased:
      case PurchaseOutcome.restored:
        await _grant(purchase);
    }
  }

  static Future<void> _grant(BillingPurchase purchase) async {
    state.value = AiPackFlow.verifying;
    final token = purchase.verificationToken;
    if (token == null || token.isEmpty) {
      state.value = AiPackFlow.failed;
      return;
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
      if (data is! Map || data['ok'] != true) {
        state.value = AiPackFlow.failed;
        return;
      }
    } catch (e) {
      debugPrint('verify-boost (AI pack) failed: $e');
      state.value = AiPackFlow.failed;
      message =
          "We couldn't confirm that payment yet. It is retried "
          'automatically, or refunded by Google within 3 days.';
      // Not consumed: Play replays it next launch, or refunds it.
      return;
    }
    await BillingService.platform.consume(purchase);
    state.value = AiPackFlow.success;
    revision.value++;
  }
}
