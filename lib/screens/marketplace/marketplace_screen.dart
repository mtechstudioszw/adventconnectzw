import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/product_model.dart';
import '../../models/seller_model.dart';
import '../../services/cache_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/marketplace_service.dart';
import '../../services/seller_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/ads/ad_banner.dart';
import '../../widgets/home/section_header.dart';
import '../../widgets/last_updated_strip.dart';
import '../../widgets/marketplace/cart_badge_button.dart';
import '../../widgets/marketplace/product_tile.dart';
import '../../widgets/marketplace/shop_card.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/content_reveal.dart';
import '../../widgets/motion/hide_on_scroll.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/motion/staggered_reveal.dart';
import '../../widgets/offline_inline_notice.dart';
import '../../widgets/screen_shell.dart';
import '../../widgets/shimmer_loaders.dart';
import '../widgets/main_bottom_nav.dart';
import '../widgets/post_form_widgets.dart';

/// The marketplace tab.
///
/// Structure is storefront-first: shops sit above the product grid so the
/// tab reads as a street of shops rather than a bag of goods, which is
/// also the only arrangement that looks composed while the catalogue is
/// small.
///
/// Products render as [ProductTile] — photo-led, no card chrome. The old
/// layout wrapped the whole screen in a fixed-height `SizedBox` inside a
/// non-scrolling `SingleChildScrollView`, which put the bottom ~112dp of
/// the grid permanently past the edge of an unscrollable viewport. Now the
/// whole screen is one sliver list, so the grid owns the scroll.
class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen>
    with NavVisibilityMixin {
  final _searchController = TextEditingController();
  Timer? _debounce;

  /// Everything fetched for the current category. Search filters this
  /// list on-device rather than round-tripping — the old debounce fired
  /// two queries per keystroke *and* the server shuffled the result, so
  /// the grid reordered under the user's finger while they typed.
  List<Product> _products = [];
  List<Seller> _shops = const [];
  Set<String> _savedIds = <String>{};
  String _selectedCategory = 'all';
  String _query = '';
  bool _loading = true;
  String? _error;
  Seller? _mySeller;

  static const _cacheKey = 'products_list';

  @override
  void initState() {
    super.initState();
    _hydrateFromCache();
    _loadProducts();
    _loadShops();
    _loadMySeller();
    _loadSaved();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _hydrateFromCache() {
    try {
      final raw = CacheService.readString(_cacheKey);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List)
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!mounted || list.isEmpty) return;
      setState(() {
        _products = list;
        _loading = false;
      });
    } catch (_) {}
  }

  Future<void> _writeCache(List<Product> list) async {
    try {
      await CacheService.writeString(
        _cacheKey,
        jsonEncode(list.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> _loadMySeller() async {
    try {
      final seller = await SellerService.fetchMySellerProfile();
      if (mounted) setState(() => _mySeller = seller);
    } catch (_) {
      // Banner is decorative — failures must never block the marketplace.
    }
  }

  Future<void> _loadShops() async {
    try {
      final shops = await SellerService.fetchApprovedSellers();
      if (mounted) setState(() => _shops = shops);
    } catch (_) {
      // Rail self-hides when empty.
    }
  }

  Future<void> _loadSaved() async {
    try {
      final ids = await MarketplaceService.fetchSavedProductIds();
      if (mounted) setState(() => _savedIds = ids);
    } catch (_) {
      // Signed out, or offline — the heart just stays hidden.
    }
  }

  Future<void> _loadProducts() async {
    setState(() {
      if (_products.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final list = await MarketplaceService.fetchProducts(
        category: _selectedCategory,
      );
      if (!mounted) return;
      setState(() {
        _products = list;
        _loading = false;
      });
      if (_selectedCategory == 'all') unawaited(_writeCache(list));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load products. Pull to retry.';
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    await Future.wait([_loadProducts(), _loadShops(), _loadSaved()]);
  }

  /// Local filter. Debounced only to avoid rebuilding the grid on every
  /// frame of fast typing — no network involved.
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _query = value.trim().toLowerCase());
    });
  }

  void _selectCategory(String id) {
    if (_selectedCategory == id) return;
    setState(() => _selectedCategory = id);
    _loadProducts();
  }

  List<Product> get _visibleProducts {
    if (_query.isEmpty) return _products;
    return _products.where((p) {
      return p.title.toLowerCase().contains(_query) ||
          (p.description?.toLowerCase().contains(_query) ?? false) ||
          p.sellerName.toLowerCase().contains(_query);
    }).toList();
  }

  Future<void> _toggleSave(Product product) async {
    final wasSaved = _savedIds.contains(product.id);
    // Optimistic — the heart must answer the tap instantly.
    setState(() {
      if (wasSaved) {
        _savedIds = {..._savedIds}..remove(product.id);
      } else {
        _savedIds = {..._savedIds, product.id};
      }
    });
    try {
      if (wasSaved) {
        await MarketplaceService.unsaveProduct(product.id);
      } else {
        await MarketplaceService.saveProduct(product.id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (wasSaved) {
          _savedIds = {..._savedIds, product.id};
        } else {
          _savedIds = {..._savedIds}..remove(product.id);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sign in to save listings.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      bottomNavigationBar: HideOnScroll(
        visible: navVisible,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CartFloatingBar(onTap: () => context.pushNamed('cart')),
            const AdBanner(),
            const MainBottomNav(currentIndex: 3),
          ],
        ),
      ),
      floatingActionButton: const PostFab(
        routeName: 'add_product',
        tooltip: 'List a product',
      ),
      body: NotificationListener<UserScrollNotification>(
        onNotification: handleNavScroll,
        child: BrandedRefreshIndicator(
          color: AppColors.primaryBlue,
          onRefresh: _refresh,
          child: ContentReveal(
            loading: _loading && _products.isEmpty,
            skeleton: ShimmerLoaders.productGrid(),
            child: _buildScroll(),
          ),
        ),
      ),
    );
  }

  Widget _buildScroll() {
    final products = _visibleProducts;
    final cachedAt = CacheService.cachedAt(_cacheKey);
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _buildHeader()),
        SliverToBoxAdapter(child: _buildSearchBar()),
        if (_mySeller != null)
          SliverToBoxAdapter(child: _SellerStatusBanner(seller: _mySeller!)),
        SliverToBoxAdapter(child: const _ShopJobsSegment(active: _Section.shop)),

        // Shops rail — hidden while searching, since a text query is about
        // finding a product, not browsing shops.
        if (_shops.isNotEmpty && _query.isEmpty)
          SliverToBoxAdapter(child: _buildShopsRail()),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpace.xl),
            child: SectionHeader(
              title: _query.isEmpty ? 'Browse everything' : 'Results',
              action: 'Categories',
              onAction: () => context.pushNamed('categories'),
            ),
          ),
        ),
        SliverToBoxAdapter(child: _buildCategoryStrip()),

        if (cachedAt != null && _query.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
              child: LastUpdatedStrip(
                timestamp: cachedAt,
                isOnline: ConnectivityService.isOnline,
                onRefresh: _refresh,
              ),
            ),
          ),

        if (_error != null && _products.isEmpty)
          SliverToBoxAdapter(child: _buildErrorState())
        else if (products.isEmpty)
          SliverToBoxAdapter(child: _buildEmptyState())
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.md,
              AppSpace.lg,
              AppSpace.xxl,
            ),
            sliver: SliverGrid(
              // 3:4 photo plus the text block beneath it. Kept as a fixed
              // ratio while the catalogue is small — ragged masonry with a
              // handful of items reads as a bug, not as editorial.
              gridDelegate: ProductTile.gridDelegate,
              delegate: SliverChildBuilderDelegate((context, i) {
                final p = products[i];
                final tile = ProductTile(
                  product: p,
                  heroTag: 'product_image_${p.id}',
                  saved: _savedIds.contains(p.id),
                  onToggleSave: () => _toggleSave(p),
                  onTap: () => context.pushNamed(
                    'product_details',
                    pathParameters: {'id': p.id},
                    extra: p,
                  ),
                );
                // Only the first rows cascade; past that the reveal is
                // just latency the user has to sit through.
                if (i >= 6) return tile;
                return StaggeredReveal(index: i, rise: 20, child: tile);
              }, childCount: products.length),
            ),
          ),

        // Clears the floating basket bar + ad + nav so the last row is
        // reachable. This is the padding the old fixed-height layout
        // never had.
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }

  Widget _buildHeader() {
    return ScreenHero(
      title: 'Shop within the community',
      tagline: 'Marketplace',
      fallbackRoute: 'home',
      trailing: CartBadgeButton(onTap: () => context.pushNamed('cart')),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.md,
        AppSpace.lg,
        AppSpace.sm,
      ),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        style: AppTextStyles.bodyLarge,
        decoration: InputDecoration(
          hintText: 'Search products and shops',
          prefixIcon: const Icon(Icons.search, color: AppColors.primaryBlue),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close, color: context.palette.textMuted),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
          filled: true,
          fillColor: context.palette.inputFill,
          contentPadding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
        ),
      ),
    );
  }

  Widget _buildShopsRail() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpace.xl),
        SectionHeader(
          title: 'Shops on Advent Connect',
          action: _shops.length > 3 ? 'See all' : null,
          onAction: () => context.pushNamed('categories'),
        ),
        const SizedBox(height: AppSpace.md),
        SizedBox(
          height: 208,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
            itemCount: _shops.length,
            separatorBuilder: (context, i) => const SizedBox(width: AppSpace.md),
            itemBuilder: (context, i) {
              final shop = _shops[i];
              return StaggeredReveal(
                index: i,
                rise: 16,
                child: ShopCard(
                  seller: shop,
                  onTap: () => context.pushNamed(
                    'seller_profile',
                    pathParameters: {'userId': shop.authUserId},
                    extra: shop,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryStrip() {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
        itemCount: ProductCategory.all.length,
        separatorBuilder: (context, index) => const SizedBox(width: AppSpace.sm),
        itemBuilder: (context, i) {
          final cat = ProductCategory.all[i];
          return _CategoryChip(
            label: cat.label,
            icon: cat.icon,
            selected: _selectedCategory == cat.id,
            onTap: () => _selectCategory(cat.id),
          );
        },
      ),
    );
  }

  Widget _buildErrorState() {
    final isOffline = !ConnectivityService.isOnline;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.xl,
        AppSpace.lg,
        AppSpace.xxl,
      ),
      child: Column(
        children: [
          if (isOffline) OfflineInlineNotice(onRetry: _loadProducts),
          if (isOffline) const SizedBox(height: AppSpace.xl),
          if (!isOffline) ...[
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: context.palette.textMuted,
            ),
            const SizedBox(height: AppSpace.md),
          ],
          Text(
            isOffline ? 'No products cached yet.' : _error!,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: context.palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final searching = _query.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xxl,
        AppSpace.xxl,
        AppSpace.xxl,
        AppSpace.xxl,
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
            child: Icon(
              searching ? Icons.search_off_rounded : Icons.shopping_bag_outlined,
              color: AppColors.primaryBlue,
              size: 40,
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          Text(
            searching ? 'Nothing matches "$_query"' : 'No products yet',
            textAlign: TextAlign.center,
            style: AppTextStyles.headlineMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            searching
                ? 'Try a different word, or browse a category.'
                : 'Know an SDA business owner? Tell them about us.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: context.palette.textMuted,
              height: 1.5,
            ),
          ),
          if (!searching) ...[
            const SizedBox(height: AppSpace.xl),
            _BecomeSellerButton(onTap: () => _onBecomeSellerTapped(context)),
          ],
        ],
      ),
    );
  }
}

