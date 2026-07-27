import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/cart_item_model.dart';
import '../../models/order_model.dart';
import '../../services/auth_service.dart';
import '../../services/cart_service.dart';
import '../../services/order_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/motion/staggered_reveal.dart';
import '../../widgets/screen_shell.dart';
import 'order_placed_screen.dart';

/// The basket.
///
/// The central fact this screen has to communicate honestly: a basket
/// spanning several shops is not one purchase. Each shop is a separate
/// conversation with a separate person, so the basket is presented
/// already split by shop, and checkout creates one order per shop.
///
/// Nothing here has been paid for. Every string says "request".
class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  bool _placing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: ValueListenableBuilder<int>(
        valueListenable: CartService.revision,
        builder: (context, revision, child) {
          final baskets = CartService.baskets;
          return Column(
            children: [
              ScreenHero(
                title: 'Your basket',
                tagline: 'Marketplace',
                fallbackRoute: 'marketplace',
                trailing: baskets.isEmpty
                    ? null
                    : ScreenHeroTrailing(
                        icon: Icons.delete_outline_rounded,
                        onTap: _confirmClear,
                      ),
              ),
              Expanded(
                child: baskets.isEmpty
                    ? _EmptyBasket(onBrowse: () => context.goNamed('marketplace'))
                    : _buildList(baskets),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: CartService.revision,
        builder: (context, revision, child) {
          final baskets = CartService.baskets;
          if (baskets.isEmpty) return const SizedBox.shrink();
          return _CheckoutBar(
            baskets: baskets,
            busy: _placing,
            onCheckout: _startCheckout,
          );
        },
      ),
    );
  }

  Widget _buildList(List<SellerBasket> baskets) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.md,
        AppSpace.lg,
        AppSpace.xxl,
      ),
      children: [
        if (baskets.length > 1) ...[
          _MultiShopNotice(shopCount: baskets.length),
          const SizedBox(height: AppSpace.lg),
        ],
        for (var i = 0; i < baskets.length; i++)
          StaggeredReveal(
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.lg),
              child: _ShopBasketCard(
                basket: baskets[i],
                onChangeQty: (item, qty) =>
                    CartService.setQty(item.productId, qty),
                onRemove: (item) => CartService.remove(item.productId),
                onOpenProduct: (item) => context.pushNamed(
                  'product_details',
                  pathParameters: {'id': item.productId},
                ),
              ),
            ),
          ),
        const SizedBox(height: AppSpace.sm),
        _NoPaymentNotice(),
      ],
    );
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
        title: Text('Empty your basket?', style: AppTextStyles.headlineSmall),
        content: Text(
          'Everything in the basket will be removed. Your saved listings '
          'are not affected.',
          style: AppTextStyles.bodyMedium.copyWith(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Keep',
              style: AppTextStyles.labelMedium.copyWith(
                color: ctx.palette.text,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: Text('Empty basket', style: AppTextStyles.labelLarge),
          ),
        ],
      ),
    );
    if (ok == true) await CartService.clear();
  }

  Future<void> _startCheckout() async {
    if (AuthService.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sign in to send an order request.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
      return;
    }
    final details = await showModalBottomSheet<_CheckoutDetails>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.sheet,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.sheetTop),
      builder: (ctx) => const _CheckoutSheet(),
    );
    if (details == null || !mounted) return;

    setState(() => _placing = true);
    final placed = <MarketOrder>[];
    final failed = <String>[];

    // One order per shop. Each is committed independently, so a shop
    // whose item just sold out doesn't cost the buyer the rest of the
    // basket — the successful shops are cleared, the failed one stays.
    for (final basket in CartService.baskets) {
      try {
        final id = await OrderService.placeBasket(
          basket,
          note: details.note,
          buyerName: details.name,
          buyerPhone: details.phone,
        );
        final order = await OrderService.fetchById(id);
        if (order != null) placed.add(order);
        await CartService.removeBasket(basket);
      } catch (e) {
        failed.add(basket.sellerName);
      }
    }

    if (!mounted) return;
    setState(() => _placing = false);

    if (placed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            failed.isEmpty
                ? 'Could not place the order. Try again.'
                : 'Could not place the order — some items may no longer be available.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderPlacedScreen(orders: placed, failedShops: failed),
      ),
    );
  }
}

class _CheckoutDetails {
  const _CheckoutDetails({this.name, this.phone, this.note});
  final String? name;
  final String? phone;
  final String? note;
}

