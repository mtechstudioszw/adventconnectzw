import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/order_model.dart';
import '../../services/order_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/staggered_reveal.dart';
import '../../widgets/screen_shell.dart';
import 'order_status_chip.dart';

/// Buyer-side order history. The thing the marketplace has never had:
/// a record that a purchase was even attempted.
class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  List<MarketOrder> _orders = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final orders = await OrderService.fetchMyOrders();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your orders. Pull to retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BrandedRefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            const ScreenHero(
              title: 'My orders',
              tagline: 'Marketplace',
              fallbackRoute: 'marketplace',
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 80),
                child: Center(child: BrandSpinner(size: 30)),
              )
            else if (_error != null)
              _Message(text: _error!)
            else if (_orders.isEmpty)
              _Message(
                text: 'No orders yet. Anything you request from a shop will '
                    'show up here.',
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.lg,
                  AppSpace.md,
                  AppSpace.lg,
                  AppSpace.xxl,
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < _orders.length; i++)
                      StaggeredReveal(
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: AppSpace.md),
                          child: _OrderRow(
                            order: _orders[i],
                            onTap: () async {
                              await context.pushNamed(
                                'order_details',
                                pathParameters: {'orderId': _orders[i].id},
                                extra: _orders[i],
                              );
                              if (mounted) _load();
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order, required this.onTap});

  final MarketOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.lgAll,
        child: Ink(
          decoration: BoxDecoration(
            color: context.palette.card,
            borderRadius: AppRadius.lgAll,
            boxShadow: AppShadows.card(context),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        order.sellerName ?? 'Seller',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleSmall.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    OrderStatusChip(status: order.status),
                  ],
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  '${order.reference} · ${order.itemCount} '
                  '${order.itemCount == 1 ? 'item' : 'items'}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: context.palette.textMuted,
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        order.items.map((e) => e.titleSnapshot).join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: context.palette.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Text(
                      order.formatSubtotal(),
                      style: AppTextStyles.titleMedium.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xxl,
        80,
        AppSpace.xxl,
        AppSpace.xxl,
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              color: AppColors.primaryBlue,
              size: 36,
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: context.palette.textMuted,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
