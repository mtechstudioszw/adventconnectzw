import 'package:flutter/material.dart';

import '../../../services/billing/billing_config.dart';
import '../../../services/billing/billing_platform.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';
import '../../../theme/app_tokens.dart';

/// Choose monthly or annual.
///
/// # The psychology, deliberately
///
///  * **Annual is listed FIRST and preselected.** Reading the larger
///    number first makes the monthly price feel small, and reading the
///    per-month equivalent underneath makes the annual feel like the
///    sensible one. Either choice then feels good, which is the point —
///    an anchor that makes both options comfortable, not one that
///    corners anybody.
///  * **The saving is named in MONTHS, not percent.** "2 months free"
///    needs no arithmetic and no trust in our maths; "17% off" needs
///    both. Same discount, far easier to hold in the head.
///  * **The per-month equivalent is computed, never hand-written.** A
///    hardcoded "$2.50/month" beside a store price the member sees in
///    their own currency is how a paywall starts lying by accident.
///  * **No countdown, no "limited time", no strike-through fake price.**
///    Those cost more trust than they win with this audience, and the
///    brief bans them outright.
///
/// # When only one plan exists
///
/// Play returns whatever base plans are ACTIVE. Before an annual plan is
/// created in Play Console there is exactly one, and this collapses to a
/// single quiet row rather than showing an empty choice — a picker with
/// one option looks broken.
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

  /// Annual first. The store sorts cheapest-first, which is the wrong
  /// order for an anchor.
  List<PremiumOffer> get _ordered {
    final sorted = [...offers]
      ..sort((a, b) => b.rawPrice.compareTo(a.rawPrice));
    return sorted;
  }

  /// The cheapest plan, used as the baseline the saving is measured
  /// against. Null when there is nothing to compare.
  PremiumOffer? get _baseline {
    if (offers.length < 2) return null;
    return offers.reduce((a, b) => a.rawPrice <= b.rawPrice ? a : b);
  }

  @override
  Widget build(BuildContext context) {
    if (offers.isEmpty) return const SizedBox.shrink();

    // One plan: no choice to present.
    if (offers.length == 1) {
      return _SinglePlanRow(offer: offers.first);
    }

    return Column(
      children: [
        for (final offer in _ordered)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: _PlanTile(
              offer: offer,
              baseline: _baseline,
              selected: identical(offer, selected) ||
                  offer.productId == selected?.productId &&
                      offer.rawPrice == selected?.rawPrice,
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
    required this.baseline,
    required this.selected,
    required this.onTap,
  });

  final PremiumOffer offer;
  final PremiumOffer? baseline;
  final bool selected;
  final VoidCallback onTap;

  /// True when this plan bills yearly.
  ///
  /// Decided by price relative to the cheapest plan rather than by
  /// parsing a base-plan id: ids are set in Play Console and a typo
  /// there would silently mislabel a real charge. Price is the thing the
  /// member actually pays, so it is the safer signal.
  bool get _isAnnual =>
      baseline != null && offer.rawPrice > baseline!.rawPrice * 1.5;

  /// Months of the cheaper plan this one covers for free.
  ///
  /// Computed from the real prices, so it stays honest whatever the
  /// store returns and whatever currency the member sees.
  int get _freeMonths {
    final base = baseline;
    if (base == null || base.rawPrice <= 0) {
      return BillingConfig.annualFreeMonths;
    }
    final monthsPaidFor = offer.rawPrice / base.rawPrice;
    final saved = (12 - monthsPaidFor).round();
    return saved.clamp(0, 11);
  }

  /// "US$2.50" — the annual price divided across twelve months, in the
  /// same currency the store quoted.
  String? get _perMonth {
    if (!_isAnnual || offer.rawPrice <= 0) return null;
    final each = offer.rawPrice / 12;
    // Recover the currency symbol from the store's own formatting rather
    // than mapping currency codes ourselves — the store already knows
    // how this member's currency is written.
    final symbol = offer.price.replaceAll(RegExp(r'[\d.,\s]'), '');
    return '$symbol${each.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final free = _freeMonths;
    final showPromo = _isAnnual && free > 0;

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
            children: [
              _Radio(selected: selected),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _isAnnual ? 'Yearly' : 'Monthly',
                          style: AppTextStyles.titleSmall
                              .copyWith(color: palette.text),
                        ),
                        if (showPromo) ...[
                          const SizedBox(width: AppSpace.sm),
                          _PromoBadge(months: free),
                        ],
                      ],
                    ),
                    if (_perMonth != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '$_perMonth a month, billed yearly',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: palette.textMuted),
                      ),
                    ],
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

/// What the picker collapses to before an annual plan exists.
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
