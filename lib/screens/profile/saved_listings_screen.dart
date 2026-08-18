import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/product_model.dart';
import '../../services/marketplace_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/marketplace/product_tile.dart';
import '../../widgets/screen_shell.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/brand_spinner.dart';

/// Grid of products the user saved via the heart icon on a listing.
class SavedListingsScreen extends StatefulWidget {
  const SavedListingsScreen({super.key});

  @override
  State<SavedListingsScreen> createState() => _SavedListingsScreenState();
}

class _SavedListingsScreenState extends State<SavedListingsScreen> {
  List<Product> _products = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await MarketplaceService.fetchSavedProducts();
      if (!mounted) return;
      setState(() {
        _products = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load saved listings. Pull to retry.';
      });
    }
  }

  Future<void> _unsave(Product p) async {
    try {
      await MarketplaceService.unsaveProduct(p.id);
      if (!mounted) return;
      setState(() => _products = _products.where((x) => x.id != p.id).toList());
    } catch (_) {
      if (!mounted) return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BrandedRefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              const ScreenHero(
                title: 'Saved listings',
                tagline: 'Bookmarks',
                subtitle: 'Products you saved from the marketplace.',
                fallbackRoute: 'profile',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: _buildBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 64),
        child: Center(child: BrandSpinner(size: 30)),
      );
    }
    if (_error != null) {
      return ErrorBanner(message: _error!);
    }
    if (_products.isEmpty) {
      return EmptyStateCard(
        icon: Icons.favorite_outline,
        title: 'No saved listings',
        message: 'Tap the heart icon on any product to save it here for later.',
        action: PrimaryGradientButton(
          label: 'Browse marketplace',
          icon: Icons.shopping_bag_outlined,
          onTap: () => context.goNamed('marketplace'),
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _products.length,
      gridDelegate: ProductTile.gridDelegate,
      itemBuilder: (context, i) {
        final p = _products[i];
        // Everything here is saved by definition, so the tile's own heart
        // is always filled and always means "unsave". This replaces a
        // bespoke overlay button that did the same job.
        return ProductTile(
          product: p,
          saved: true,
          onToggleSave: () => _unsave(p),
          onTap: () => context.pushNamed(
            'product_details',
            pathParameters: {'id': p.id},
            extra: p,
          ),
        );
      },
    );
  }
}