class _BecomeSellerButton extends StatelessWidget {
  const _BecomeSellerButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.xl,
          vertical: AppSpace.lg,
        ),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: AppRadius.buttonAll,
          boxShadow: AppShadows.glow(context),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.storefront, color: AppColors.white, size: 18),
            const SizedBox(width: AppSpace.sm),
            Text(
              'Become a seller',
              style: AppTextStyles.buttonText.copyWith(letterSpacing: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}

/// Entry point for the "Become a seller" button. patch_031 removed
/// the business-account indirection — sellers apply directly. We just
/// surface the chooser straight away; the seller dashboard handles
/// the pending / rejected / approved branching itself.
Future<void> _onBecomeSellerTapped(BuildContext context) async {
  await _showSellerChooser(context);
}

/// Bottom-sheet chooser fired when the user taps "Become a seller"
/// and qualifies for the seller flow. Asks whether they already have
/// a store or want to set up a fresh one.
Future<void> _showSellerChooser(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: sheetContext.palette.sheet,
          borderRadius: AppRadius.sheetTop,
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Selling on Advent Connect',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              'Already running a store, or starting a new one?',
              style: AppTextStyles.bodySmall.copyWith(
                color: context.palette.textMuted,
              ),
            ),
            const SizedBox(height: 18),
            _SellerChoiceTile(
              icon: Icons.storefront_outlined,
              title: 'I already have a store',
              subtitle: 'Open my seller dashboard.',
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.pushNamed('seller_dashboard');
              },
            ),
            const SizedBox(height: AppSpace.md),
            _SellerChoiceTile(
              icon: Icons.add_business_outlined,
              title: 'Set up a new store',
              subtitle:
                  'Open a store and start selling within the SDA community.',
              onTap: () {
                Navigator.of(sheetContext).pop();
                // Gate on the Marketplace Code of Conduct first.
                context.pushNamed('marketplace_guidelines');
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _SellerChoiceTile extends StatelessWidget {
  const _SellerChoiceTile({
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
      child: Container(
        padding: const EdgeInsets.all(AppSpace.lg - 2),
        decoration: BoxDecoration(
          color: context.palette.cardMuted,
          borderRadius: AppRadius.cardAll,
          border: Border.all(color: context.palette.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: AppRadius.buttonAll,
              ),
              child: Icon(icon, color: AppColors.white, size: 22),
            ),
            const SizedBox(width: AppSpace.lg - 2),
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
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.primaryBlue),
          ],
        ),
      ),
    );
  }
}

