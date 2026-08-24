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

  // -------------------------------------------------------------------
  //  Annual plan
  //
  //  Play Billing 5+ allows several BASE PLANS on one subscription
  //  product, so the annual plan lives under the SAME product id — there
  //  is no second SKU and no second verification path. `verify-purchase`
  //  and `play-rtdn` already handle it unchanged, which is why annual is
  //  safe to add where a consumable top-up was not.
  //
  //  FOUNDER ACTION: create an annual base plan on `premium_monthly` in
  //  Play Console and activate it. Until then the store returns one plan
  //  and the picker quietly shows monthly alone — nothing breaks.
  // -------------------------------------------------------------------

  /// Base plan ids as created in Play Console. The store reports these
  /// on each offer so the app can tell the plans apart without guessing
  /// from the price.
  static const String monthlyBasePlanId = 'monthly';
  static const String annualBasePlanId = 'annual';

  /// Fallbacks only — the store's localised price always wins.
  static const String fallbackAnnualPriceLabel = 'US\$30.00';

  /// What the annual plan saves, expressed in MONTHS rather than a
  /// percentage.
  ///
  /// "2 months free" outperforms "17% off" reliably: it is a concrete
  /// unit of the thing being bought, so it needs no arithmetic and no
  /// trust in our maths. Same discount, easier to hold in the head.
  ///
  /// Derived from the real prices at render time where possible; this is
  /// the fallback for when the store has not answered yet.
  static const int annualFreeMonths = 2;
}
