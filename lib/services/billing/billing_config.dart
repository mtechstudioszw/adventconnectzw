/// Everything store-specific about the premium subscription, in one
/// place, so changing a product ID is a one-line edit rather than a hunt.
class BillingConfig {
  BillingConfig._();

  /// The Play Console subscription product ID.
  ///
  /// >>> NOT YET CONFIRMED (3 Aug 2026) <<<
  /// The founder had not created the product when this shipped. A Play
  /// product ID **can never be changed after creation**, so whatever is
  /// created in Play Console must match this string exactly — or this
  /// string must be changed to match it. Nothing else in the app
  /// hardcodes it.
  ///
  /// Play Console → Monetise → Products → Subscriptions → Create:
  ///   * Product ID: premium_monthly
  ///   * Base plan: monthly, auto-renewing, USD $3.00
  ///   * Add at least one regional price, then ACTIVATE the base plan
  ///     (an inactive base plan makes the product invisible to the app,
  ///     which looks exactly like a bug).
  static const String monthlyProductId = 'premium_monthly';

  /// Every product the app may query. One today; adding an annual plan
  /// later means adding it here and to the Premium screen, nowhere else.
  static const Set<String> allProductIds = {monthlyProductId};

  /// Shown only if the store fails to return a localised price, which
  /// happens on a cold Play Store cache or a device with no Play
  /// services. Never used when the store answers — the real price is
  /// always the store's own localised string, in the user's currency.
  static const String fallbackPriceLabel = 'US\$3.00';

  /// Human label for the billing period. Kept next to the price so the
  /// two can never drift apart in the UI.
  static const String periodLabel = 'month';
}
