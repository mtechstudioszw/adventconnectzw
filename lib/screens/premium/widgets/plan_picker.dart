import 'package:flutter/material.dart';

import '../../../services/billing/billing_config.dart';
import '../../../services/billing/billing_platform.dart';
import '../../../services/billing/premium_tier.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';
import '../../../theme/app_tokens.dart';

/// Choose a plan: Plus monthly, Pro monthly, or Pro yearly.
///
/// # The psychology, deliberately
///
///  * **The yearly plan is listed FIRST, badged, and preselected.**
///    Founder's call, 25 Aug 2026. It is also the honest recommendation:
///    at US$30 against US$5/month it is the cheapest way to hold Pro for
///    a year by a distance, so preselecting it cannot overcharge anyone
///    relative to what they would have chosen on price.
///  * **The per-month line does the arguing.** US$30/year is US$2.50 a
///    month — *less than the US$3 Plus plan directly underneath it*, for
///    the higher tier. That comparison is the whole pitch and it needs
///    no adjectives, so the tiles sit adjacent and the number is
///    computed from the store's own prices rather than written down.
///  * **The saving is named in MONTHS, not percent.** "6 months free"
///    needs no arithmetic and no trust in our maths; "50% off" needs
///    both. Same discount, far easier to hold in the head.
///  * **Every price is the store's own localised string.** A member in
///    Harare sees their currency. Nothing here formats a price; the
///    per-month figure divides the store's number and reuses the store's
///    own symbol.
///  * **No countdown, no "limited time", no strike-through fake price.**
///    Those cost more trust than they win with this audience, and the
///    brief bans them outright.
///
/// # When fewer plans exist
///
/// Play returns whatever base plans are ACTIVE. Before `pro-monthly` and
/// `annual` are created in Play Console there is exactly one, and this
/// collapses to a single quiet row rather than showing an empty choice —
/// a picker with one option looks broken. Two plans render as two.
class PlanPicker extends StatelessWidget {
  const PlanPicker({
    super.key,
    required this.offers,
    required this.selected,
    required this.onSelect,
  });

  final List<PremiumOffer> offers;
  final PremiumOffer? selected;
  final ValueChanged<PremiumOffer> onSelect;

  /// Dearest first, which puts the yearly plan at the top.
  ///
  /// The store sorts cheapest-first, which is the wrong order for an
  /// anchor and the wrong order for a preselected row — a selected tile
  /// below two unselected ones reads as the last resort rather than the
  /// recommendation.
  List<PremiumOffer> get _ordered {
    final sorted = [...offers]
      ..sort((a, b) => b.rawPrice.compareTo(a.rawPrice));
    return sorted;
  }

  /// The cheapest plan, used as the baseline a saving is measured
  /// against. Null when there is nothing to compare.
  PremiumOffer? get _baseline {
    if (offers.length < 2) return null;
    return offers.reduce((a, b) => a.rawPrice <= b.rawPrice ? a : b);
  }

  /// The dearest MONTHLY plan, which is what a yearly plan actually
  /// saves against.
  ///
  /// Not [_baseline]. With three plans the cheapest is Plus at $3, and
  /// measuring the yearly Pro against it would claim "6 months free" on
  /// a comparison between two different tiers — true arithmetic, wrong
  /// claim. The honest baseline for "what does buying yearly save" is
  /// the same tier billed monthly.
  PremiumOffer? get _monthlyPeer {
    PremiumOffer? best;
    for (final o in offers) {
      if (_isYearly(o)) continue;
      if (best == null || o.rawPrice > best.rawPrice) best = o;
    }
    return best;
  }

  /// Does this offer bill yearly?
  ///
  /// Read from the BASE PLAN ID first, and the reasoning here has
  /// flipped since the two-plan version of this file. It used to prefer
  /// the price ("a typo in a Play Console id would silently mislabel a
  /// real charge"), which was right when the id decided nothing. It now
  /// decides the TIER — the server grants Plus or Pro from this exact
  /// string (patch_268). So if the id is wrong the entitlement is wrong
  /// whatever this label says, and labelling from anything else would
  /// only guarantee the label and the grant disagree.
  ///
  /// Price stays as the fallback for a store that reports no id at all.
  bool _isYearly(PremiumOffer offer) {
    final id = offer.basePlanId;
    if (id != null && id.isNotEmpty) {
      return id == BillingConfig.annualBasePlanId;
    }
    final base = _baseline;
    return base != null && offer.rawPrice > base.rawPrice * 1.5;
  }

  bool _isFeatured(PremiumOffer offer) =>
      offer.basePlanId == BillingConfig.featuredBasePlanId;

