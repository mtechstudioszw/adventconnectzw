import '../billing/billing_config.dart';
import '../billing/premium_tier.dart';

/// What each Advent AI tier gets, and what it costs us to serve.
///
/// # This file MIRRORS the database. It does not decide anything.
///
/// Every number here also exists as an `app_config` row (patch 235) and
/// the server reads *those*, never these. The copies live here so the
/// paywall can say "10 questions" without a round trip on first paint.
/// The config key is named beside each one — if you change a number
/// here, change the row, or the app will promise what the server refuses.
///
/// Runtime truth always comes from `ai_my_balance()`. This is furniture.
///
/// # The tiers (reconciled 25 Aug 2026)
///
///   Free      — 10 questions, refilled monthly, on the cheap model.
///   Plus      — 100 questions a month, on the better model. US$3.
///   Pro       — 500 questions a month, on the better model. US$5 a
///               month, or US$30 a year.
///
/// All three paid levels are BASE PLANS on the one live
/// `premium_monthly` product — see [PremiumTier] for why that shape and
/// not three products.
///
/// ## Why Plus is not zero questions
///
/// The founder's proposal put Advent AI entirely behind the $5 tier.
/// The free tier gets 10 a month, so a $3 tier with none would give a
/// paying member less than a non-paying one — and every current $3
/// subscriber already has 500. The full reasoning, and the one-line
/// change if you want the literal version, is on [TierBenefits.plus].
///
/// ## Cost, at the cap
///
///   Plus  100 x $0.00197 = $0.20 against ~$2.55 net of the store's cut.
///   Pro   500 x $0.00197 = $0.99 against ~$4.25 net.
///
/// Both hold with a wide margin, and realistic use is far below either
/// cap — the cap exists to bound the tail, not to describe the median.
///
/// ## Why there is no top-up bundle in v1
///
/// The brief (§20-24) asked for a "Fund Your Account" system with $1/$5/
/// $10 top-ups, and an earlier draft of this file had one. It is cut,
/// deliberately, on the founder's own §37 — *do not overengineer before
/// validating*:
///
///  * A consumable IAP is a **second billing verification path**, and
///    consumables are the harder one to get right: a purchase token must
///    be consumed exactly once, and duplicate-grant bugs are the classic
///    exploit against precisely that flow. Subscriptions already run
///    through `verify-purchase` + `play-rtdn`, which are live and
///    already verified. One payment surface is safer than two.
///  * Nobody has yet paid $3, so there is no evidence a $1 tier is the
///    missing piece rather than a second thing to secure and support.
///
/// The ledger in patch 234 records units per pool, so adding a `bundle`
/// pool later is an INSERT and a new branch in `ai_spend_unit` — no
/// migration of existing balances. The door is left open on purpose.
///
/// ## The advertising benefit — READ BEFORE EDITING [Tier.benefits]
///
/// This used to read "No ads anywhere in the app". That is a **negative**
/// benefit: it charges the member to stop doing something to them, which
/// reads as a hostage note, and in a church app it costs more goodwill
/// than it earns.
///
/// The reframe is who *pays for the app*, not what gets removed. An app
/// is funded either by advertisers or by the people using it, and
/// Premium moves a member from the first to the second. That is true, it
/// is a statement about them rather than about a nuisance, and it
/// carries the stewardship framing this audience already thinks in.
///
/// Do not "simplify" it back to "No ads". The words are the feature.
class AiTiers {
  AiTiers._();

  // ------------------------------------------------------------------
  //  Provider economics. Verified against ai.google.dev/gemini-api/docs/
  //  pricing, 23 Aug 2026, and mirrored in app_config as
  //  ai_price_in_micros_per_mtok / ai_price_out_micros_per_mtok.
  // ------------------------------------------------------------------

  /// One answer on the cheap model, in US cents. Gemini 2.5 Flash-Lite
  /// at $0.10/1M in and $0.40/1M out, against ~2,800 input tokens
  /// (system prompt + app knowledge + context + tool results) and ~450
  /// output — both bounded by `ai_max_context_tokens` and
  /// `ai_max_output_tokens`.
  static const double centsPerMessageLite = 0.046;

  /// The same sum on Gemini 2.5 Flash ($0.30/1M in, $2.50/1M out).
  static const double centsPerMessageFlash = 0.197;

  /// **Google's free tier trains on what is sent to it.** Its pricing
  /// page marks every free-tier model "used to improve Google products";
  /// the paid tier is not.
  ///
  /// Members ask Advent AI about depression, marriage, doubt and money.
  /// Routing that to a tier that harvests it would be indefensible and
  /// contradicts this app's own privacy rules. Free-tier rate limits are
  /// also **per project, not per user**, so the entire membership would
  /// share one bucket and the feature would collapse on the first busy
  /// Sabbath regardless.
  ///
  /// Billing must be enabled on the Google Cloud project before launch.
  /// Developing against the free tier with invented questions is fine.
  static const bool freeTierIsUnusable = true;

