import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'billing_platform.dart';
import 'billing_service.dart';
import 'boost_catalog.dart';

/// Where a boost purchase is. The boost sheet renders straight off this.
enum BoostFlow {
  idle,
  loading,

  /// Price in hand.
  ready,

  /// No Play billing here, or the SKU isn't live in Play Console yet.
  unavailable,
  purchasing,

  /// Paid by a method that clears later (cash, carrier billing).
  pendingPayment,
  verifying,
  success,
  cancelled,
  failed,
}

/// Monthly Business credits still unspent (patch 289).
typedef BoostCredits = ({int listing, int job, DateTime? resetsAt});

/// Server-side confirmation of a bought boost. Injectable for tests.
typedef BoostVerifier =
    Future<({bool ok, DateTime? endsAt, String? message})> Function(
      BillingPurchase purchase,
      int? targetId,
    );

/// Boosts: pay to put a listing or a job in front of more people
/// (owner, 29 Oct 2026: "you pay something for your store to be picked,
/// your products to be at the top").
///
/// Same security model as Premium: this class gets a token from Play and
/// hands it to `verify-boost`; only the server can feature anything.
/// Business members can also spend a monthly credit instead of paying.
class BoostService {
  BoostService._();

  static final ValueNotifier<BoostFlow> state = ValueNotifier(BoostFlow.idle);

  /// Plain-English text for the current state, safe to show.
  static String? message;

  /// When the last granted boost ends.
  static DateTime? lastEndsAt;

  /// Bumped after any boost lands, so listings refresh their badge.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static final Map<BoostKind, PremiumOffer> _offers = {};

  /// The listing or job the member is paying for right now. Play also
  /// carries it in the purchase's account tag, which is what the server
  /// believes — this is only the fallback.
  static int? _pendingTarget;

  static BoostVerifier? _verifier;
  static BoostVerifier get _verify => _verifier ??= _verifyWithServer;

  static SupabaseClient get _client => Supabase.instance.client;

  static PremiumOffer? offerFor(BoostKind kind) => _offers[kind];

  /// Fetch the localised price. Leaves [state] at `unavailable` when Play
  /// can't sell it here — the sheet then offers credits only.
  static Future<PremiumOffer?> loadOffer(BoostKind kind) async {
    state.value = BoostFlow.loading;
    message = null;
    final store = BillingService.platform;
    if (!await store.isAvailable()) {
      state.value = BoostFlow.unavailable;
      message = 'Buying boosts needs the Google Play Store.';
      return null;
    }
    final offer = await store.loadOffer(kind.sku);
    if (offer == null) {
      state.value = BoostFlow.unavailable;
      message = "Paid boosts aren't on sale yet. Check back soon.";
      return null;
    }
    _offers[kind] = offer;
    state.value = BoostFlow.ready;
    return offer;
  }

  /// Open Play's purchase sheet for [kind] on [targetId].
  static Future<void> buy(BoostKind kind, int targetId) async {
    final offer = _offers[kind] ?? await loadOffer(kind);
    if (offer == null) return;
    BillingService.init();
    _pendingTarget = targetId;
    message = null;
    state.value = BoostFlow.purchasing;
    final started = await BillingService.platform.buyConsumable(
      offer,
      accountTag: kind.accountTag(targetId),
    );
    if (!started) {
      state.value = BoostFlow.failed;
      message = "Couldn't open Google Play checkout. Please try again.";
    }
  }

  /// Called by [BillingService] for every boost purchase on Play's stream
  /// — new ones and ones replayed after a crash.
  static Future<void> onPurchase(BillingPurchase purchase) async {
    switch (purchase.outcome) {
      case PurchaseOutcome.pending:
        state.value = BoostFlow.pendingPayment;
        message = 'Your payment is clearing. The boost starts by itself '
            'when it does.';
      case PurchaseOutcome.cancelled:
        state.value = BoostFlow.cancelled;
      case PurchaseOutcome.error:
        state.value = BoostFlow.failed;
        message = 'Google Play could not complete the purchase.';
      case PurchaseOutcome.purchased:
      case PurchaseOutcome.restored:
        await _grant(purchase);
    }
  }

  static Future<void> _grant(BillingPurchase purchase) async {
    state.value = BoostFlow.verifying;
    final result = await _verify(purchase, _pendingTarget);
    if (!result.ok) {
      state.value = BoostFlow.failed;
      message = result.message ??
          "We couldn't confirm that payment. If you were charged, it is "
              'retried automatically — or refunded by Google within 3 days.';
      // Not consumed: Play replays it on the next launch, and refunds it
      // by itself if it never verifies.
      return;
    }
    // Granted and acknowledged by the server. Spend it so the same boost
    // can be bought again.
    await BillingService.platform.consume(purchase);
    _pendingTarget = null;
    lastEndsAt = result.endsAt;
    state.value = BoostFlow.success;
    revision.value++;
  }