  static bool _sameOffer(PremiumOffer a, PremiumOffer? b) =>
      b != null &&
      a.productId == b.productId &&
      a.basePlanId == b.basePlanId &&
      a.rawPrice == b.rawPrice;

  @override
  Widget build(BuildContext context) {
    if (offers.isEmpty) return const SizedBox.shrink();

    // One plan: no choice to present.
    if (offers.length == 1) {
      return _SinglePlanRow(offer: offers.first);
    }

    final peer = _monthlyPeer;
    return Column(
      children: [
        for (final offer in _ordered)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: _PlanTile(
              offer: offer,
              tier: BillingConfig.tierForBasePlan(offer.basePlanId),
              yearly: _isYearly(offer),
              featured: _isFeatured(offer),
              monthlyPeer: peer,
              selected: identical(offer, selected) || _sameOffer(offer, selected),
              onTap: () => onSelect(offer),
            ),
          ),
      ],
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.offer,
    required this.tier,
    required this.yearly,
    required this.featured,
    required this.monthlyPeer,
    required this.selected,
    required this.onTap,
  });

  final PremiumOffer offer;
  final PremiumTier tier;
  final bool yearly;
  final bool featured;
  final PremiumOffer? monthlyPeer;
  final bool selected;
  final VoidCallback onTap;

  /// Months of the same tier billed monthly that this plan covers for
  /// free.
  ///
  /// Computed from the real prices, so it stays honest whatever the
  /// store returns and whatever currency the member sees. Falls back to
  /// the configured figure only when there is nothing to compare with.
  int get _freeMonths {
    final peer = monthlyPeer;
    if (peer == null || peer.rawPrice <= 0) {
      return BillingConfig.annualFreeMonths;
    }
    final monthsPaidFor = offer.rawPrice / peer.rawPrice;
    return (12 - monthsPaidFor).round().clamp(0, 11);
  }

  /// "US$2.50" — the yearly price divided across twelve months, in the
  /// same currency the store quoted.
  String? get _perMonth {
    if (!yearly || offer.rawPrice <= 0) return null;
    final each = offer.rawPrice / 12;
    // Recover the currency symbol from the store's own formatting rather
    // than mapping currency codes ourselves — the store already knows
    // how this member's currency is written.
    final symbol = offer.price.replaceAll(RegExp(r'[\d.,\s]'), '');
    return '$symbol${each.toStringAsFixed(2)}';
  }

  /// The tier's name, and how often it bills.
  String get _title => yearly ? '${tier.label} yearly' : '${tier.label} monthly';

  /// One line on what this level is worth. Built from [TierBenefits] so
  /// it cannot drift from the entitlement the server will actually grant.
  String get _summary {
    final b = TierBenefits.of(tier);
    return 'No ads · ${b.callAllowanceLabel} of calls a day · '
        '${b.aiQuestionsPerMonth} Advent AI questions a month';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final free = _freeMonths;
    final showPromo = featured && free > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryBlue.withValues(alpha: 0.06)
                : palette.card,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: selected ? AppColors.primaryBlue : palette.divider,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _Radio(selected: selected),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Wrap, not Row: at a large text size the title and
                    // the badge together are wider than the tile, and a
                    // Row would overflow rather than stack.
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppSpace.sm,
                      runSpacing: 4,
                      children: [
                        Text(
                          _title,
                          style: AppTextStyles.titleSmall.copyWith(
                            color: palette.text,
                          ),
                        ),
                        if (showPromo) _PromoBadge(months: free),
                      ],
                    ),
                    if (_perMonth != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '$_perMonth a month, billed yearly',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.primaryBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      _summary,
                      style: AppTextStyles.caption.copyWith(
                        color: palette.textMuted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Text(
                offer.price,
                style: AppTextStyles.titleSmall.copyWith(
                  color: selected ? AppColors.primaryBlue : palette.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The saving, in months. Gold, and the only gold on this card — the
/// design rule is one gold highlight per screen at most.
class _PromoBadge extends StatelessWidget {
  const _PromoBadge({required this.months});
  final int months;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.goldAccent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        months == 1 ? '1 month free' : '$months months free',
        style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.goldAccent,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppColors.primaryBlue : palette.divider,
          width: 2,
        ),
        color: selected ? AppColors.primaryBlue : Colors.transparent,
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
          : null,
    );
  }
}

/// What the picker collapses to while only one base plan is active in
/// Play Console.
class _SinglePlanRow extends StatelessWidget {
  const _SinglePlanRow({required this.offer});
  final PremiumOffer offer;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: palette.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Billed monthly',
              style: AppTextStyles.bodyMedium.copyWith(color: palette.text),
            ),
          ),
          Text(
            offer.price,
            style: AppTextStyles.titleSmall.copyWith(color: palette.text),
          ),
        ],
      ),
    );
  }
}
