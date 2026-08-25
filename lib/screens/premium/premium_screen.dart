import 'package:flutter/material.dart';

import '../../services/ads/ad_impression_counter.dart';
import '../../services/ai/ai_balance_service.dart';
import '../../services/ai/ai_tiers.dart';
import '../../services/billing/billing_config.dart';
import '../../services/billing/billing_service.dart';
import '../../services/premium_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/advent_ai_bubble.dart';
import '../../widgets/advent_ai_mark.dart';
import '../../widgets/motion/motion.dart';
import '../../widgets/premium/premium_badge.dart';
import '../../widgets/screen_shell.dart';
import 'widgets/advent_ai_offer_card.dart';
import 'widgets/plan_picker.dart';

/// "Go Premium".
///
/// The founder's brief: don't ask politely, show people what staying on
/// the free tier actually costs them. So the argument here is built from
/// things that are TRUE and personal rather than from adjectives —
/// chiefly [AdImpressionCounter], the real number of ads this device has
/// shown them. A number someone recognises persuades; a slogan doesn't.
///
/// Where the line is drawn: loss framing yes, deception no. No fake
/// countdown, no invented discount, no disguised decline button, no
/// pretending the free tier will be taken away. The comparison is
/// accurate, the price is the store's own localised string, and
/// declining is one clear tap.
class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key, this.autoLoad = true});

  /// Test seam: skip the store round-trip in widget tests.
  final bool autoLoad;

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  @override
  void initState() {
    super.initState();
    // No floating Advent AI button on the screen that sells Advent AI
    // (founder, 25 Aug 2026). It lands squarely on the plan picker and
    // the buy bar — the two controls this screen exists to deliver a tap
    // to — and tapping it navigates AWAY from the purchase. `/premium`
    // is on AdventAiBubble.blockedPrefixes as well; this is the half
    // that holds if the screen is ever shown as a sheet, where the
    // router's location stays whatever was underneath.
    AdventAiBubble.suppress();
    if (widget.autoLoad) {
      AdImpressionCounter.load();
      BillingService.init();
      BillingService.loadOffer();
    }
  }

  @override
  void dispose() {
    AdventAiBubble.unsuppress();
    super.dispose();
  }

  bool get _busy =>
      BillingService.state.value == PremiumFlowState.purchasing ||
      BillingService.state.value == PremiumFlowState.verifying;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ValueListenableBuilder<bool>(
        valueListenable: PremiumService.isPremium,
        builder: (context, isPremium, _) {
          return ValueListenableBuilder<PremiumFlowState>(
            valueListenable: BillingService.state,
            builder: (context, flow, _) {
              return Column(
                children: [
                  ScreenHero(
                    title: isPremium ? 'Your Premium' : 'Go Premium',
                    tagline: isPremium
                        ? 'Thank you for supporting Adventist Super App'
                        : null,
                    fallbackRoute: '/profile',
                  ),
                  Expanded(
                    child: SafeArea(
                      top: false,
                      child: isPremium
                          ? _ActiveView(flow: flow)
                          : _OfferView(flow: flow, busy: _busy),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// =====================================================================
//  Already subscribed
// =====================================================================

class _ActiveView extends StatelessWidget {
  const _ActiveView({required this.flow});

  final PremiumFlowState flow;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final until = PremiumService.premiumUntil;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        StaggeredReveal(
          index: 0,
          child: _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PremiumBadge(size: 20, showLabel: true),
                const SizedBox(height: 14),
                Text(
                  'Premium is active',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: 6),
                // Leads with Advent AI, not with ads.
                //
                // This line used to say only "Every ad is switched off",
                // which described Premium entirely by what it removes —
                // the same negative framing the offer screen was rebuilt
                // to get away from. A member who has just paid should be
                // told what they now HAVE. Ads follow as a second clause
                // because it is still true and still worth saying.
                Text(
                  '${AiTiers.premium.monthlyMessages} Advent AI questions '
                  'a month, and no ads anywhere in the app.'
                  '${until == null ? '' : ' Renews on '
                      '${_formatDate(until.toLocal())}.'}',
                  style: TextStyle(
                    fontSize: 15,
                    color: palette.textMuted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                // Their live remaining allowance, so "active" is a fact
                // they can see rather than a claim. A subscriber who
                // cannot tell whether the thing they pay for is working
                // is a subscriber who cancels.
                const _ActiveAllowanceRow(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        StaggeredReveal(
          index: 1,
          child: _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Manage or cancel',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your subscription is billed by Google Play. Cancel any '
                  'time in the Play Store — you keep Premium until the end '
                  'of the period you have already paid for.',
                  style: TextStyle(fontSize: 14, color: palette.textMuted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        StaggeredReveal(
          index: 2,
          child: TextButton(
            onPressed: BillingService.restore,
            child: const Text('Restore on another device'),
          ),
        ),
      ],
    );
  }
}

// =====================================================================
//  The pitch
// =====================================================================

class _OfferView extends StatelessWidget {
  const _OfferView({required this.flow, required this.busy});

  final PremiumFlowState flow;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final price = BillingService.offer?.price ?? BillingConfig.fallbackPriceLabel;
    final unavailable = flow == PremiumFlowState.unavailable;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              // Advent AI leads.
              //
              // This screen used to open with the ad-count card — the
              // "honest gut-punch" of how many ads you had sat through.
              // Opening on a grievance sells by making someone feel bad
              // about their own use of the app, and it left Premium with
              // nothing positive to offer.
              //
              // Advent AI is the first thing Premium has ever had that a
              // member actually WANTS, so it goes first and the ad card
              // moves below the fold as supporting evidence.
              StaggeredReveal(index: 0, child: const AdventAiOfferCard()),
              const SizedBox(height: 12),
              // The choice, right under what they are choosing.
              StaggeredReveal(
                index: 1,
                child: ValueListenableBuilder<int>(
                  valueListenable: BillingService.planRevision,
                  builder: (context, _, child) => PlanPicker(
                    offers: BillingService.offers,
                    selected: BillingService.offer,
                    onSelect: BillingService.selectPlan,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              StaggeredReveal(index: 2, child: const _ComparisonCard()),
              const SizedBox(height: 12),
              StaggeredReveal(index: 3, child: const _AdCostCard()),
              const SizedBox(height: 12),
              StaggeredReveal(index: 4, child: _PriceAnchorCard(price: price)),
              if (flow == PremiumFlowState.pendingPayment) ...[
                const SizedBox(height: 12),
                StaggeredReveal(
                  index: 3,
                  child: _NoticeCard(
                    icon: Icons.schedule_rounded,
                    tone: AppColors.primaryBlue,
                    title: 'Payment being confirmed',
                    body: 'Your payment method needs a moment to clear. '
                        'Premium switches on by itself as soon as it does — '
                        'you can close the app.',
                  ),
                ),
              ],
              if (BillingService.errorMessage != null) ...[
                const SizedBox(height: 12),
                StaggeredReveal(
                  index: 3,
                  child: _NoticeCard(
                    icon: unavailable
                        ? Icons.info_outline_rounded
                        : Icons.error_outline_rounded,
                    tone: unavailable ? palette.textMuted : AppColors.red,
                    title: unavailable ? 'Not available here' : 'That didn\'t go through',
                    body: BillingService.errorMessage!,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: BillingService.restore,
                  child: const Text('I already subscribed — restore'),
                ),
              ),
            ],
          ),
        ),
        // Rebuilds with the picker: the label carries the price the
        // member is about to be charged, and the two must never disagree.
        ValueListenableBuilder<int>(
          valueListenable: BillingService.planRevision,
          builder: (context, _, child) => _BuyBar(
            price: BillingService.offer?.price ??
                BillingConfig.fallbackPriceLabel,
            busy: busy,
            enabled: !unavailable,
          ),
        ),
      ],
    );
  }
}

/// The honest gut-punch: a real count of the ads this person has sat
/// through. No number yet (a brand-new install) falls back to the plain
/// promise rather than showing a hollow "0".
class _AdCostCard extends StatelessWidget {
  const _AdCostCard();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ValueListenableBuilder<int>(
      valueListenable: AdImpressionCounter.revision,
      builder: (context, _, _) {
        final seen = AdImpressionCounter.count;
        final since = AdImpressionCounter.since;
        return _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (seen >= 10) ...[
                _CountUp(
                  value: seen,
                  style: TextStyle(
                    fontSize: 44,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  since == null
                      ? 'ads shown to you in Adventist Super App.'
                      : 'ads shown to you since '
                          '${_formatDate(since)}.',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Every banner between posts. Every full-screen ad after a '
                  'story. Every one that opens when you come back to the app. '
                  'Premium switches off all of them — and stops the app even '
                  'asking for them, so it uses less data and less battery.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: palette.textMuted,
                  ),
                ),
              ] else ...[
                Text(
                  'Read, watch and pray without interruption',
                  style: TextStyle(
                    fontSize: 22,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Premium removes every ad in Adventist Super App — banners, '
                  'full-screen ads, the one when you open the app. It also '
                  'stops the app requesting them at all, so it uses less '
                  'data and less battery.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Free vs Premium, side by side. The free column is deliberately the
/// one that reads as a list of losses — because it is one — but every
/// line on it is factually what the free tier does today.
class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard();

  static const _rows = <({String label, String free, bool premiumHas})>[
    (label: 'Banner ads between posts', free: 'Shown', premiumHas: false),
    (label: 'Full-screen ads after stories', free: 'Shown', premiumHas: false),
    (label: 'Ad when you open the app', free: 'Shown', premiumHas: false),
    (label: 'Ads in the feed', free: 'Shown', premiumHas: false),
    (label: 'Quiz hints', free: 'Watch an ad', premiumHas: true),
    (label: 'Premium badge on your name', free: 'No', premiumHas: true),
    (label: 'Supports the app', free: 'No', premiumHas: true),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(flex: 5, child: SizedBox.shrink()),
              Expanded(
                flex: 3,
                child: Text(
                  'Free',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: palette.textMuted,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'Premium',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.goldAccent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final row in _rows) ...[
            Divider(height: 17, color: palette.divider),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    row.label,
                    style: TextStyle(fontSize: 14, color: palette.text),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    row.free,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: palette.textMuted,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Icon(
                    row.premiumHas
                        ? Icons.check_circle_rounded
                        : Icons.block_rounded,
                    size: 20,
                    color: row.premiumHas
                        ? AppColors.successGreen
                        : AppColors.goldAccent,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Price anchoring, done with arithmetic rather than adjectives.
class _PriceAnchorCard extends StatelessWidget {
  const _PriceAnchorCard({required this.price});

  final String price;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return _Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.savings_rounded,
              color: AppColors.goldAccent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$price a ${BillingConfig.periodLabel}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  // "No refund games" is retired (founder, 23 Aug 2026).
                  // It implies other people play games, and it puts the
                  // idea of a dispute in someone's head at the exact
                  // moment they are deciding to trust us. The reassurance
                  // is the same without the swipe.
                  'Cancel any time in the Play Store, and keep Premium '
                  'until the period you paid for ends.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return _Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tone, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The commit bar. Sticky, so the price and the button are always in
/// reach however far down the page the user has read.
class _BuyBar extends StatelessWidget {
  const _BuyBar({
    required this.price,
    required this.busy,
    required this.enabled,
  });

  final String price;
  final bool busy;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border(top: BorderSide(color: palette.divider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LoadingButton(
            // The button states the act, not the wait. "Verifying…" would
            // be telling the user to hold on; the spinner already says
            // that, and the label should say what they're getting.
            //
            // "Switching ads off" is retired: Premium's headline benefit
            // is Advent AI now, and naming the removal of an annoyance
            // as the thing being bought is what made this screen feel
            // like a squeeze.
            label: busy ? 'Setting up Premium' : 'Go Premium — $price',
            icon: Icons.star_rounded,
            loading: busy,
            enabled: enabled,
            onPressed: BillingService.buy,
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            style: TextButton.styleFrom(foregroundColor: palette.textMuted),
            // Plainly "not now".
            //
            // This used to read "Keep watching ads for now", defended as
            // "they are choosing the ads, not choosing no". That is
            // confirmshaming: making someone say something unpleasant
            // about themselves in order to decline. It is a dark pattern
            // the brief bans outright (§27), and in a church app it is
            // the single line most likely to leave a member feeling the
            // app is working against them.
            //
            // Declining must cost nothing and say nothing about them.
            child: const Text('Not now'),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
//  Small shared pieces
// =====================================================================

/// A subscriber's live Advent AI allowance, on the Premium screen.
///
/// "Premium is active" is a claim. This is evidence: a real number that
/// moves as they use it. Somebody who cannot tell whether the thing they
/// pay for is working is somebody who cancels — and this is the screen
/// they open when they are wondering.
///
/// Renders nothing at all until the balance is known, rather than
/// flashing a hollow "0 of 500" while the fetch is in flight.
class _ActiveAllowanceRow extends StatefulWidget {
  const _ActiveAllowanceRow();

  @override
  State<_ActiveAllowanceRow> createState() => _ActiveAllowanceRowState();
}

class _ActiveAllowanceRowState extends State<_ActiveAllowanceRow> {
  @override
  void initState() {
    super.initState();
    // The member may have arrived straight from a purchase, so the
    // cached figure can predate their subscription by seconds.
    AiBalanceService.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return ValueListenableBuilder<AiBalance>(
      valueListenable: AiBalanceService.balance,
      builder: (context, balance, _) {
        if (balance.grant <= 0) return const SizedBox.shrink();

        // The ALLOWANCE, not the total. `balance.remaining` also carries
        // the free sample, and a subscriber holding 8 unused free units
        // read "508 of 500 left" here — see AiBalance.allowanceRemaining.
        final left = balance.allowanceRemaining;
        final used = balance.allowanceUsed;
        final fraction = (left / balance.grant).clamp(0.0, 1.0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(AdventAiBrand.icon,
                    size: 14, color: AppColors.goldAccent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Advent AI this month',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: palette.text,
                    ),
                  ),
                ),
                Text(
                  '$left of ${balance.grant} left',
                  style: TextStyle(fontSize: 13, color: palette.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(100),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 6,
                backgroundColor: palette.chipBg,
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
              ),
            ),
            if (used > 0) ...[
              const SizedBox(height: 6),
              Text(
                // Their own usage, stated warmly. Not a warning — a
                // subscriber running low is a subscriber getting value,
                // and the tone should say so.
                'You have asked $used question${used == 1 ? '' : 's'} '
                'this month.',
                style: TextStyle(fontSize: 12, color: palette.textMuted),
              ),
            ],
            if (balance.freeRemaining > 0) ...[
              const SizedBox(height: 6),
              Text(
                // Without this the bar looks broken. A subscriber who
                // still holds free units spends THOSE first
                // (ai_spend_unit is free-first), so their next few
                // questions move nothing on the meter above. Saying so
                // is the difference between "stuck" and "extra".
                'Plus ${balance.freeRemaining} free question'
                '${balance.freeRemaining == 1 ? '' : 's'} still to use — '
                'those go first.',
                style: TextStyle(fontSize: 12, color: palette.textMuted),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Counts a number up on first paint. The motion tracks the data — the
/// number climbing IS the point being made — and it is short enough
/// that nobody waits for it.
class _CountUp extends StatelessWidget {
  const _CountUp({required this.value, required this.style});

  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text('${v.round()}', style: style),
    );
  }
}

String _formatDate(DateTime d) {
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}