/// Collects the few things a seller needs in order to actually fulfil:
/// who this is, how to call them back, and anything special about the
/// order. Deliberately short — every extra field here is a buyer lost.
class _CheckoutSheet extends StatefulWidget {
  const _CheckoutSheet();

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.palette.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Your details',
                style: AppTextStyles.headlineSmall.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                'Shared with the shops you\'re ordering from, so they can '
                'get back to you.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: context.palette.textMuted,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Your name',
                  hintText: 'So the seller knows who ordered',
                ),
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone / WhatsApp',
                  hintText: 'e.g. 077 123 4567',
                ),
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: _note,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: 'Delivery area, size, colour…',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              PrimaryGradientButton(
                label: 'Create order request',
                icon: Icons.check_rounded,
                onTap: () => Navigator.pop(
                  context,
                  _CheckoutDetails(
                    name: _name.text.trim().isEmpty ? null : _name.text.trim(),
                    phone: _phone.text.trim().isEmpty
                        ? null
                        : _phone.text.trim(),
                    note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.sm),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShopBasketCard extends StatelessWidget {
  const _ShopBasketCard({
    required this.basket,
    required this.onChangeQty,
    required this.onRemove,
    required this.onOpenProduct,
  });

  final SellerBasket basket;
  final void Function(CartItem item, int qty) onChangeQty;
  final void Function(CartItem item) onRemove;
  final void Function(CartItem item) onOpenProduct;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: AppRadius.lgAll,
        boxShadow: AppShadows.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.lg,
              AppSpace.lg,
              AppSpace.md,
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.storefront,
                    color: AppColors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Text(
                    basket.sellerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.titleSmall.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${basket.itemCount} ${basket.itemCount == 1 ? 'item' : 'items'}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: context.palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.palette.divider),
          for (final item in basket.items)
            _CartLine(
              item: item,
              onChangeQty: (qty) => onChangeQty(item, qty),
              onRemove: () => onRemove(item),
              onOpen: () => onOpenProduct(item),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.md,
              AppSpace.lg,
              AppSpace.lg,
            ),
            child: Row(
              children: [
                Text(
                  'Shop subtotal',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: context.palette.textMuted,
                  ),
                ),
                const Spacer(),
                Text(
                  basket.formatSubtotal(),
                  style: AppTextStyles.titleMedium.copyWith(
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

class _CartLine extends StatelessWidget {
  const _CartLine({
    required this.item,
    required this.onChangeQty,
    required this.onRemove,
    required this.onOpen,
  });

  final CartItem item;
  final ValueChanged<int> onChangeQty;
  final VoidCallback onRemove;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Pressable(
            onTap: onOpen,
            child: ClipRRect(
              borderRadius: AppRadius.cardAll,
              child: SizedBox(
                width: 64,
                height: 64,
                child: item.imageUrl == null || item.imageUrl!.isEmpty
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.palette.cardMuted,
                        ),
                        child: Icon(
                          Icons.image_outlined,
                          color: context.palette.textMuted,
                        ),
                      )
                    : CachedImage(item.imageUrl!, fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  item.formatPrice(),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: context.palette.textMuted,
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                Row(
                  children: [
                    _QtyStepper(
                      qty: item.qty,
                      onChanged: onChangeQty,
                    ),
                    const Spacer(),
                    Text(
                      item.formatLineTotal(),
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            visualDensity: VisualDensity.compact,
            tooltip: 'Remove',
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: context.palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Quantity control. Products carry no stock column, so there is nothing
/// to validate against — the only ceiling is the DB's own qty check.
class _QtyStepper extends StatelessWidget {
  const _QtyStepper({required this.qty, required this.onChanged});

  final int qty;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: context.palette.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(
            icon: qty <= 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
            onTap: () => onChanged(qty - 1),
          ),
          SizedBox(
            width: 28,
            child: Text(
              '$qty',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _StepButton(
            icon: Icons.add_rounded,
            onTap: qty >= CartItem.maxQty ? null : () => onChanged(qty + 1),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      pressedScale: 0.9,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Icon(
          icon,
          size: 16,
          color: onTap == null
              ? context.palette.textMuted.withValues(alpha: 0.4)
              : context.palette.text,
        ),
      ),
    );
  }
}

class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({
    required this.baskets,
    required this.busy,
    required this.onCheckout,
  });

  final List<SellerBasket> baskets;
  final bool busy;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    // Totals are per currency. Summing USD and ZWL into one number would
    // be a lie, so mixed baskets show each currency on its own line.
    final byCurrency = <String, double>{};
    for (final basket in baskets) {
      byCurrency.update(
        basket.currency,
        (v) => v + basket.subtotal,
        ifAbsent: () => basket.subtotal,
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: context.palette.card,
        boxShadow: AppShadows.floating(context),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.md,
            AppSpace.lg,
            AppSpace.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Total',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: context.palette.textMuted,
                    ),
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final entry in byCurrency.entries)
                        Text(
                          formatMoney(entry.value, entry.key),
                          style: AppTextStyles.headlineSmall.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              PrimaryGradientButton(
                label: baskets.length > 1
                    ? 'Send ${baskets.length} order requests'
                    : 'Send order request',
                icon: Icons.send_rounded,
                busy: busy,
                onTap: busy ? null : onCheckout,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MultiShopNotice extends StatelessWidget {
  const _MultiShopNotice({required this.shopCount});
  final int shopCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.07),
        borderRadius: AppRadius.cardAll,
        border: Border.all(
          color: AppColors.primaryBlue.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.store_mall_directory_outlined,
            color: AppColors.primaryBlue,
            size: 20,
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Text(
              'You\'re ordering from $shopCount shops. Each shop gets its own '
              'order and you\'ll arrange payment and delivery with them '
              'separately.',
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

class _NoPaymentNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.darkNavy.withValues(alpha: 0.04),
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: AppColors.darkNavy.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppColors.primaryBlue,
            size: 18,
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Text(
              'No payment happens in the app. Sending a request tells the '
              'shop what you want — you agree payment and delivery directly '
              'with them.',
              style: AppTextStyles.bodySmall.copyWith(
                color: context.palette.textMuted,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyBasket extends StatelessWidget {
  const _EmptyBasket({required this.onBrowse});
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_bag_outlined,
                color: AppColors.primaryBlue,
                size: 40,
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            Text(
              'Your basket is empty',
              style: AppTextStyles.headlineMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              'Add something from the marketplace and it will wait for you '
              'here — even offline.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: context.palette.textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            PrimaryGradientButton(
              label: 'Browse the marketplace',
              icon: Icons.storefront_outlined,
              onTap: onBrowse,
            ),
          ],
        ),
      ),
    );
  }
}
