import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/product_model.dart';
import '../../services/seller_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';

/// Owner view of a seller's full product list. Lets them toggle each
/// listing between live/hidden, jump into product details, and delete
/// stale ones. Add-product CTA lives at the top.
class ManageProductsScreen extends StatefulWidget {
  const ManageProductsScreen({super.key});

  @override
  State<ManageProductsScreen> createState() => _ManageProductsScreenState();
}

enum _Filter { all, live, hidden }

class _ManageProductsScreenState extends State<ManageProductsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  List<Product> _products = const [];
  bool _loading = true;
  String? _error;
  _Filter _filter = _Filter.all;
  final Set<String> _busyIds = <String>{};

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slide = Tween<double>(begin: 12, end: 0).animate(
      CurvedAnimation(parent: _entrance, curve: Curves.easeOut),
    );
    _load();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final products = await SellerService.fetchMyProducts();
      if (!mounted) return;
      setState(() {
        _products = products;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your products. Pull to retry.';
      });
    }
  }

  List<Product> get _filtered {
    switch (_filter) {
      case _Filter.live:
        return _products.where((p) => p.isAvailable).toList();
      case _Filter.hidden:
        return _products.where((p) => !p.isAvailable).toList();
      case _Filter.all:
        return _products;
    }
  }

  Future<void> _toggle(Product product) async {
    if (_busyIds.contains(product.id)) return;
    setState(() => _busyIds.add(product.id));
    try {
      await SellerService.setProductAvailability(
        productId: product.id,
        available: !product.isAvailable,
      );
      if (!mounted) return;
      // Refresh from the server so the model state stays in sync with
      // whatever the DB actually stored (both `status` + `is_available`).
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not update visibility. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyIds.remove(product.id));
    }
  }

  Future<void> _confirmDelete(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: Text(
          'Delete this product?',
          style: AppTextStyles.headlineSmall,
        ),
        content: Text(
          '"${product.title}" will be removed from the marketplace permanently.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: const Color.fromRGBO(26, 26, 46, 0.75),
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: AppTextStyles.labelMedium.copyWith(
                color: AppColors.textDark,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: Text('Delete', style: AppTextStyles.labelLarge),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busyIds.add(product.id));
    try {
      await SellerService.deleteProduct(product.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.successGreen,
          content: Text(
            'Product deleted.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not delete. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyIds.remove(product.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGrey,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.pushNamed('add_product');
          if (mounted) _load();
        },
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: AppColors.white,
        elevation: 6,
        icon: const Icon(Icons.add),
        label: Text(
          'Add product',
          style: AppTextStyles.buttonText.copyWith(fontSize: 14),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildHero(),
              AnimatedBuilder(
                animation: _entrance,
                builder: (context, child) => Opacity(
                  opacity: _fade.value,
                  child: Transform.translate(
                    offset: Offset(0, _slide.value),
                    child: child,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  child: _buildBody(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _products.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primaryBlue),
        ),
      );
    }
    if (_error != null && _products.isEmpty) {
      return _ErrorCard(message: _error!);
    }
    if (_products.isEmpty) {
      return _buildEmptyAll();
    }
    final list = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FilterChips(
          filter: _filter,
          counts: _counts(),
          onChanged: (f) => setState(() => _filter = f),
        ),
        const SizedBox(height: 16),
        if (list.isEmpty)
          _buildEmptyFiltered()
        else
          ...list.map((p) => _ProductRow(
                product: p,
                busy: _busyIds.contains(p.id),
                onToggle: () => _toggle(p),
                onDelete: () => _confirmDelete(p),
                onOpen: () => context.pushNamed(
                  'product_details',
                  pathParameters: {'id': p.id},
                  extra: p,
                ),
              )),
      ],
    );
  }

  Map<_Filter, int> _counts() {
    var live = 0;
    var hidden = 0;
    for (final p in _products) {
      if (p.isAvailable) {
        live += 1;
      } else {
        hidden += 1;
      }
    }
    return {
      _Filter.all: _products.length,
      _Filter.live: live,
      _Filter.hidden: hidden,
    };
  }

  Widget _buildEmptyAll() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              color: AppColors.primaryBlue,
              size: 42,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'No products yet',
            style: AppTextStyles.headlineMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'List your first product to start selling on the marketplace.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.6),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyFiltered() {
    final label = switch (_filter) {
      _Filter.live => 'live',
      _Filter.hidden => 'hidden',
      _Filter.all => 'matching',
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(
            Icons.filter_alt_off_outlined,
            size: 36,
            color: AppColors.primaryBlue.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 8),
          Text(
            'No $label products',
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero() {
    return ClipPath(
      clipper: _HeroClipper(),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _CircleIconButton(
                      icon: Icons.arrow_back_ios_new,
                      onTap: () => context.canPop()
                          ? context.pop()
                          : context.goNamed('seller_dashboard'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MY PRODUCTS',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.white.withValues(alpha: 0.55),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Manage listings',
                        style: AppTextStyles.displayMedium.copyWith(
                          color: AppColors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Toggle live/hidden, edit details, remove stale items.',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.filter,
    required this.counts,
    required this.onChanged,
  });

  final _Filter filter;
  final Map<_Filter, int> counts;
  final ValueChanged<_Filter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Chip(
          label: 'All',
          count: counts[_Filter.all] ?? 0,
          active: filter == _Filter.all,
          onTap: () => onChanged(_Filter.all),
        ),
        const SizedBox(width: 8),
        _Chip(
          label: 'Live',
          count: counts[_Filter.live] ?? 0,
          active: filter == _Filter.live,
          onTap: () => onChanged(_Filter.live),
        ),
        const SizedBox(width: 8),
        _Chip(
          label: 'Hidden',
          count: counts[_Filter.hidden] ?? 0,
          active: filter == _Filter.hidden,
          onTap: () => onChanged(_Filter.hidden),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: active ? AppColors.primaryGradient : null,
            color: active ? null : AppColors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active
                  ? AppColors.primaryBlue
                  : const Color.fromRGBO(26, 26, 46, 0.08),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTextStyles.labelMedium.copyWith(
                  color: active ? AppColors.white : AppColors.textDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.white.withValues(alpha: 0.25)
                      : AppColors.primaryBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$count',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: active ? AppColors.white : AppColors.primaryBlue,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    required this.busy,
    required this.onToggle,
    required this.onDelete,
    required this.onOpen,
  });

  final Product product;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final firstImage = product.firstImage;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: Container(
                        width: 76,
                        color: AppColors.lightGrey,
                        child: firstImage.isNotEmpty
                            ? CachedImage(
                                firstImage,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Icon(
                                  Icons.image_not_supported_outlined,
                                  color: Color.fromRGBO(26, 26, 46, 0.4),
                                ),
                              )
                            : const Icon(
                                Icons.image_outlined,
                                color: Color.fromRGBO(26, 26, 46, 0.4),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.titleSmall.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          product.formatPrice(),
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.primaryBlue,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _AvailabilityChip(available: product.isAvailable),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _RowMenu(
                    product: product,
                    busy: busy,
                    onToggle: onToggle,
                    onDelete: onDelete,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RowMenu extends StatelessWidget {
  const _RowMenu({
    required this.product,
    required this.busy,
    required this.onToggle,
    required this.onDelete,
  });

  final Product product;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const SizedBox(
        width: 36,
        height: 36,
        child: Padding(
          padding: EdgeInsets.all(10),
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: AppColors.primaryBlue,
          ),
        ),
      );
    }
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(
        Icons.more_vert,
        color: Color.fromRGBO(26, 26, 46, 0.55),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      onSelected: (value) {
        switch (value) {
          case 'toggle':
            onToggle();
            break;
          case 'delete':
            onDelete();
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'toggle',
          child: Row(
            children: [
              Icon(
                product.isAvailable
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: AppColors.primaryBlue,
                size: 18,
              ),
              const SizedBox(width: 10),
              Text(
                product.isAvailable ? 'Hide from marketplace' : 'Make live',
                style: AppTextStyles.bodyMedium,
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              const Icon(
                Icons.delete_outline,
                color: AppColors.red,
                size: 18,
              ),
              const SizedBox(width: 10),
              Text(
                'Delete',
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.red),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AvailabilityChip extends StatelessWidget {
  const _AvailabilityChip({required this.available});
  final bool available;

  @override
  Widget build(BuildContext context) {
    final color = available ? AppColors.successGreen : AppColors.textDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: available ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        available ? 'LIVE' : 'HIDDEN',
        style: AppTextStyles.labelSmall.copyWith(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 48,
            color: Color.fromRGBO(26, 26, 46, 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 28);
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width,
      size.height - 28,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.white.withValues(alpha: 0.10)),
          ),
          child: Icon(icon, color: AppColors.white, size: 18),
        ),
      ),
    );
  }
}