  /// Spend a Business credit on [targetId]. Throws a readable message.
  static Future<DateTime?> useCredit(BoostKind kind, int targetId) async {
    try {
      final res = await _client.rpc('use_boost_credit', params: {
        'p_target_type': kind.targetType,
        'p_target_id': targetId,
      });
      final ends = DateTime.tryParse('$res')?.toLocal();
      lastEndsAt = ends;
      revision.value++;
      return ends;
    } on PostgrestException catch (e) {
      throw Exception(_friendly(e));
    }
  }

  /// Business credits left this month. All zero for everyone else, and
  /// before patch 289 runs.
  static Future<BoostCredits> creditsLeft() async {
    try {
      final rows = await _client.rpc('boost_credits_left');
      final row = rows is List && rows.isNotEmpty ? rows.first : rows;
      if (row is Map) {
        return (
          listing: (row['product_left'] as num?)?.toInt() ?? 0,
          job: (row['job_left'] as num?)?.toInt() ?? 0,
          resetsAt: DateTime.tryParse('${row['resets_at']}')?.toLocal(),
        );
      }
    } catch (e) {
      debugPrint('boost_credits_left failed: $e');
    }
    return (listing: 0, job: 0, resetsAt: null);
  }

  /// When the current boost on a listing or job ends, if it has one.
  static Future<DateTime?> activeUntil(BoostKind kind, int targetId) async {
    try {
      final rows = await _client
          .from('boosts')
          .select('ends_at')
          .eq('target_type', kind.targetType)
          .eq('target_id', targetId)
          .gt('ends_at', DateTime.now().toUtc().toIso8601String())
          .order('ends_at', ascending: false)
          .limit(1);
      final list = rows as List;
      if (list.isEmpty) return null;
      return DateTime.tryParse('${list.first['ends_at']}')?.toLocal();
    } catch (_) {
      return null;
    }
  }

  static Future<({bool ok, DateTime? endsAt, String? message})>
  _verifyWithServer(BillingPurchase purchase, int? targetId) async {
    final token = purchase.verificationToken;
    if (token == null || token.isEmpty) {
      return (ok: false, endsAt: null, message: null);
    }
    try {
      final res = await _client.functions.invoke(
        'verify-boost',
        body: {
          'platform': purchase.store.id,
          'product_id': purchase.productId,
          'purchase_token': token,
          'target_id': ?targetId,
        },
      );
      final data = res.data;
      if (data is Map && data['ok'] == true) {
        return (
          ok: true,
          endsAt: DateTime.tryParse('${data['ends_at']}')?.toLocal(),
          message: null,
        );
      }
      return (ok: false, endsAt: null, message: null);
    } on FunctionException catch (e) {
      final body = e.details;
      final code = body is Map ? body['error']?.toString() : null;
      debugPrint('verify-boost rejected: status=${e.status} error=$code');
      return (
        ok: false,
        endsAt: null,
        message: switch (code) {
          'not_owner' => 'That listing isn\'t yours, so it can\'t be boosted. '
              'Google will refund you within 3 days.',
          'not_live' => 'That listing is no longer live, so it can\'t be '
              'boosted. Google will refund you within 3 days.',
          'pending' => 'Your payment is still clearing.',
          'verification_unavailable' => "Google Play didn't answer in time. "
              "It will be retried — you won't be charged twice.",
          _ => null,
        },
      );
    } catch (e) {
      debugPrint('verify-boost failed (network): $e');
      return (
        ok: false,
        endsAt: null,
        message: "We couldn't reach the server. It will be retried "
            'automatically.',
      );
    }
  }

  static String _friendly(PostgrestException e) {
    final t = '${e.message} ${e.hint ?? ''}';
    if (t.contains('BOOST_NO_CREDITS')) {
      return "This month's boosts are used up. They refill on the 1st.";
    }
    if (t.contains('BOOST_NEEDS_BUSINESS')) {
      return 'Monthly boosts come with Business.';
    }
    if (t.contains('BOOST_NOT_LIVE')) {
      return 'Only a live listing can be boosted.';
    }
    if (t.contains('BOOST_NOT_OWNER')) {
      return 'You can only boost your own listings.';
    }
    return "That didn't work. Please try again.";
  }

  /// Back to idle when a boost sheet opens, so it doesn't show the last
  /// sheet's success or error.
  static void resetFlow() {
    message = null;
    state.value = BoostFlow.idle;
  }

  @visibleForTesting
  static void debugConfigure({BoostVerifier? verifier}) =>
      _verifier = verifier;

  @visibleForTesting
  static void debugReset() {
    _verifier = null;
    _offers.clear();
    _pendingTarget = null;
    lastEndsAt = null;
    message = null;
    state.value = BoostFlow.idle;
  }
}