  // ------------------------------------------------------------------
  //  Tiers
  // ------------------------------------------------------------------

  /// Ad-supported. Ten questions a month — `ai_free_grant_units`.
  ///
  /// Refilled monthly rather than granted once for life. A one-time
  /// grant means a member who spends it in week one and cannot afford
  /// $3 has no reason to ever open Advent AI again; the feature is dead
  /// to most of the user base by design. A monthly refill keeps the
  /// habit alive so the eventual ask lands on somebody who already uses
  /// it. Cost stays bounded by `ai_global_free_pool_micros` and
  /// `ai_global_daily_cap_micros` either way.
  static const free = Tier(
    id: 'free',
    label: 'Free',
    monthlyMessages: 10,
    model: AiModel.lite,
    priceLabel: 'Free',
    benefits: <String>[
      '10 Advent AI questions a month',
      'The whole app — Bible, Sabbath School, Hymnal, EGW, Quiz, '
          'churches, events, chat and the marketplace',
    ],
  );

  /// US$3 a month — the base plan that has been live since 4 Aug 2026,
  /// now named. `ai_plus_monthly_units`.
  ///
  /// Price and product ID come from [BillingConfig]; a Play product ID
  /// can never be changed after creation, so this file must never
  /// restate it.
  static const plus = Tier(
    id: 'plus',
    label: 'Plus',
    monthlyMessages: 100,
    model: AiModel.flash,
    priceLabel: BillingConfig.fallbackPriceLabel,
    benefits: <String>[
      '100 Advent AI questions a month, on our better model',
      'Six hours of calls a day, up from two',
      // The reframe. Read the class doc before touching this line.
      'The app is paid for by members like you, not by advertisers — '
          'so yours has no ads in it',
      'Keeps Adventist Super App free for everyone who cannot pay',
    ],
  );

  /// US$5 a month, or US$30 a year — `ai_premium_monthly_units`.
  ///
  /// The config key keeps its old name deliberately: it is the same
  /// number, on the same allowance, that `premium` granted before the
  /// tiers were split. Renaming a live app_config key to match a Dart
  /// identifier would be a migration in exchange for nothing.
  static const pro = Tier(
    id: 'pro',
    label: 'Pro',
    monthlyMessages: 500,
    model: AiModel.flash,
    priceLabel: BillingConfig.fallbackProPriceLabel,
    benefits: <String>[
      '500 Advent AI questions a month — five times Plus',
      'Deeper answers — Pro uses our most capable model',
      'Twelve hours of calls a day',
      'The app is paid for by members like you, not by advertisers — '
          'so yours has no ads in it',
      'Keeps Adventist Super App free for everyone who cannot pay',
    ],
  );

  /// The old name for [pro], from when there was one paid tier.
  ///
  /// Kept as a plain alias rather than deprecated: the paywall copy and
  /// its tests legitimately mean "the top tier", which is what this has
  /// always pointed at and still does. New code that means a SPECIFIC
  /// level should name it — [plus] or [pro].
  static const premium = pro;

  /// Every tier, cheapest first. The price climbs on purpose: it makes
  /// the top tier the considered conclusion of a comparison rather than
  /// the demand that opens one.
  static const all = <Tier>[free, plus, pro];

  /// The Advent AI tier a [PremiumTier] grants.
  static Tier forPremiumTier(PremiumTier tier) => switch (tier) {
    PremiumTier.none => free,
    PremiumTier.plus => plus,
    PremiumTier.pro => pro,
  };

  /// Warn a member at this many remaining, so the wall is never the
  /// first they hear of it. Arriving at zero unwarned is what makes a
  /// paywall feel like a trap.
  static const int warnAtRemaining = 3;
}

/// Which provider model a tier's answers come from.
///
/// Mirrors `ai_model` / `ai_model_premium` in app_config. The split is
/// not crippling the free tier to sell the paid one — it is what makes a
/// free tier affordable at all, and it gives Premium a difference
/// members can actually feel, which "no ads" never did.
enum AiModel {
  /// `gemini-2.5-flash-lite`.
  lite,

  /// `gemini-2.5-flash`.
  flash,
}

/// One level of Advent AI access.
class Tier {
  const Tier({
    required this.id,
    required this.label,
    required this.monthlyMessages,
    required this.model,
    required this.priceLabel,
    required this.benefits,
  });

  final String id;
  final String label;

  /// Questions included per calendar month.
  final int monthlyMessages;

  final AiModel model;

  /// Fallback only. When the store answers, its localised price wins — a
  /// member in Harare must see their own currency, never a US figure.
  final String priceLabel;

  final List<String> benefits;

  /// What this tier costs us if a member uses every question, in cents.
  /// For the admin dashboard; never shown to members.
  double get worstCaseCostCents =>
      monthlyMessages *
      (model == AiModel.flash
          ? AiTiers.centsPerMessageFlash
          : AiTiers.centsPerMessageLite);
}