/// Status pill rendered at the top of the marketplace tab when the
/// current user has a `sellers` row.
class _SellerStatusBanner extends StatelessWidget {
  const _SellerStatusBanner({required this.seller});

  final Seller seller;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color tint, String label, String hint) =
        seller.isApproved
        ? (
            Icons.storefront_rounded,
            AppColors.successGreen,
            'Seller mode',
            'Tap to open your seller dashboard.',
          )
        : seller.isPending
        ? (
            Icons.hourglass_top_rounded,
            AppColors.goldAccent,
            'Store under review',
            'Tap to check approval status.',
          )
        : (
            Icons.error_outline_rounded,
            AppColors.red,
            'Application needs attention',
            'Tap to review and resubmit.',
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        0,
        AppSpace.lg,
        AppSpace.sm,
      ),
      child: Pressable(
        onTap: () => context.pushNamed('seller_dashboard'),
        child: Container(
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.10),
            borderRadius: AppRadius.buttonAll,
            border: Border.all(color: tint.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: tint, size: 18),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: AppTextStyles.titleSmall.copyWith(
                        color: tint,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: context.palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: tint.withValues(alpha: 0.7),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Section { shop, jobs }

class _ShopJobsSegment extends StatelessWidget {
  const _ShopJobsSegment({required this.active});
  final _Section active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.lg,
        vertical: AppSpace.xs,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpace.xs),
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: AppRadius.buttonAll,
          border: Border.all(color: context.palette.divider),
        ),
        child: Row(
          children: [
            _SegmentButton(
              label: 'Shop',
              icon: Icons.shopping_bag_outlined,
              selected: active == _Section.shop,
              onTap: active == _Section.shop
                  ? null
                  : () => context.goNamed('marketplace'),
            ),
            const SizedBox(width: 6),
            _SegmentButton(
              label: 'Jobs',
              icon: Icons.work_outline,
              selected: active == _Section.jobs,
              onTap: active == _Section.jobs
                  ? null
                  : () => context.goNamed('jobs'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: selected ? AppColors.primaryGradient : null,
            borderRadius: AppRadius.buttonAll,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? AppColors.white : context.palette.textMuted,
              ),
              const SizedBox(width: AppSpace.sm),
              Text(
                label,
                style: AppTextStyles.labelMedium.copyWith(
                  color: selected ? AppColors.white : context.palette.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      pressedScale: 0.94,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg - 2,
          vertical: AppSpace.md - 2,
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? context.palette.text : context.palette.card,
          borderRadius: AppRadius.pillAll,
          border: Border.all(
            color: selected ? context.palette.text : context.palette.divider,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyles.labelMedium.copyWith(
                color: selected
                    ? context.palette.scaffoldBg
                    : context.palette.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
