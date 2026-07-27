import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/order_model.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/motion/staggered_reveal.dart';
import '../../widgets/screen_shell.dart';
import 'order_handoff.dart';

/// The moment after checkout.
///
/// The order rows already exist — but the seller doesn't know yet. This
/// screen exists to make that second step unmissable, because an order
/// nobody is told about is just a row in a table.
class OrderPlacedScreen extends StatelessWidget {
  const OrderPlacedScreen({
    super.key,
    required this.orders,
    this.failedShops = const [],
  });

  final List<MarketOrder> orders;

  /// Shops whose order couldn't be created — usually because an item sold
  /// out between adding it and checking out. Their items are still in the
  /// basket.
  final List<String> failedShops;

  @override
  Widget build(BuildContext context) {
    final multi = orders.length > 1;
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          ScreenHero(
            title: multi
                ? '${orders.length} order requests created'
                : 'Order request created',
            tagline: 'Almost there',
            fallbackRoute: 'marketplace',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.sm,
              AppSpace.lg,
              AppSpace.xxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _NextStepNotice(shopCount: orders.length),
                if (failedShops.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.md),
                  _FailedNotice(shops: failedShops),
                ],
                const SizedBox(height: AppSpace.xl),
                for (var i = 0; i < orders.length; i++)
                  StaggeredReveal(
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.md),
                      child: _OrderHandoffCard(order: orders[i]),
                    ),
                  ),
                const SizedBox(height: AppSpace.md),
                OutlinedButton(
                  onPressed: () => context.goNamed('my_orders'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryBlue,
                    side: BorderSide(
                      color: AppColors.primaryBlue.withValues(alpha: 0.4),
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpace.lg - 2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.buttonAll,
                    ),
                  ),
                  child: Text('View my orders', style: AppTextStyles.labelLarge),
                ),
                const SizedBox(height: AppSpace.sm),
                TextButton(
                  onPressed: () => context.goNamed('marketplace'),
                  child: Text(
                    'Back to marketplace',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: context.palette.textMuted,
                    ),
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

class _OrderHandoffCard extends StatelessWidget {
  const _OrderHandoffCard({required this.order});

  final MarketOrder order;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: AppRadius.lgAll,
        boxShadow: AppShadows.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.storefront,
                  color: AppColors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.sellerName ?? 'Seller',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${order.reference} · ${order.itemCount} '
                      '${order.itemCount == 1 ? 'item' : 'items'} · '
                      '${order.formatSubtotal()}',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: context.palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          PrimaryGradientButton(
            label: 'Send on WhatsApp',
            icon: Icons.chat_rounded,
            onTap: () => OrderHandoff.viaWhatsApp(context, order),
          ),
          const SizedBox(height: AppSpace.sm),
          Pressable(
            onTap: () => OrderHandoff.viaAdventChat(context, order),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.md + 2),
              decoration: BoxDecoration(
                borderRadius: AppRadius.buttonAll,
                border: Border.all(
                  color: AppColors.primaryBlue.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.forum_outlined,
                    color: AppColors.primaryBlue,
                    size: 18,
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Text(
                    'Send in Advent Chat',
                    style: AppTextStyles.buttonText.copyWith(
                      color: AppColors.primaryBlue,
                      fontSize: 14.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NextStepNotice extends StatelessWidget {
  const _NextStepNotice({required this.shopCount});
  final int shopCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.successGreen.withValues(alpha: 0.08),
        borderRadius: AppRadius.cardAll,
        border: Border.all(
          color: AppColors.successGreen.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            color: AppColors.successGreen,
            size: 20,
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Text(
              shopCount > 1
                  ? 'Saved to your orders. Now send each shop their request '
                        'so they know it\'s waiting.'
                  : 'Saved to your orders. Now send it to the shop so they '
                        'know it\'s waiting.',
              style: AppTextStyles.bodySmall.copyWith(
                color: context.palette.text,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FailedNotice extends StatelessWidget {
  const _FailedNotice({required this.shops});
  final List<String> shops;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.07),
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: AppColors.red.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.red,
            size: 20,
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Text(
              'Couldn\'t create the order for ${shops.join(', ')} — an item '
              'may have just sold. Those items are still in your basket.',
              style: AppTextStyles.bodySmall.copyWith(
                color: context.palette.text,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
