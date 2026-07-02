import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/product_model.dart';
import '../../services/marketplace_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/product_card.dart';
import '../../widgets/screen_shell.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/content_reveal.dart';
import '../../widgets/motion/staggered_reveal.dart';
import '../../widgets/shimmer_loaders.dart';
import '../../widgets/motion/pressable.dart';

/// Browse the marketplace by category. Two modes:
///   1. No `categoryId` → renders the category grid (one tile per
///      ProductCategory). Tap a tile to drill in.
///   2. `categoryId` set → shows the products in that category.
class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key, this.categoryId});

  final String? categoryId;

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  List<Product> _products = const [];
  bool _loading = false;
  String? _error;

  ProductCategory? get _category => widget.categoryId == null
      ? null
      : ProductCategory.all.firstWhere(
          (c) => c.id == widget.categoryId,
          orElse: () => ProductCategory.all.first,
        );

  @override
  void initState() {
    super.initState();
    if (widget.categoryId != null) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await MarketplaceService.fetchProducts(
        category: widget.categoryId,
      );
      if (!mounted) return;
      setState(() {
        _products = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load this category. Pull to retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cat = _category;
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: BrandedRefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: () async {
          if (widget.categoryId != null) await _load();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              ScreenHero(
                title: cat?.label ?? 'Browse categories',
                tagline: cat == null ? 'Marketplace' : 'Marketplace · category',
                subtitle: cat == null
                    ? 'Pick a category to see everything in it.'
                    : null,
                fallbackRoute: 'marketplace',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: widget.categoryId == null
                    ? _buildGrid()
                    : _buildResults(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGrid() {
    // Drop the special "all" category from the picker — it'd just take
    // users back to the marketplace they came from.
    final cats = ProductCategory.all.where((c) => c.id != 'all').toList();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cats.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 1.05,
      ),
      itemBuilder: (context, i) {
        final cat = cats[i];
        return _CategoryTile(
          category: cat,
          onTap: () =>
              context.pushNamed('category', pathParameters: {'id': cat.id}),
        );
      },
    );
  }

  Widget _buildResults() {
    return ContentReveal(
      loading: _loading && _products.isEmpty,
      skeleton: SizedBox(height: 480, child: ShimmerLoaders.productGrid()),
      child: _buildResultsContent(),
    );
  }

  Widget _buildResultsContent() {
    if (_error != null) return ErrorBanner(message: _error!);
    if (_products.isEmpty) {
      return EmptyStateCard(
        icon: Icons.shopping_bag_outlined,
        title: 'No products in ${_category?.label ?? 'this category'} yet',
        message: 'Check back soon — sellers add new listings every day.',
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _products.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.72,
      ),
      itemBuilder: (context, i) {
        final p = _products[i];
        final card = ProductCard(
          product: p,
          heroTag: 'product_image_${p.id}',
          onTap: () => context.pushNamed(
            'product_details',
            pathParameters: {'id': p.id},
            extra: p,
          ),
        );
        if (i >= 6) return card;
        return StaggeredReveal(index: i, rise: 20, child: card);
      },
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onTap});

  final ProductCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressEffect(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            decoration: BoxDecoration(
              color: context.palette.card,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      category.icon,
                      style: const TextStyle(fontSize: 32),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    category.label,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.titleSmall.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
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
