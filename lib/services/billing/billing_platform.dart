/// The seam between the app and whichever store it happens to be
/// running on.
///
/// Google Play is the only implementation today. iOS is explicitly out
/// of scope until the founder has a Mac and an Apple Developer account —
/// but nothing above this file knows that. When StoreKit arrives it
/// implements [BillingPlatform] and the UI, the state machine and the
/// Supabase schema all stay exactly as they are.
///
/// The rule that keeps this honest: **nothing in this directory ever
/// grants premium**. A purchase here produces a [BillingPurchase] with a
/// token; only the server, having asked the store, may turn that into
/// `profiles.premium_until`.
library;

/// Which store a purchase came from. Matches the `platform` column in
/// `public.subscriptions` exactly.
enum BillingStore {
  googlePlay('google_play'),
  appStore('app_store');

  const BillingStore(this.id);

  /// The value written to the database.
  final String id;
}

/// A purchasable subscription, with the store's own localised price.
///
/// Never format a price yourself: the store returns it already localised
/// and in the user's currency, and a hand-built "US$3.00" would be wrong
/// for most of the world and illegal to display in some of it.
class PremiumOffer {
  const PremiumOffer({
    required this.productId,
    required this.title,
    required this.description,
    required this.price,
    required this.currencyCode,
    required this.rawPrice,
    this.native,
  });

  final String productId;
  final String title;
  final String description;

  /// Localised, ready to display, e.g. "US$3.00" or "R55,00".
  final String price;
  final String currencyCode;
  final double rawPrice;

  /// The underlying store object, opaque above this layer. The platform
  /// implementation needs it back to start a purchase.
  final Object? native;
}

/// What happened to a purchase attempt.
enum PurchaseOutcome {
  /// Paid and ready to verify.
  purchased,

  /// The store replayed an existing entitlement (restore, reinstall, new
  /// device). Also needs verifying — it is the same token.
  restored,

  /// Awaiting an out-of-band payment. Common in Zimbabwe: cash, carrier
  /// billing and some local methods all land here and can take days.
  /// The user is NOT premium yet and must not be charged for the wait.
  pending,

  /// The user backed out. Not an error, and never shown as one.
  cancelled,

  /// The store returned an error.
  error,
}

/// One purchase event from the store.
class BillingPurchase {
  const BillingPurchase({
    required this.outcome,
    required this.store,
    this.productId,
    this.verificationToken,
    this.orderId,
    this.message,
    this.native,
    this.needsCompletion = false,
  });

  final PurchaseOutcome outcome;
  final BillingStore store;
  final String? productId;

  /// What the server sends to the store to verify.
  ///   * Play — the purchase token
  ///   * StoreKit — the receipt / JWS transaction
  final String? verificationToken;

  final String? orderId;

  /// Store-supplied error text. For logs and support, not for users —
  /// the UI writes its own plain-English message.
  final String? message;

  /// The underlying store object, needed to acknowledge the purchase.
  final Object? native;

  /// True while the store is still waiting to be told we've delivered.
  ///
  /// Play refunds any subscription not acknowledged within three days,
  /// so this must end up completed — but only AFTER the server has
  /// verified it. Acknowledging first would mean acknowledging purchases
  /// we never granted.
  final bool needsCompletion;

  bool get isEntitling =>
      outcome == PurchaseOutcome.purchased ||
      outcome == PurchaseOutcome.restored;
}

/// A store, as the rest of the app sees it.
abstract class BillingPlatform {
  /// Which store this is.
  BillingStore get store;

  /// Whether billing can be used at all here. False on an emulator with
  /// no Play services, on a device where the Play Store is disabled, and
  /// on every platform without an implementation.
  Future<bool> isAvailable();

  /// Fetch the live product. Returns null when the store has never heard
  /// of [productId] — which in practice means the base plan was never
  /// activated in Play Console, not that the code is wrong.
  Future<PremiumOffer?> loadOffer(String productId);

  /// Start the store's own purchase sheet. Resolves as soon as the sheet
  /// is presented; the result arrives on [purchaseUpdates].
  Future<bool> buy(PremiumOffer offer);

  /// Every purchase the store tells us about: new ones, restored ones,
  /// renewals it decides to replay, and failures.
  Stream<List<BillingPurchase>> get purchaseUpdates;

  /// Ask the store to replay existing entitlements. Play requires a
  /// restore path to exist, and it is the only way a user who reinstalls
  /// or switches phone gets their subscription back without support.
  Future<void> restorePurchases();

  /// Tell the store we have delivered the goods. Call ONLY after the
  /// server has verified the purchase.
  Future<void> completePurchase(BillingPurchase purchase);

  void dispose();
}
