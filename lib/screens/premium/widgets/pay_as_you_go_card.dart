import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/platform_flags.dart';
import '../../../services/billing/ai_pack_service.dart';
import '../../../services/billing/small_products.dart';
import '../../../services/billing/verified_plan_service.dart';
import '../../../services/premium_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/screen_shell.dart';
import '../../calls/widgets/call_pack_sheet.dart';

/// "Just need one thing?" (owner, 3 Nov 2026): the single features for about
/// a dollar each, for members who will never want a monthly bundle.
///
/// Each row goes straight to where that thing is bought — the gold tick to
/// its ID check, minutes to the minute packs, questions to Play. Boosts are
/// bought from the listing or job itself, so their row says where.
///
/// Never on iPhone ([kHidePayments]).
class PayAsYouGoCard extends StatefulWidget {
  const PayAsYouGoCard({super.key});

  @override
  State<PayAsYouGoCard> createState() => _PayAsYouGoCardState();
}

class _PayAsYouGoCardState extends State<PayAsYouGoCard> {
  bool _aiLive = false;

  @override
  void initState() {
    super.initState();
    AiPackService.state.addListener(_onAiPack);
    VerifiedPlanService.loadOffer().then((_) {
      if (mounted) setState(() {});
    });
    AiPackService.loadOffer().then((_) {
      if (mounted) {
        setState(() => _aiLive = AiPackService.state.value == AiPackFlow.ready);
      }
    });
  }

  @override
  void dispose() {
    AiPackService.state.removeListener(_onAiPack);
    super.dispose();
  }

  void _onAiPack() {
    if (!mounted) return;
    final s = AiPackService.state.value;
    final text = switch (s) {
      AiPackFlow.success =>
        '${SmallProducts.aiPackQuestions} questions added to Advent AI.',
      AiPackFlow.failed || AiPackFlow.pendingPayment =>
        AiPackService.message ?? "That didn't go through. Please try again.",
      _ => null,
    };
    if (text != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kHidePayments) return const SizedBox.shrink();
    final palette = context.palette;
    return ScreenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Just need one thing?',
            style: AppTextStyles.titleSmall.copyWith(
              color: palette.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Small one-off prices. No bundle needed.',
            style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<bool>(
            valueListenable: PremiumService.verifiedPlan,
            builder: (context, hasPlan, _) => _Row(
              icon: Icons.verified_rounded,
              iconColor: AppColors.goldAccent,
              title: 'Gold tick',
              subtitle: hasPlan
                  ? 'Your Verified plan is on'
                  : 'After a quick ID check · per month',
              price: hasPlan ? null : VerifiedPlanService.priceLabel,
              onTap: () => context.pushNamed('get_verified'),
            ),
          ),
          _Row(
            icon: Icons.call_rounded,
            title: 'Extra call minutes',
            subtitle: '5 or 20 hours, used after your daily minutes',
            price: 'from US\$0.99',
            onTap: () => CallPackSheet.show(context),
          ),
          if (_aiLive)
            _Row(
              icon: Icons.auto_awesome_rounded,
              title: '${SmallProducts.aiPackQuestions} Advent AI questions',
              subtitle: "Yours until you use them",
              price: AiPackService.priceLabel,
              onTap: AiPackService.buy,
            ),
          _Row(
            icon: Icons.storefront_rounded,
            title: 'Boost a listing or job',
            subtitle: 'Open your listing or job and tap Boost',
            price: 'from US\$1',
            onTap: null,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final String? price;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                icon,
                size: 20,
                color: iconColor ?? AppColors.primaryBlue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: palette.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (price != null) ...[
              const SizedBox(width: 8),
              Text(
                price!,
                style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (onTap != null)
              Icon(Icons.chevron_right_rounded, color: palette.textMuted),
          ],
        ),
      ),
    );
  }
}
