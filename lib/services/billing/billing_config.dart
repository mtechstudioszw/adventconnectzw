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
  //  CONFIRMED LIVE (24 Aug 2026): all three base plans exist in Play
  //  Console under `premium_monthly`.
  //
  //    Subscription `premium_monthly`
  //      • base plan `monthly`         — US$3 / month.
  //      • base plan `pro-monthly`     — US$5 / month, auto-renewing.
  //      • base plan `annualpermanent` — US$30 / year, auto-renewing.
  //
  //  NOTE: the yearly base plan's id is `annualpermanent`, not `annual`.
  //  It was created under that name in Play Console and — like the
  //  product id — a base plan id can never be changed after creation.
  //  If this constant and the console ever disagree, every offer on the
  //  yearly plan silently falls through to the "unknown base plan"
  //  fallback: labelled monthly, priced right, but graded as Plus
  //  instead of Pro. That happened once already (25 Aug 2026); this
  //  comment exists so it doesn't happen again by the same route.
  // -------------------------------------------------------------------

  /// Base plan ids as created in Play Console. The store reports these
  /// on each offer so the app can tell the plans apart without guessing
  /// from the price.
  static const String monthlyBasePlanId = 'monthly';
  static const String proMonthlyBasePlanId = 'pro-monthly';
  static const String annualBasePlanId = 'annualpermanent';

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

  /// Human label for the billing period of a SPECIFIC offer.
  ///
  /// Not a constant — it used to be `static const periodLabel = 'month'`,
  /// which was correct back when there was one base plan and wrong the
  /// moment a yearly one existed: it labelled the US$30 plan "a month"
  /// regardless of which offer was actually selected. This reads the
  /// offer's own base plan id, the same source of truth [PlanPicker]
  /// uses, so the two can never disagree about what a member is buying.
  static String periodLabelFor(String? basePlanId) =>
      basePlanId == annualBasePlanId ? 'year' : 'month';

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
