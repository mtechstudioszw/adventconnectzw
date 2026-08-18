import 'package:flutter/material.dart';

import '../../models/order_model.dart';
import '../../services/auth_service.dart';
import '../../services/order_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/screen_shell.dart';
import 'order_handoff.dart';
import 'order_status_chip.dart';

/// One order, from either side.
///
/// The same screen serves the buyer and the seller — they see the same
/// facts, and the available actions differ by who is looking. Keeping it
/// as one screen is what stops the two sides drifting into disagreeing
/// about what an order says.
class OrderDetailsScreen extends StatefulWidget {
  const OrderDetailsScreen({
    super.key,
    required this.orderId,
    this.initialOrder,
  });

  final String orderId;
  final MarketOrder? initialOrder;

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  MarketOrder? _order;
  bool _loading = true;

  /// Set when the fetch FAILED, as opposed to succeeding and finding
  /// nothing. Without it a dropped connection rendered "Order not found",
  /// which for something the member has paid for is both false and
  /// alarming.
  String? _error;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _order = widget.initialOrder;
    _loading = widget.initialOrder == null;
    _load();
  }

  Future<void> _load() async {
    try {
      final order = await OrderService.fetchById(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = order ?? _order;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load this order.';
      });
    }
  }

  bool get _isSeller =>
      _order != null && AuthService.currentUser?.id == _order!.sellerId;

  Future<void> _setStatus(String status) async {
    final order = _order;
    if (order == null) return;
    setState(() => _updating = true);
    try {
      await OrderService.updateStatus(order.id, status);
      if (!mounted) return;
      setState(() {
        _order = order.copyWith(status: status);
        _updating = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _updating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not update the order. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: _loading && order == null
          ? const Center(child: BrandSpinner(size: 32))
          : order == null
          ? (_error != null ? _loadFailed() : _notFound())
          : _buildBody(order),
    );
  }

  /// The fetch failed. Distinct from [_notFound]: the order is probably
  /// fine, we just could not reach it — so this offers a retry instead of
  /// telling the member their order is gone.
  Widget _loadFailed() {
    return ListView(
      children: [
        const ScreenHero(
          title: 'Order',
          fallbackRoute: 'marketplace',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: ErrorBanner(message: _error!, onRetry: _load),
        ),
      ],
    );
  }

  Widget _notFound() {
    return ListView(
      children: [
        const ScreenHero(
          title: 'Order not found',
          fallbackRoute: 'marketplace',
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpace.xxl),
          child: Text(
            'This order no longer exists, or you don\'t have access to it.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: context.palette.textMuted,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(MarketOrder order) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        ScreenHero(
          title: order.reference,
          tagline: _isSeller ? 'Incoming order' : 'Your order',
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
              _StatusCard(order: order, isSeller: _isSeller),
              const SizedBox(height: AppSpace.lg),
              _ItemsCard(order: order),
              if (order.note?.trim().isNotEmpty == true) ...[
                const SizedBox(height: AppSpace.lg),
                _NoteCard(note: order.note!.trim()),
              ],
              if (_isSeller) ...[
                const SizedBox(height: AppSpace.lg),
                _BuyerCard(order: order),
              ],
              const SizedBox(height: AppSpace.xl),
              ..._actionsFor(order),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _actionsFor(MarketOrder order) {
    if (_updating) {
      return const [Center(child: BrandSpinner(size: 26))];
    }
    if (!order.isOpen) {
      return [
        Text(
          order.isCompleted
              ? 'This order is complete.'
              : 'This order was cancelled.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySmall.copyWith(
            color: context.palette.textMuted,
          ),
        ),
      ];
    }

    if (_isSeller) {
      return [
        if (order.isPending)
          PrimaryGradientButton(
            label: 'Confirm order',
            icon: Icons.check_rounded,
            onTap: () => _setStatus('confirmed'),
          ),
        if (order.isConfirmed)
          PrimaryGradientButton(
            label: 'Mark as completed',
            icon: Icons.done_all_rounded,
            onTap: () => _setStatus('completed'),
          ),
        const SizedBox(height: AppSpace.sm),
        _OutlineAction(
          label: 'Decline order',
          icon: Icons.close_rounded,
          color: AppColors.red,
          onTap: () => _setStatus('cancelled'),
        ),
      ];
    }

    return [
      PrimaryGradientButton(
        label: 'Message the shop on WhatsApp',
        icon: Icons.chat_rounded,
        onTap: () => OrderHandoff.viaWhatsApp(context, order),
      ),
      const SizedBox(height: AppSpace.sm),
      _OutlineAction(
        label: 'Message in Advent Chat',
        icon: Icons.forum_outlined,
        color: AppColors.primaryBlue,
        onTap: () => OrderHandoff.viaAdventChat(context, order),
      ),
      const SizedBox(height: AppSpace.sm),
      _OutlineAction(
        label: 'Cancel this order',
        icon: Icons.close_rounded,
        color: AppColors.red,
        onTap: () => _setStatus('cancelled'),
      ),
    ];
  }
}

class _OutlineAction extends StatelessWidget {
  const _OutlineAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.md + 2),
        decoration: BoxDecoration(
          borderRadius: AppRadius.buttonAll,
          border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: AppSpace.sm),
            Text(
              label,
              style: AppTextStyles.buttonText.copyWith(
                color: color,
                fontSize: 14.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.order, required this.isSeller});

  final MarketOrder order;
  final bool isSeller;

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isSeller
                      ? (order.buyerName ?? 'A buyer')
                      : (order.sellerName ?? 'Seller'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              OrderStatusChip(status: order.status),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Text(
                'Total',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: context.palette.textMuted,
                ),
              ),
              const Spacer(),
              Text(
                order.formatSubtotal(),
                style: AppTextStyles.headlineSmall.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            'Payment and delivery are arranged directly between buyer and '
            'seller. Adventist Super App is not a party to the transaction.',
            style: AppTextStyles.bodySmall.copyWith(
              color: context.palette.textMuted,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.order});

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ITEMS',
            style: AppTextStyles.labelSmall.copyWith(
              color: context.palette.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          for (final line in order.items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: AppRadius.cardAll,
                    child: SizedBox(
                      width: 52,
                      height: 52,
                      child:
                          line.imageUrlSnapshot == null ||
                              line.imageUrlSnapshot!.isEmpty
                          ? DecoratedBox(
                              decoration: BoxDecoration(
                                color: context.palette.cardMuted,
                              ),
                              child: Icon(
                                Icons.image_outlined,
                                color: context.palette.textMuted,
                              ),
                            )
                          : CachedImage(
                              line.imageUrlSnapshot!,
                              fit: BoxFit.cover,
                            ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Snapshot, not a live lookup — this is what was
                        // ordered, whatever the listing says today.
                        Text(
                          line.titleSnapshot,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${line.formatPrice()} × ${line.qty}',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: context.palette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Text(
                    line.formatLineTotal(),
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w800,
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

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note});
  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.06),
        borderRadius: AppRadius.cardAll,
        border: Border.all(
          color: AppColors.primaryBlue.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'NOTE FROM THE BUYER',
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.primaryBlue,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            note,
            style: AppTextStyles.bodyMedium.copyWith(
              color: context.palette.text,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _BuyerCard extends StatelessWidget {
  const _BuyerCard({required this.order});
  final MarketOrder order;

  @override
  Widget build(BuildContext context) {
    final phone = order.buyerPhone?.trim();
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: AppRadius.lgAll,
        boxShadow: AppShadows.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BUYER',
            style: AppTextStyles.labelSmall.copyWith(
              color: context.palette.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            order.buyerName ?? 'Not provided',
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (phone != null && phone.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              phone,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
