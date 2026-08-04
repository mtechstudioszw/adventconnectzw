/// Everything store-specific about the premium subscription, in one
/// place, so changing a product ID is a one-line edit rather than a hunt.
class BillingConfig {
  BillingConfig._();

  /// The Play Console subscription product ID.
  ///
  /// CONFIRMED LIVE (4 Aug 2026): created in Play Console as
  /// `premium_monthly`, base plan `monthly` (monthly, auto-renewing),
  /// priced across 174 countries/regions, base plan status Active.
  /// Matches this string exactly, as it must — a Play product ID can
  /// never be changed after creation.
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
