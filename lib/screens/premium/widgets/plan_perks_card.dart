import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../services/billing/boost_service.dart';
import '../../../services/billing/premium_tier.dart';
import '../../../services/premium_service.dart';
import '../../../services/verification_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';

/// "What your plan includes" for a subscriber, with the two things that
/// need an action rather than just being on: the gold tick's ID check and
/// (Business) the monthly boosts.
class PlanPerksCard extends StatefulWidget {
  const PlanPerksCard({super.key});

  @override
  State<PlanPerksCard> createState() => _PlanPerksCardState();
}

class _PlanPerksCardState extends State<PlanPerksCard> {
  VerificationRequest? _tick;
  BoostCredits? _credits;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tick = await VerificationService.mine();
    final credits = PremiumService.tier == PremiumTier.business
        ? await BoostService.creditsLeft()
        : null;
    if (!mounted) return;
    setState(() {
      _tick = tick;
      _credits = credits;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tier = PremiumService.tier;
    final b = PremiumService.benefits;
    final tickLine = switch (_tick?.status) {
      VerifyStatus.approved => 'Gold tick: showing on your account',
      VerifyStatus.pending => 'Gold tick: we are checking your ID',
      _ => 'Gold tick: needs a quick ID check',
    };
    return _PerksShell(
      title: 'Your ${tier.label} plan includes',
      children: [
        _Perk(
          icon: Icons.verified_outlined,
          text: tickLine,
          action: _tick?.status == VerifyStatus.approved
              ? null
              : _tick?.status == VerifyStatus.pending
              ? 'View'
              : 'Get verified',
          onTap: () => context.pushNamed('get_verified').then((_) => _load()),
        ),
        _Perk(icon: Icons.block_outlined, text: 'No ads anywhere'),
        _Perk(
          icon: Icons.call_outlined,
          text: '${b.callAllowanceLabel} of calls a day',
        ),
        _Perk(
          icon: Icons.auto_awesome_outlined,
          text: '${b.aiQuestionsPerMonth} Advent AI questions a month',
        ),
        if (b.featuredShop)
          const _Perk(
            icon: Icons.storefront_outlined,
            text: 'Your approved shop is a Featured store in Marketplace',
          ),
        if (b.listingBoostsPerMonth > 0)
          _Perk(
            icon: Icons.trending_up_rounded,
            text: _credits == null
                ? '${b.listingBoostsPerMonth} listing boosts and '
                      '${b.jobBoostsPerMonth} featured jobs a month'
                : '${_credits!.listing} of ${b.listingBoostsPerMonth} listing '
                      'boosts and ${_credits!.job} of ${b.jobBoostsPerMonth} '
                      'featured jobs left this month',
          ),
        if (b.pageTick)
          const _Perk(
            icon: Icons.flag_outlined,
            text: 'Gold tick on a Page you created — verify it from the Page',
          ),
      ],
    );
  }
}

/// On the offer screen: the ID check is free and can be done before
/// paying, so the tick is ready the moment someone subscribes.
class GoldTickPromoCard extends StatelessWidget {
  const GoldTickPromoCard({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return _PerksShell(
      title: 'The gold tick',
      children: [
        Text(
          'Show people it is really you — useful for pastors, ministries, '
          'musicians and anyone who sells. Send an ID and a selfie; we '
          'check them and delete them. The tick shows while you have any '
          'plan. The check itself is free, so you can do it first.',
          style: AppTextStyles.bodySmall.copyWith(
            color: palette.textMuted,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('gold-tick-start'),
            onPressed: () => context.pushNamed('get_verified'),
            icon: const Icon(Icons.verified_outlined, size: 18),
            label: const Text('Start the ID check'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryBlue,
              side: const BorderSide(color: AppColors.primaryBlue),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PerksShell extends StatelessWidget {
  const _PerksShell({required this.title, required this.children});
  final String title;
  final List<Widget> children;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.titleSmall.copyWith(color: palette.text),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _Perk extends StatelessWidget {
  const _Perk({required this.icon, required this.text, this.action, this.onTap});
  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 20, color: palette.brandBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodySmall.copyWith(color: palette.text),
            ),
          ),
          if (action != null)
            TextButton(onPressed: onTap, child: Text(action!)),
        ],
      ),
    );
  }
}
