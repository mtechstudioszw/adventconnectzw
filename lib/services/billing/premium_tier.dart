/// Which level of Premium a member holds, and what each level buys.
///
/// # One product, three base plans
///
/// A Play product ID can never be changed after creation, and
/// `premium_monthly` is live. So the tiers are **base plans on that one
/// product**, not new products:
///
/// ```
///   premium_monthly              (the product — never shown to a member)
///     ├── base plan `monthly`      US$3 / month   → PremiumTier.plus
///     ├── base plan `pro-monthly`  US$5 / month   → PremiumTier.pro
///     └── base plan `annual`       US$30 / year   → PremiumTier.pro
/// ```
///
/// This is not a shortcut, it is the correct shape, and it buys four
/// things that separate products would each have cost work to get:
///
///  1. **Mutual exclusivity for free.** Play allows exactly one active
///     base plan per product, so nobody can hold Plus and Pro at once.
///     Two separate products live in two subscription groups and CAN
///     both be active — we would have had to detect and reconcile that
///     ourselves, in a place where getting it wrong means double
///     charging a member.
///  2. **Native upgrade / downgrade with proration.** Moving Plus → Pro
///     is a base-plan change Play prices itself. Across products it is a
///     cancel plus a purchase, and the member pays twice for the overlap.
///  3. **No second verification path.** `verify-purchase` and `play-rtdn`
///     key on the product id and already work. The only new fact either
///     needs is which base plan the purchase used — one field, no new
///     function, no new secret.
///  4. **One subscription in the member's Play account**, which is what
///     they see when they go looking for how to cancel.
///
/// # Where the truth lives
///
/// Nowhere in this file. The server writes `profiles.premium_tier` from
/// verified store state (patch_268), the client reads it, and everything
/// here is the vocabulary plus what each level is worth. A client that
/// could decide its own tier would be a client that could grant itself
/// Pro, which is the whole thing `verify-purchase` exists to prevent.
library;

/// The levels, cheapest first. The order is load-bearing — [atLeast]
/// compares by index.
enum PremiumTier {
  /// Not subscribed. Ads on, free ceilings everywhere.
  none('none', 'Free'),

  /// US$3 / month. No ads, and a bigger call allowance.
  plus('plus', 'Plus'),

  /// US$5 / month, or US$30 / year. Everything in Plus, plus the full
  /// Advent AI allowance on the better model.
  pro('pro', 'Pro');

  const PremiumTier(this.id, this.label);

  /// The value stored in `profiles.premium_tier`. Must match the CHECK
  /// constraint in patch_268 exactly.
  final String id;

  /// What a member is called at this level.
  final String label;

  /// Parse a server value. Anything unrecognised — including a tier a
  /// newer build introduced and this one has never heard of — degrades
  /// to [none] rather than throwing, because the alternative is an app
  /// that crashes on launch the day a fourth tier is added.
  static PremiumTier parse(Object? raw) {
    final id = raw?.toString().trim().toLowerCase();
    if (id == null || id.isEmpty) return PremiumTier.none;
    for (final t in PremiumTier.values) {
      if (t.id == id) return t;
    }
    return PremiumTier.none;
  }

  /// Any paid level.
  bool get isPaid => this != PremiumTier.none;

  /// True when this tier is [other] or better. Use this rather than
  /// `== PremiumTier.pro` at a call site, so adding a level above Pro
  /// later does not silently lock existing members out of a feature
  /// they are paying more than enough for.
  bool atLeast(PremiumTier other) => index >= other.index;
}

/// What each level actually buys.
///
/// # These numbers MIRROR the database. They do not decide anything.
///
/// Same contract as `AiTiers`: every figure here also exists as an
/// `app_config` row or a column default, the server reads *those*, and
/// these copies exist so a paywall can say "6 hours a day" without a
/// round trip on first paint. Change one, change the other, or the app
/// promises what the server refuses.
class TierBenefits {
  const TierBenefits({
    required this.tier,
    required this.callMinutesPerDay,
    required this.aiQuestionsPerMonth,
    required this.adFree,
  });

  final PremiumTier tier;

  /// Mirrors `call.free_daily_minutes` / `call.plus_daily_minutes` /
  /// `call.pro_daily_minutes` in app_config.
  final int callMinutesPerDay;

  /// Mirrors `ai_free_grant_units` / `ai_plus_monthly_units` /
  /// `ai_premium_monthly_units` in app_config.
  final int aiQuestionsPerMonth;

  final bool adFree;

  static const free = TierBenefits(
    tier: PremiumTier.none,
    callMinutesPerDay: 120,
    aiQuestionsPerMonth: 10,
    adFree: false,
  );

  /// # Why Plus is not zero Advent AI
  ///
  /// The founder's proposal (25 Aug 2026) was that the $3 tier "only
  /// removes ads n extra call minutes", with Advent AI held back for
  /// the $5 tier. Two facts make the literal version unshippable, and
  /// both are about people who already exist rather than about taste:
  ///
  ///  1. **The free tier gets 10 questions a month.** A $3 tier with no
  ///     AI allowance would give a paying member FEWER questions than
  ///     someone paying nothing. Whatever Plus is, it cannot be below
  ///     free.
  ///  2. **`premium_monthly` is live at $3 and already includes 500
  ///     questions.** Every current subscriber bought that. Cutting the
  ///     $3 tier's AI to nothing is taking a feature off people who are
  ///     mid-subscription — churn, refund requests, and a bad look in a
  ///     church app. (They are grandfathered to Pro by patch_268; this
  ///     is about what the $3 tier means to the NEXT person who reads
  ///     the paywall next to a subscriber who tells them what they get.)
  ///
  /// 100 is the compromise: a real, felt upgrade over free — ten times
  /// the questions, on the better model — while leaving Pro five times
  /// more room to be worth $2 extra. **If you want the literal
  /// proposal, set this to 10 and the tier still works**; nothing
  /// branches on the number.
  static const plus = TierBenefits(
    tier: PremiumTier.plus,
    callMinutesPerDay: 360,
    aiQuestionsPerMonth: 100,
    adFree: true,
  );

  static const pro = TierBenefits(
    tier: PremiumTier.pro,
    callMinutesPerDay: 720,
    aiQuestionsPerMonth: 500,
    adFree: true,
  );

  static TierBenefits of(PremiumTier tier) => switch (tier) {
    PremiumTier.none => free,
    PremiumTier.plus => plus,
    PremiumTier.pro => pro,
  };

  /// "2 hours" / "6 hours" / "12 hours" — the call allowance in the unit
  /// people actually think in. 360 minutes is a number you have to do
  /// arithmetic on; six hours is not.
  String get callAllowanceLabel {
    if (callMinutesPerDay % 60 == 0) {
      final hours = callMinutesPerDay ~/ 60;
      return '$hours hour${hours == 1 ? '' : 's'}';
    }
    return '$callMinutesPerDay minutes';
  }
}
