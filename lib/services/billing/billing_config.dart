import 'premium_tier.dart';

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
  ///
  /// **The name is now a misnomer and that is fine.** It carries the
  /// annual and Pro plans too (see [basePlanTiers]). A member never sees
  /// a product id; renaming it is impossible and would buy nothing.
  static const String monthlyProductId = 'premium_monthly';

  /// Every product the app may query. Still one — the tiers are BASE
  /// PLANS on this product, not separate SKUs. See [PremiumTier] for
  /// why that is the right shape rather than a shortcut.
  static const Set<String> allProductIds = {monthlyProductId};

  // -------------------------------------------------------------------
  //  Base plans
  //
  //  Play Billing 5+ allows several BASE PLANS on one subscription
  //  product, so all three tiers live under the SAME product id — there
  //  is no second SKU and no second verification path. `verify-purchase`
  //  and `play-rtdn` handle them with one extra field (the base plan id),
  //  which is why tiers are safe to add where a consumable top-up was
  //  not.
  //
  //  FOUNDER ACTION — Play Console, before any of this can sell:
  //
  //    Subscription `premium_monthly`
  //      • base plan `monthly`     — EXISTS AND IS LIVE. US$3 / month.
  //                                  Do not touch it. Changing the price
  //                                  or the id of a live base plan is
  //                                  either impossible or a migration.
  //      • base plan `pro-monthly` — CREATE. US$5 / month, auto-renewing.
  //      • base plan `annual`      — CREATE. US$30 / year, auto-renewing.
  //
  //  Until they exist, `loadOffers` returns one plan, the picker shows a
  //  single quiet row, and everyone who buys gets Plus. Nothing breaks
  //  and nothing lies.
  // -------------------------------------------------------------------

  /// Base plan ids as created in Play Console. The store reports these
  /// on each offer so the app can tell the plans apart without guessing
  /// from the price.
  static const String monthlyBasePlanId = 'monthly';
  static const String proMonthlyBasePlanId = 'pro-monthly';
  static const String annualBasePlanId = 'annual';

  /// Which tier each base plan grants.
  ///
  /// **This map is a MIRROR of the server's, in patch_268.** The server
  /// decides; this copy exists so the picker can label a plan before any
  /// purchase happens. If the two ever disagree the server wins, and the
  /// member sees a tier they were not shown — so change them together.
  static const Map<String, PremiumTier> basePlanTiers = {
    monthlyBasePlanId: PremiumTier.plus,
    proMonthlyBasePlanId: PremiumTier.pro,
    annualBasePlanId: PremiumTier.pro,
  };

  /// The tier a base plan grants. Defaults to [PremiumTier.plus] for an
  /// id we have never heard of — the LOWEST paid tier, deliberately.
  /// An unknown plan is either a Play Console change that has not
  /// reached this build or a mistake, and under-granting is the failure
  /// that gets a support ticket rather than the one that gives away Pro.
  static PremiumTier tierForBasePlan(String? basePlanId) {
    if (basePlanId == null || basePlanId.isEmpty) return PremiumTier.plus;
    return basePlanTiers[basePlanId] ?? PremiumTier.plus;
  }

  /// The plan that carries the promotional badge and is SELECTED when
  /// the Premium screen opens (founder's call, 25 Aug 2026).
  ///
  /// It is the honest recommendation as well as the profitable one: at
  /// US$30 it is the cheapest way to hold Pro for a year by a distance,
  /// so preselecting it cannot overcharge anyone relative to the plan
  /// they would otherwise have picked on price.
  static const String featuredBasePlanId = annualBasePlanId;

  /// Ribbon text on the featured plan. Not a countdown, not a fake
  /// discount, not "limited time" — the brief bans all three, and this
  /// audience costs more trust than they win.
  static const String featuredBadgeLabel = 'BEST VALUE';

  // -------------------------------------------------------------------
  //  Fallback price labels
  //
  //  Shown ONLY if the store fails to return a localised price, which
  //  happens on a cold Play Store cache or a device with no Play
  //  services. Never used when the store answers — the real price is
  //  always the store's own localised string, in the user's currency.
  //  A member in Harare must see their own currency, never a US figure.
  // -------------------------------------------------------------------

  static const String fallbackPriceLabel = 'US\$3.00';
  static const String fallbackProPriceLabel = 'US\$5.00';
  static const String fallbackAnnualPriceLabel = 'US\$30.00';

  /// Human label for the billing period. Kept next to the price so the
  /// two can never drift apart in the UI.
  static const String periodLabel = 'month';

  /// What the annual plan saves, expressed in MONTHS rather than a
  /// percentage.
  ///
  /// "6 months free" outperforms "50% off" reliably: it is a concrete
  /// unit of the thing being bought, so it needs no arithmetic and no
  /// trust in our maths. Same discount, easier to hold in the head.
  ///
  /// Derived from the real prices at render time where possible; this is
  /// the fallback for when the store has not answered yet. US$30/year
  /// against US$5/month is six months' worth given away.
  static const int annualFreeMonths = 6;
}
