import 'package:flutter/material.dart';

import '../../services/ads/ad_impression_counter.dart';
import '../../services/billing/billing_config.dart';
import '../../services/billing/billing_service.dart';
import '../../services/premium_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../widgets/motion/motion.dart';
import '../../widgets/premium/premium_badge.dart';
import '../../widgets/screen_shell.dart';

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
    if (widget.autoLoad) {
      AdImpressionCounter.load();
      BillingService.init();
      BillingService.loadOffer();
    }
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
                Text(
                  until == null
                      ? 'Every ad is switched off across the app.'
                      : 'Every ad is switched off. Renews on '
                          '${_formatDate(until.toLocal())}.',
                  style: TextStyle(fontSize: 15, color: palette.textMuted),
                ),
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
              StaggeredReveal(index: 0, child: const _AdCostCard()),
              const SizedBox(height: 12),
              StaggeredReveal(index: 1, child: const _ComparisonCard()),
              const SizedBox(height: 12),
              StaggeredReveal(index: 2, child: _PriceAnchorCard(price: price)),
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
        _BuyBar(price: price, busy: busy, enabled: !unavailable),
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
                  'Cancel any time in the Play Store, and keep Premium until '
                  'the period you paid for ends. No refund games.',
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
            label: busy ? 'Switching ads off' : 'Go Premium — $price',
            icon: Icons.star_rounded,
            loading: busy,
            enabled: enabled,
            onPressed: BillingService.buy,
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            style: TextButton.styleFrom(foregroundColor: palette.textMuted),
            // Honest, and still framed: they are choosing the ads, not
            // choosing "no". One tap, no guilt screen, no second prompt.
            child: const Text('Keep watching ads for now'),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
//  Small shared pieces
// =====================================================================

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
