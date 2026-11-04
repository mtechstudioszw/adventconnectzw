import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/platform_flags.dart';
import '../../services/billing/billing_service.dart';
import '../../services/premium_promo_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// The Premium card in the Home feed (Android only).
///
/// Owner, 4 Nov 2026: "people are not reaching the premium screen … some
/// users think we don't have premium". A card in the feed, not a pop-up:
/// it is seen by everyone who scrolls, interrupts no one, and "Not now"
/// snoozes it (PremiumPromoService.feedCardFor).
///
/// What it will NOT do — on purpose:
///  * no countdown or "offer ends soon" unless an offer really ends. A
///    fake timer is a Google Play deceptive-behaviour risk and the
///    founder's own brief (25 Aug 2026) bans it;
///  * "free trial" only when Play actually returned a trial offer to this
///    member — so the button never promises what the store won't give.
class FeedPremiumCard extends StatefulWidget {
  const FeedPremiumCard({super.key, required this.kind});

  final FeedPromo kind;

  /// The free-member messages, one per day in rotation, so the card
  /// teaches a different reason each time instead of repeating one.
  static const freePitches = <(IconData, String, String)>[
    (
      Icons.block_rounded,
      'Use the app with no ads',
      'Premium removes every ad — in the feed, Watch, Marketplace and '
          'after stories.',
    ),
    (
      Icons.star_rounded,
      'Get the gold Premium star',
      'Everyone sees it beside your name — on posts, comments, your '
          'profile and in chat.',
    ),
    (
      Icons.call_rounded,
      'More time on calls',
      'Up to 6 hours of voice calls a day, instead of 2.',
    ),
    (
      Icons.favorite_rounded,
      'Keep the app growing',
      'Premium pays for the servers, the Bible audio and new features — '
          'and keeps the app free for everyone else.',
    ),
  ];

  @visibleForTesting
  static (IconData, String, String) pitchFor(DateTime day) {
    final dayOfYear = day.difference(DateTime(day.year)).inDays;
    return freePitches[dayOfYear % freePitches.length];
  }

  @override
  State<FeedPremiumCard> createState() => _FeedPremiumCardState();
}

class _FeedPremiumCardState extends State<FeedPremiumCard> {
  @override
  void initState() {
    super.initState();
    // The price / trial line needs Play's offers. Fetch them quietly the
    // first time the card is seen; until then the card reads without them.
    if (!kHidePayments && BillingService.offers.isEmpty) {
      BillingService.loadOffer().then((_) {
        if (mounted) setState(() {});
      }).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kHidePayments || widget.kind == FeedPromo.none) {
      return const SizedBox.shrink();
    }
    final palette = context.palette;
    final upgrade = widget.kind == FeedPromo.upgradePro;

    final offers = BillingService.offers;
    final trial = offers
        .map((o) => o.trialLabel)
        .whereType<String>()
        .firstOrNull;
    final cheapest = offers.isEmpty
        ? null
        : offers.reduce((a, b) => a.rawPrice <= b.rawPrice ? a : b);

    final (icon, title, body) = upgrade
        ? (
            Icons.workspace_premium_rounded,
            'Upgrade to Pro',
            'Twice the call time — up to 12 hours of voice calls a day '
                'instead of 6.',
          )
        : FeedPremiumCard.pitchFor(DateTime.now());

    final cta = upgrade
        ? 'See Pro'
        : trial != null
        ? 'Start $trial free trial'
        : 'See Premium';
    final small = upgrade
        ? null
        : trial != null
        ? 'Then ${cheapest?.price ?? 'the plan price'}. Cancel any time.'
        : cheapest != null
        ? 'From ${cheapest.price}. Cancel any time.'
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Container(
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.goldAccent.withValues(alpha: 0.35),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.goldAccent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: AppColors.goldAccent, size: 19),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    upgrade ? 'PRO' : 'PREMIUM',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: palette.textMuted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Not now',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded,
                      size: 20, color: palette.textMuted),
                  onPressed: PremiumPromoService.dismissFeedCard,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: palette.textMuted),
                  ),
                  const SizedBox(height: 14),
                  _GradientPill(
                    label: cta,
                    onTap: () => context.pushNamed('premium'),
                  ),
                  if (small != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      small,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientPill extends StatelessWidget {
  const _GradientPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            child: Text(
              label,
              style: AppTextStyles.labelLarge.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
