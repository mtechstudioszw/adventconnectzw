import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/order_model.dart';
import '../../models/product_model.dart';
import '../../models/seller_model.dart';
import '../../services/order_service.dart';
import '../../services/seller_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/home/section_header.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/motion/staggered_reveal.dart';
import '../../widgets/screen_shell.dart';
import '../marketplace/order_status_chip.dart';

/// Entry point into the seller flow. States:
///   * no seller row → CTA to set up the store
///   * pending / rejected → banner explaining state, no dashboard
///   * approved → orders, stats, listings, store settings
///
/// The old version was a settings page wearing a dashboard's name: its
/// three "stats" were two counts the seller typed in themselves plus a
/// rating that is blank for every seller in the database. Now that orders
/// exist, the top of the screen answers the only question a seller
/// actually opens this for — has anyone ordered anything?
class SellerDashboardScreen extends StatefulWidget {
  const SellerDashboardScreen({super.key});

  @override
  State<SellerDashboardScreen> createState() => _SellerDashboardScreenState();
}

class _SellerDashboardScreenState extends State<SellerDashboardScreen> {
  Seller? _seller;
  List<Product> _products = const [];
  List<MarketOrder> _orders = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (mounted && !_loading) setState(() => _error = null);
    try {
      final seller = await SellerService.fetchMySellerProfile();
      List<Product> products = const [];
      List<MarketOrder> orders = const [];
      if (seller != null && seller.isApproved) {
        // Orders are non-essential to rendering the page — a failure
        // there must not blank out the listings the seller came to see.
        products = await SellerService.fetchMyProducts();
        try {
          orders = await OrderService.fetchSellerOrders();
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _seller = seller;
        _products = products;
        _orders = orders;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your store. Pull to retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final seller = _seller;
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: BrandedRefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: _bootstrap,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            // Flat header, matching every other secondary screen. The old
            // curved ClipPath hero was the one thing screen_shell.dart
            // explicitly says not to build.
            ScreenHero(
              title: seller?.businessName.isNotEmpty == true
                  ? seller!.businessName
                  : 'Your store',
              tagline: 'Seller dashboard',
              subtitle: _heroSubtitle(),
              fallbackRoute: 'profile',
              trailing: seller?.isApproved == true
                  ? ScreenHeroTrailing(
                      icon: Icons.add,
                      onTap: () async {
                        await context.pushNamed('add_product');
                        if (mounted) _bootstrap();
                      },
                    )
                  : null,
            ),
            _buildBody(),
            const SizedBox(height: AppSpace.xxl),
          ],
        ),
      ),
    );
  }

  String _heroSubtitle() {
    final seller = _seller;
    if (seller == null) return 'Open a storefront on the marketplace.';
    if (seller.isPending) return 'Application under review.';
    if (seller.isFinalReviewPending) return 'Final review in progress.';
    if (seller.isRejectedFinal) return 'Marketplace access closed.';
    if (seller.isRejected) return 'Application needs your attention.';
    final pending = _orders.where((o) => o.isPending).length;
    if (pending > 0) {
      return '$pending order${pending == 1 ? '' : 's'} waiting for you.';
    }
    return 'Listings, orders and store settings in one place.';
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(child: BrandSpinner(size: 30)),
      );
    }
    if (_error != null) return _pad(_ErrorCard(message: _error!));
    final seller = _seller;
    if (seller == null) return _pad(_buildEmptyState());
    if (seller.isPending) return _pad(_buildPendingState(seller));
    if (seller.isFinalReviewPending) return _pad(_buildFinalReviewState(seller));
    if (seller.isRejectedFinal) return _pad(_buildRejectedFinalState(seller));
    if (seller.isRejected) return _pad(_buildRejectedState(seller));
    return _buildApprovedDashboard(seller);
  }

  Widget _pad(Widget child) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpace.lg,
      AppSpace.md,
      AppSpace.lg,
      0,
    ),
    child: child,
  );

  Widget _buildApprovedDashboard(Seller seller) {
    final stats = SellerService.statsFor(_products);
    final openOrders = _orders.where((o) => o.isOpen).toList();
    final views = _products.fold<int>(0, (sum, p) => sum + p.viewCount);
    // Revenue counts completed orders only. Counting pending requests as
    // money would flatter the number and mislead the seller.
    final earned = <String, double>{};
    for (final o in _orders.where((o) => o.isCompleted)) {
      earned.update(
        o.currency,
        (v) => v + o.subtotal,
        ifAbsent: () => o.subtotal,
      );
    }

    var index = 0;
    Widget reveal(Widget child) =>
        StaggeredReveal(index: index++, child: child);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pad(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              reveal(_StoreSummaryCard(seller: seller, showStatusChip: true)),
              const SizedBox(height: AppSpace.lg),
              reveal(
                _MetricsGrid(
                  live: stats.available,
                  hidden: stats.hidden,
                  views: views,
                  openOrders: openOrders.length,
                  earned: earned,
                ),
              ),
            ],
          ),
        ),

        // Orders lead. This is the answer to "did anything happen?"
        reveal(
          _OrdersSection(
            orders: _orders,
            onOpen: (order) async {
              await context.pushNamed(
                'order_details',
                pathParameters: {'orderId': order.id},
                extra: order,
              );
              if (mounted) _bootstrap();
            },
          ),
        ),

        reveal(
          _ListingsSection(
            products: _products,
            onManage: () async {
              await context.pushNamed('manage_products');
              if (mounted) _bootstrap();
            },
            onAdd: () async {
              await context.pushNamed('add_product');
              if (mounted) _bootstrap();
            },
          ),
        ),

        const SizedBox(height: AppSpace.xl),
        _pad(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              reveal(
                _QuickActionsCard(
                  onAdd: () async {
                    await context.pushNamed('add_product');
                    if (mounted) _bootstrap();
                  },
                  onManage: () async {
                    await context.pushNamed('manage_products');
                    if (mounted) _bootstrap();
                  },
                  onEdit: () async {
                    await context.pushNamed('edit_store', extra: seller);
                    if (mounted) _bootstrap();
                  },
                  onStorefront: () => context.pushNamed(
                    'seller_profile',
                    pathParameters: {'userId': seller.authUserId},
                    extra: seller,
                  ),
                ),
              ),
              if (seller.observesSabbath) ...[
                const SizedBox(height: AppSpace.lg),
                reveal(
                  _SabbathBadge(
                    notice: seller.sabbathNoticeText ?? 'Observes the Sabbath.',
                  ),
                ),
              ],
              const SizedBox(height: AppSpace.lg),
              reveal(_DangerZoneCard(onDelete: () => _confirmDeleteStore(seller))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: AppRadius.lgAll,
        boxShadow: AppShadows.card(context),
      ),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.storefront,
              color: AppColors.white,
              size: 44,
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          Text(
            'Become a seller',
            textAlign: TextAlign.center,
            style: AppTextStyles.headlineMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            'List products to the SDA community across Zimbabwe. We review '
            'applications within 1–3 days.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: context.palette.textMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          PrimaryGradientButton(
            label: 'Start setup',
            icon: Icons.arrow_forward,
            onTap: () async {
              // Self-serve flow routes through the Code of Conduct gate
              // first (patch_022 enforces this at the DB layer too).
              await context.pushNamed('marketplace_guidelines');
              if (mounted) _bootstrap();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPendingState(Seller seller) {
    return Column(
      children: [
        const _StatusBanner(
          tone: _BannerTone.info,
          icon: Icons.hourglass_top,
          title: 'Awaiting admin approval',
          message:
              'An admin is reviewing your store profile. You\'ll get a '
              'notification the moment it\'s approved — usually within a day '
              'or two. Once approved you can list products without further '
              'per-product reviews.',
        ),
        const SizedBox(height: AppSpace.lg),
        _StoreSummaryCard(seller: seller),
        const SizedBox(height: AppSpace.lg),
        const _ChecklistCard(
          items: [
            'Photo and clear business name',
            'Province + city set',
            'Phone or WhatsApp reachable',
          ],
        ),
      ],
    );
  }

  Widget _buildRejectedState(Seller seller) {
    final attemptsLeft = seller.attemptsRemaining;
    final isLastChance = attemptsLeft <= 1;
    return Column(
      children: [
        _StatusBanner(
          tone: _BannerTone.danger,
          icon: Icons.report_problem_outlined,
          title: isLastChance
              ? 'Application not approved — final attempt remaining'
              : 'Application not approved',
          message: seller.rejectionReason?.trim().isNotEmpty == true
              ? seller.rejectionReason!
              : 'Reach out via support if you\'d like more detail. Update your '
                    'store details below and resubmit — '
                    '${attemptsLeft == 1 ? 'this is your last chance' : '$attemptsLeft attempts remaining'} '
                    'before marketplace access is closed.',
        ),
        const SizedBox(height: AppSpace.lg),
        _StoreSummaryCard(seller: seller),
        const SizedBox(height: AppSpace.lg),
        PrimaryGradientButton(
          label: 'Edit & resubmit',
          icon: Icons.edit_outlined,
          onTap: () async {
            await context.pushNamed('edit_store', extra: seller);
            if (mounted) _bootstrap();
          },
        ),
      ],
    );
  }

  Widget _buildFinalReviewState(Seller seller) {
    return Column(
      children: [
        const _StatusBanner(
          tone: _BannerTone.info,
          icon: Icons.gavel_outlined,
          title: 'Final review in progress',
          message:
              'This is your third and final application. An admin is reviewing '
              'your updated details — you\'ll get a notification when there\'s '
              'a decision.',
        ),
        const SizedBox(height: AppSpace.lg),
        _StoreSummaryCard(seller: seller),
      ],
    );
  }

  Widget _buildRejectedFinalState(Seller seller) {
    return Column(
      children: [
        const _StatusBanner(
          tone: _BannerTone.danger,
          icon: Icons.block_outlined,
          title: 'Marketplace access closed',
          message:
              'Your seller application has been rejected 3 times. You are no '
              'longer eligible to apply to become a marketplace seller. '
              'Please contact support if you need more information.',
        ),
        const SizedBox(height: AppSpace.lg),
        _StoreSummaryCard(seller: seller),
      ],
    );
  }

  Future<void> _confirmDeleteStore(Seller seller) async {
    // Two-step confirm — destructive and irreversible (every product goes
    // with it).
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
        title: Text('Delete your store?', style: AppTextStyles.headlineSmall),
        content: Text(
          '"${seller.businessName}" and every product you\'ve listed will be '
          'removed from the marketplace. This cannot be undone.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: ctx.palette.text,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: AppTextStyles.labelMedium.copyWith(color: ctx.palette.text),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: Text('Delete store', style: AppTextStyles.labelLarge),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SellerService.deleteMySellerProfile();
      if (!mounted) return;
      setState(() {
        _seller = null;
        _products = const [];
        _orders = const [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.successGreen,
          content: Text(
            'Store deleted.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not delete the store. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }
}

/// Four tiles, because a seller's questions are "is anyone buying?",
/// "is anyone looking?", "what's live?" and "what have I made?".
class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({
    required this.live,
    required this.hidden,
    required this.views,
    required this.openOrders,
    required this.earned,
  });

  final int live;
  final int hidden;
  final int views;
  final int openOrders;
  final Map<String, double> earned;

  @override
  Widget build(BuildContext context) {
    final earnedLabel = earned.isEmpty
        ? '—'
        : earned.entries
              .map((e) => formatMoney(e.value, e.key))
              .join(' + ');
    return Row(
      children: [
        Expanded(
          child: _MetricTile(
            value: '$openOrders',
            label: 'OPEN ORDERS',
            icon: Icons.receipt_long_outlined,
            highlight: openOrders > 0,
          ),
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: _MetricTile(
            value: earnedLabel,
            label: 'COMPLETED',
            icon: Icons.payments_outlined,
          ),
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: _MetricTile(
            value: '$views',
            label: 'VIEWS',
            icon: Icons.visibility_outlined,
          ),
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: _MetricTile(
            value: '$live',
            label: 'LIVE',
            icon: Icons.inventory_2_outlined,
            sub: hidden > 0 ? '$hidden hidden' : null,
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.value,
    required this.label,
    required this.icon,
    this.sub,
    this.highlight = false,
  });

  final String value;
  final String label;
  final IconData icon;
  final String? sub;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final accent = highlight ? AppColors.goldAccent : AppColors.primaryBlue;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.sm,
        vertical: AppSpace.md,
      ),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.goldAccent.withValues(alpha: 0.10)
            : context.palette.card,
        borderRadius: AppRadius.cardAll,
        border: highlight
            ? Border.all(color: AppColors.goldAccent.withValues(alpha: 0.35))
            : null,
        boxShadow: highlight ? null : AppShadows.card(context),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.w800,
                color: context.palette.text,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            label,
            textAlign: TextAlign.center,
            style: AppTextStyles.labelSmall.copyWith(
              color: context.palette.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          if (sub != null)
            Text(
              sub!,
              style: AppTextStyles.labelSmall.copyWith(
                color: context.palette.textMuted,
              ),
            ),
        ],
      ),
    );
  }
}

class _OrdersSection extends StatelessWidget {
  const _OrdersSection({required this.orders, required this.onOpen});

  final List<MarketOrder> orders;
  final void Function(MarketOrder) onOpen;

  @override
  Widget build(BuildContext context) {
    final open = orders.where((o) => o.isOpen).toList();
    final shown = open.isNotEmpty ? open : orders;
    return HomeSection(
      title: 'Orders',
      action: orders.isEmpty ? null : 'All',
      onAction: orders.isEmpty ? null : () => context.pushNamed('my_orders'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
        child: orders.isEmpty
            ? _EmptyPanel(
                icon: Icons.receipt_long_outlined,
                title: 'No orders yet',
                message:
                    'When someone sends an order request it lands here, with '
                    'their name and phone number.',
              )
            : Column(
                children: [
                  for (final order in shown.take(4))
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.md),
                      child: _OrderRow(
                        order: order,
                        onTap: () => onOpen(order),
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
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpace.lg),
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: AppRadius.lgAll,
          boxShadow: AppShadows.card(context),
          border: order.isPending
              ? Border.all(color: AppColors.goldAccent.withValues(alpha: 0.4))
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.buyerName ?? 'A buyer',
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
            const SizedBox(height: AppSpace.sm),
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
    );
  }
}

class _ListingsSection extends StatelessWidget {
  const _ListingsSection({
    required this.products,
    required this.onManage,
    required this.onAdd,
  });

  final List<Product> products;
  final VoidCallback onManage;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return HomeSection(
      title: 'Your listings',
      action: products.isEmpty ? null : 'Manage',
      onAction: products.isEmpty ? null : onManage,
      child: products.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
              child: _EmptyPanel(
                icon: Icons.inventory_2_outlined,
                title: 'No products yet',
                message: 'Add your first product so buyers have something to '
                    'find.',
                action: PrimaryGradientButton(
                  label: 'Add a product',
                  icon: Icons.add,
                  onTap: onAdd,
                ),
              ),
            )
          : SizedBox(
              height: 168,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
                itemCount: products.length,
                separatorBuilder: (context, i) =>
                    const SizedBox(width: AppSpace.md),
                itemBuilder: (context, i) => _ListingChip(
                  product: products[i],
                  onTap: () => context.pushNamed(
                    'product_details',
                    pathParameters: {'id': products[i].id},
                    extra: products[i],
                  ),
                ),
              ),
            ),
    );
  }
}

class _ListingChip extends StatelessWidget {
  const _ListingChip({required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: 116,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: AppRadius.cardAll,
              child: SizedBox(
                width: 116,
                height: 106,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    product.firstImage.isEmpty
                        ? DecoratedBox(
                            decoration: BoxDecoration(
                              color: context.palette.cardMuted,
                            ),
                            child: Icon(
                              Icons.image_outlined,
                              color: context.palette.textMuted,
                            ),
                          )
                        : CachedImage(product.firstImage, fit: BoxFit.cover),
                    if (!product.isAvailable)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                        ),
                        child: Center(
                          child: Text(
                            product.isSold ? 'SOLD' : 'HIDDEN',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              product.formatPrice(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              product.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall.copyWith(
                color: context.palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.xl),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: AppRadius.lgAll,
        boxShadow: AppShadows.card(context),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: AppColors.primaryBlue.withValues(alpha: 0.5)),
          const SizedBox(height: AppSpace.sm),
          Text(
            title,
            style: AppTextStyles.titleSmall.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: context.palette.textMuted,
              height: 1.5,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: AppSpace.lg),
            action!,
          ],
        ],
      ),
    );
  }
}

enum _BannerTone { info, danger, success }

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.tone,
    required this.icon,
    required this.title,
    required this.message,
  });

  final _BannerTone tone;
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      _BannerTone.info => AppColors.primaryBlue,
      _BannerTone.danger => AppColors.red,
      _BannerTone.success => AppColors.successGreen,
    };
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: AppSpace.md + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  message,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: context.palette.text,
                    height: 1.5,
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

class _StoreSummaryCard extends StatelessWidget {
  const _StoreSummaryCard({required this.seller, this.showStatusChip = false});

  final Seller seller;
  final bool showStatusChip;

  @override
  Widget build(BuildContext context) {
    final photo = seller.profilePhotoUrl;
    final hasPhoto = photo != null && photo.isNotEmpty;
    final cityLine = [
      seller.city,
      seller.province,
    ].where((s) => s != null && s.isNotEmpty).join(', ');
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: AppRadius.lgAll,
        boxShadow: AppShadows.card(context),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: hasPhoto ? null : AppColors.primaryGradient,
              color: hasPhoto ? AppColors.lightGrey : null,
              shape: BoxShape.circle,
              image: hasPhoto
                  ? DecorationImage(
                      image: NetworkImage(photo),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: hasPhoto
                ? null
                : const Icon(
                    Icons.storefront,
                    color: AppColors.white,
                    size: 28,
                  ),
          ),
          const SizedBox(width: AppSpace.md + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        seller.businessName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (seller.verified || seller.sdaVerified) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.verified,
                        color: AppColors.goldAccent,
                        size: 16,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  SellerCategory.labelFor(seller.category),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (cityLine.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    cityLine,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: context.palette.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (showStatusChip) _StatusChip(status: seller.status),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'approved' => AppColors.successGreen,
      'pending' => AppColors.primaryBlue,
      'rejected' => AppColors.red,
      _ => AppColors.primaryBlue,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.sm + 2,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        status.toUpperCase(),
        style: AppTextStyles.labelSmall.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard({
    required this.onAdd,
    required this.onManage,
    required this.onEdit,
    required this.onStorefront,
  });

  final VoidCallback onAdd;
  final VoidCallback onManage;
  final VoidCallback onEdit;
  final VoidCallback onStorefront;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: AppRadius.lgAll,
        boxShadow: AppShadows.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ActionRow(
            icon: Icons.add_box_outlined,
            title: 'Add a new product',
            subtitle: 'Photos, price and a description.',
            onTap: onAdd,
          ),
          const _Divider(),
          _ActionRow(
            icon: Icons.inventory_2_outlined,
            title: 'Manage products',
            subtitle: 'Toggle visibility, edit, or delete.',
            onTap: onManage,
          ),
          const _Divider(),
          _ActionRow(
            icon: Icons.visibility_outlined,
            title: 'View my storefront',
            subtitle: 'See the page buyers see.',
            onTap: onStorefront,
          ),
          const _Divider(),
          _ActionRow(
            icon: Icons.edit_outlined,
            title: 'Edit store profile',
            subtitle: 'Update contact, delivery, Sabbath hours.',
            onTap: onEdit,
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primaryBlue, size: 20),
            ),
            const SizedBox(width: AppSpace.md + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.titleSmall.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: context.palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: context.palette.textMuted),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, color: context.palette.divider);
}

class _SabbathBadge extends StatelessWidget {
  const _SabbathBadge({required this.notice});

  final String notice;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.goldAccent.withValues(alpha: 0.08),
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.goldAccent.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.brightness_3, color: AppColors.goldAccent, size: 20),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Text(
              notice,
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

class _ChecklistCard extends StatelessWidget {
  const _ChecklistCard({required this.items});
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: AppRadius.lgAll,
        boxShadow: AppShadows.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHILE YOU WAIT',
            style: AppTextStyles.labelSmall.copyWith(
              color: context.palette.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            'Reviewers check for:',
            style: AppTextStyles.titleSmall.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: AppColors.primaryBlue,
                    size: 18,
                  ),
                  const SizedBox(width: AppSpace.md - 2),
                  Expanded(
                    child: Text(
                      item,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: context.palette.text,
                      ),
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

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: AppRadius.lgAll,
        boxShadow: AppShadows.card(context),
      ),
      child: Column(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 48,
            color: context.palette.textMuted,
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: context.palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Destructive footer. Sits below everything else so a seller has to
/// scroll past their whole store before they reach Delete.
class _DangerZoneCard extends StatelessWidget {
  const _DangerZoneCard({required this.onDelete});

  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.red.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DANGER ZONE',
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.red,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Delete this store and every product you\'ve listed. This cannot '
            'be undone.',
            style: AppTextStyles.bodySmall.copyWith(
              color: context.palette.textMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          OutlinedButton.icon(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text('Delete store', style: AppTextStyles.labelLarge),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.red,
              side: const BorderSide(color: AppColors.red),
              padding: const EdgeInsets.symmetric(vertical: AppSpace.md + 2),
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.buttonAll,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
