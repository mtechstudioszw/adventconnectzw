import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/product_model.dart';
import '../../models/seller_model.dart';
import '../../config/countries.dart';
import '../../services/auth_service.dart';
import '../../widgets/country_scope_toggle.dart';
import '../../services/cache_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/marketplace_service.dart';
import '../../services/market_ranking.dart';
import '../../services/recently_viewed_service.dart';
import '../../widgets/marketplace/market_filter_sheet.dart';
import '../../services/seller_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/home/section_header.dart';
import '../../widgets/last_updated_strip.dart';
import '../../widgets/marketplace/cart_badge_button.dart';
import '../../widgets/marketplace/product_tile.dart';
import '../../widgets/marketplace/shop_card.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/content_reveal.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/motion/staggered_reveal.dart';
import '../../widgets/offline_inline_notice.dart';
import '../../widgets/offline_toast.dart';
import '../../widgets/shimmer_loaders.dart';
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

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  /// Everything fetched for the current category. Search filters this
  /// list on-device rather than round-tripping — the old debounce fired
  /// two queries per keystroke *and* the server shuffled the result, so
  /// the grid reordered under the user's finger while they typed.
  List<Product> _products = [];
  List<Seller> _shops = const [];

  /// The rail follows the same Zimbabwe / Worldwide scope as the grid. It
  /// didn't, so a member browsing Zimbabwe was shown a shop in Kumasi.
  /// A shop with no country set stays visible rather than vanishing.
  List<Seller> get _scopedShops => _worldwide
      ? _shops
      : _shops
            .where((s) => (s.country ?? '').isEmpty || s.country == _country)
            .toList();
  Set<String> _savedIds = <String>{};
  String _selectedCategory = 'all';

  /// The marketplace shows the member's own country unless they ask for
  /// worldwide. Handoff is WhatsApp plus local pickup, so a listing from
  /// another country is one nobody can act on.
  bool _worldwide = false;
  final String _country = AuthService.currentCountry();

  String _query = '';

  /// The text the SERVER last searched for. Typing filters what's loaded at
  /// once ([_query]); a moment later the whole catalogue is searched.
  String _serverQuery = '';
  Timer? _serverDebounce;

  MarketFilters _filters = MarketFilters.none;

  /// Seller facts the ranking reads, from the last load.
  MarketCatalog _catalog = MarketCatalog.empty;

  /// Grid rows revealed so far; "Show more" adds a page.
  static const _page = 24;
  int _shown = _page;
  bool _loading = true;

  /// True until the first product request settles. Only that first load
  /// swaps the whole screen for the skeleton; later loads (a category or
  /// scope change) skeleton the grid alone, so the chips stay tappable.
  bool _firstLoad = true;
  String? _error;
  Seller? _mySeller;

  /// Bumped per product request; a response from an older one is dropped.
  /// Flicking Books → Clothing used to let the slower Books answer land
  /// last and fill the grid under the Clothing chip.
  int _loadGen = 0;

  /// The scope the offline cache holds (see [_loadProducts]).
  bool get _isDefaultScope =>
      _selectedCategory == 'all' &&
      !_worldwide &&
      _serverQuery.isEmpty &&
      _filters.isEmpty;

  /// Plain browsing: no search, no filters, every category. Only then do
  /// the discovery sections show — a search wants results, not shelves.
  bool get _browsing =>
      _query.isEmpty && _filters.isEmpty && _selectedCategory == 'all';

  static const _cacheKey = 'products_list';

  @override
  void initState() {
    super.initState();
    _hydrateFromCache();
    _loadProducts();
    _loadShops();
    _loadMySeller();
    _loadSaved();
    RecentlyViewedService.load();
    RecentlyViewedService.items.addListener(_onRecentChanged);
  }

  void _onRecentChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    RecentlyViewedService.items.removeListener(_onRecentChanged);
    _serverDebounce?.cancel();
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
      if (!mounted) return;
      // Your own shop doesn't belong in "Shops in the community" — this
      // rail is for discovering other people's. Yours is one tap away on
      // the seller dashboard, and seeing it here just made the rail
      // shorter for no gain.
      final me = AuthService.currentUser?.id;
      setState(() => _shops =
          shops.where((s) => me == null || s.authUserId != me).toList());
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

  /// [filterChanged]: the category or scope changed, so what is on screen
  /// is the wrong list. It is cleared — the old grid used to stay up under
  /// the new chip while loading, and if the load failed it stayed up for
  /// good with no error, because the error only showed over an empty grid.
  Future<void> _loadProducts({bool filterChanged = false}) async {
    final gen = ++_loadGen;
    setState(() {
      if (filterChanged) _products = [];
      if (_products.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final catalog = await MarketplaceService.fetchCatalog(
        search: _serverQuery,
        category: _selectedCategory,
        country: _worldwide ? null : _country,
        filters: _filters,
      );
      final list = catalog.products;
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _catalog = catalog;
        _shown = _page;
        _products = list;
        _loading = false;
        _firstLoad = false;
      });
      // Scope counts as a filter for caching: a cached worldwide grid would
      // greet the member with another country's listings on next launch.
      if (_isDefaultScope) {
        unawaited(_writeCache(list));
      }
    } catch (_) {
      if (!mounted || gen != _loadGen) return;
      final hadProducts = _products.isNotEmpty;
      // Back on the default scope with nothing showing (switched back to
      // "All" offline): the cached grid is the right list, so use it.
      if (!hadProducts && _isDefaultScope) _hydrateFromCache();
      setState(() {
        _error = 'Could not load products. Pull to retry.';
        _loading = false;
        _firstLoad = false;
      });
      // A failed refresh over a grid that is still showing said nothing;
      // the spinner just retracted.
      if (hadProducts && !maybeShowOffline(context)) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text("Couldn't refresh products.")),
        );
      }
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
    // Then ask the server, so the search covers the whole catalogue and
    // shop names, not just what happened to be loaded.
    _serverDebounce?.cancel();
    _serverDebounce = Timer(const Duration(milliseconds: 450), () {
      final q = value.trim();
      if (!mounted || q == _serverQuery) return;
      _serverQuery = q;
      _loadProducts();
    });
  }

  Future<void> _openFilters() async {
    final picked = await showMarketFilterSheet(
      context,
      current: _filters,
      shops: _scopedShops,
    );
    if (picked == null || !mounted) return;
    setState(() => _filters = picked);
    _loadProducts(filterChanged: true);
  }

  void _setSort(MarketSort sort) {
    if (sort == _filters.sort) return;
    setState(() {
      _filters = _filters.copyWith(sort: sort);
      _shown = _page;
    });
  }

  void _selectCategory(String id) {
    if (_selectedCategory == id) return;
    setState(() => _selectedCategory = id);
    _loadProducts(filterChanged: true);
  }

  /// Loaded listings, narrowed by what's typed, in ranked order (see
  /// MarketRanking — deterministic per day, never a shuffle).
  List<Product> get _visibleProducts {
    final list = _query.isEmpty
        ? _products
        : _products.where((p) {
            return p.title.toLowerCase().contains(_query) ||
                (p.description?.toLowerCase().contains(_query) ?? false) ||
                p.sellerName.toLowerCase().contains(_query);
          }).toList();
    return MarketRanking.rank(
      list,
      sort: _filters.sort,
      now: DateTime.now(),
      viewer: AuthService.currentUser?.id ?? '',
      newSellerIds: _catalog.newSellerIds,
      sellerRatings: _catalog.sellerRatings,
      interestCategories: RecentlyViewedService.interestCategories,
    );
  }

  /// Recently viewed, but only listings still for sale in this scope.
  List<Product> get _recentForSale {
    final live = {for (final p in _products) p.id: p};
    return [
      for (final r in RecentlyViewedService.items.value)
        if (live[r.id] != null) live[r.id]!,
    ];
  }

  /// New this fortnight — shown only when the catalogue is big enough that
  /// this isn't simply the whole grid again.
  List<Product> get _newArrivals {
    if (_products.length < 12) return const [];
    final cutoff = DateTime.now().subtract(const Duration(days: 14));
    final fresh = _products.where((p) => p.createdAt.isAfter(cutoff)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return fresh.length >= 3 ? fresh.take(10).toList() : const [];
  }

  /// Shops whose name matches the search.
  List<Seller> get _matchingShops {
    if (_query.isEmpty) return const [];
    return _scopedShops
        .where((s) => s.businessName.toLowerCase().contains(_query))
        .toList();
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
      backgroundColor: Colors.transparent,
      // The island and the banner above it are drawn by TabShell. (The
      // "N items · View basket" bar that used to sit there is gone — it
      // restated the header's basket badge and ate a row of products.)
      floatingActionButton: PostFab(
        routeName: 'add_product',
        tooltip: 'List a product',
        onCreated: _refresh,
      ),
      body: BrandedRefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: _refresh,
        child: ContentReveal(
          loading: _firstLoad && _products.isEmpty,
          skeleton: ShimmerLoaders.productGrid(),
          child: _buildScroll(),
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
        // Collapsing header: the title block scrolls away and the search row
        // pins, so products climb to the top of the screen instead of sitting
        // below a permanent block of chrome.
        SliverPersistentHeader(
          pinned: true,
          delegate: _MarketHeaderDelegate(
            topInset: MediaQuery.paddingOf(context).top,
            // The header's height has to know the text scale — see
            // _MarketHeaderDelegate._titleBody.
            textScale: MediaQuery.textScalerOf(context).scale(1),
            controller: _searchController,
            query: _query,
            onQueryChanged: _onSearchChanged,
            onClearQuery: () {
              _searchController.clear();
              _serverDebounce?.cancel();
              setState(() => _query = '');
              if (_serverQuery.isNotEmpty) {
                _serverQuery = '';
                _loadProducts();
              }
            },
            onCartTap: () => context.pushNamed('cart'),
          ),
        ),
        if (_mySeller != null)
          SliverToBoxAdapter(child: _SellerStatusBanner(seller: _mySeller!)),
        SliverToBoxAdapter(child: const _ShopJobsSegment(active: _Section.shop)),

        // Discovery shelves (brief §11) — only while browsing, and each
        // only when it has real, distinct content. Nothing is invented to
        // fill a shelf, and a shelf that would just repeat the grid stays
        // hidden.
        if (_browsing) ...[
          if (_featuredShops.isNotEmpty)
            SliverToBoxAdapter(
              child: _buildShopsRail(
                title: 'Featured stores',
                shops: _featuredShops,
                labelled: true,
              ),
            ),
          if (_communityShops.isNotEmpty)
            SliverToBoxAdapter(
              child: _buildShopsRail(
                title: 'Shops in the community',
                shops: _communityShops,
              ),
            ),
          if (_featuredProducts.isNotEmpty)
            SliverToBoxAdapter(
              child: _ProductShelf(
                title: 'Featured',
                subtitle: 'Featured by the marketplace team',
                products: _featuredProducts,
                savedIds: _savedIds,
                onToggleSave: _toggleSave,
              ),
            ),
          if (_recentForSale.length >= 2)
            SliverToBoxAdapter(
              child: _ProductShelf(
                title: 'Recently viewed',
                products: _recentForSale,
                savedIds: _savedIds,
                onToggleSave: _toggleSave,
              ),
            ),
          if (_newArrivals.isNotEmpty)
            SliverToBoxAdapter(
              child: _ProductShelf(
                title: 'New arrivals',
                products: _newArrivals,
                savedIds: _savedIds,
                onToggleSave: _toggleSave,
              ),
            ),
        ] else if (_matchingShops.isNotEmpty)
          SliverToBoxAdapter(
            child: _buildShopsRail(title: 'Shops', shops: _matchingShops),
          ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpace.xl),
            child: SectionHeader(
              title: !_browsing
                  ? 'Results'
                  : (RecentlyViewedService.interestCategories.isNotEmpty &&
                        _products.length >= 12)
                  ? 'Recommended for you'
                  : 'All listings',
              // The "Categories" link is gone. It opened a whole screen whose
              // only job was a grid of the same categories the chips below
              // already offer inline — a second way to do the same thing, one
              // navigation deeper.
            ),
          ),
        ),
        // Scope sits above the category chips and does NOT pin: it is a
        // set-once decision, unlike categories which get flicked between
        // while browsing. Pinning both would eat a third of a small screen.
        SliverToBoxAdapter(
          child: Padding(
            // Bottom gap so the scope switch and the category chips read as
            // two separate controls, not one cramped block (owner, 28 Oct).
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.md,
              AppSpace.lg,
              AppSpace.md,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: CountryScopeToggle(
                countryCode: _country,
                worldwide: _worldwide,
                onChanged: (v) {
                  setState(() => _worldwide = v);
                  _loadProducts(filterChanged: true);
                },
              ),
            ),
          ),
        ),
        // Chips pin under the header so filtering stays reachable no matter
        // how far down the grid you are.
        SliverPersistentHeader(
          pinned: true,
          delegate: _CategoryStripDelegate(child: _buildCategoryStrip()),
        ),
        SliverToBoxAdapter(
          child: _FilterRow(
            filters: _filters,
            resultCount: _loading ? null : products.length,
            onOpenFilters: _openFilters,
            onSort: _setSort,
            onClear: _filters.isEmpty
                ? null
                : () {
                    setState(() => _filters = MarketFilters(sort: _filters.sort));
                    _loadProducts(filterChanged: true);
                  },
          ),
        ),

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

        if (_loading && _products.isEmpty)
          ShimmerLoaders.productGridSliver()
        else if (_error != null && _products.isEmpty)
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
              }, childCount: math.min(_shown, products.length)),
            ),
          ),
        if (products.length > _shown)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                0,
                AppSpace.lg,
                AppSpace.lg,
              ),
              child: OutlinedButton(
                onPressed: () => setState(() => _shown += _page),
                child: Text(
                  'Show more (${products.length - _shown} left)',
                ),
              ),
            ),
          ),

        // Clears the floating basket bar + ad + nav so the last row is
        // reachable. This is the padding the old fixed-height layout
        // never had.
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }


  /// Stores the marketplace team featured (sellers.featured — admin-set;
  /// patch_276 stops sellers setting it themselves). Labelled, never mixed
  /// into the organic order.
  List<Seller> get _featuredShops =>
      _scopedShops.where((s) => s.featured).toList();

  List<Seller> get _communityShops =>
      _scopedShops.where((s) => !s.featured).toList();

  List<Product> get _featuredProducts =>
      _products.where((p) => p.isFeatured).take(10).toList();

  Widget _buildShopsRail({
    required String title,
    required List<Seller> shops,
    bool labelled = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpace.xl),
        // No "See all": it pushed the CATEGORY grid, which has nothing to do
        // with shops. The rail already carries every approved seller and
        // scrolls horizontally, so there is nothing hidden behind it.
        SectionHeader(title: title),
        if (labelled)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, 2, AppSpace.lg, 0),
            child: Text(
              'Featured by the marketplace team',
              style: AppTextStyles.bodySmall.copyWith(
                color: context.palette.textMuted,
              ),
            ),
          ),
        const SizedBox(height: AppSpace.md),
        SizedBox(
          height: ShopCard.railHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
            itemCount: shops.length,
            separatorBuilder: (context, i) => const SizedBox(width: AppSpace.md),
            itemBuilder: (context, i) {
              final shop = shops[i];
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
            icon: cat.materialIcon,
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
            !isOffline
                ? _error!
                : _isDefaultScope
                ? 'No products cached yet.'
                // Only the default grid is cached; any other filter needs
                // the network, which is not the same as "nothing cached".
                : "This filter needs a connection. Switch back to All to "
                      'see saved products.',
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
    // Empty *because of the country filter*, which is a different problem
    // from an empty marketplace and needs a different way out.
    final scoped = !_worldwide;
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
            searching
                ? 'Nothing matches "$_query"'
                : scoped
                ? 'Nothing listed in ${Countries.nameOf(_country)} yet'
                : 'No products yet',
            textAlign: TextAlign.center,
            style: AppTextStyles.headlineMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            searching
                ? 'Try a different word, or browse a category.'
                : scoped
                // Without this the first seller in a new country opens the
                // marketplace, sees nothing, and concludes the app is
                // broken — when in fact it is working exactly as intended
                // and every existing listing is simply in Zimbabwe.
                ? 'The marketplace shows your country by default. Switch to '
                      'Worldwide above to see listings from everywhere.'
                : 'Know an SDA business owner? Tell them about us.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: context.palette.textMuted,
              height: 1.5,
            ),
          ),
          if (!searching && scoped) ...[
            const SizedBox(height: AppSpace.xl),
            TextButton.icon(
              onPressed: () {
                setState(() => _worldwide = true);
                _loadProducts(filterChanged: true);
              },
              icon: const Icon(Icons.public, size: 18),
              label: const Text('Browse worldwide'),
            ),
          ],
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
              'Selling on Adventist Super App',
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
                  // Pushed, not gone to: Back from Jobs returns here.
                  : () => context.pushNamed('jobs'),
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
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  /// Selected is Primary Blue with white, per the colour rules ("buttons,
  /// active states"). It was `palette.text` — a white pill in dark mode,
  /// the brightest thing on the screen, for a filter.
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fg = selected ? AppColors.white : palette.text;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.94,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md + 2,
          vertical: AppSpace.sm,
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryBlue : palette.card,
          borderRadius: AppRadius.pillAll,
          border: Border.all(
            color: selected ? AppColors.primaryBlue : palette.divider,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? AppColors.white : AppColors.primaryBlue,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyles.labelMedium.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Collapsing marketplace header.
///
/// At rest it shows the tagline, the title and the search field. As you scroll
/// the title block fades and shrinks away and the search row pins, so the
/// product grid climbs to the top of the screen instead of living underneath
/// a permanent block of chrome.
///
/// There is deliberately **no back button**. Marketplace is a root tab reached
/// from the nav island — the arrow it used to carry either popped to a screen
/// the member had never visited or, on a fresh launch with nothing to pop,
/// silently went to Home.
class _MarketHeaderDelegate extends SliverPersistentHeaderDelegate {
  _MarketHeaderDelegate({
    required this.topInset,
    required this.textScale,
    required this.controller,
    required this.query,
    required this.onQueryChanged,
    required this.onClearQuery,
    required this.onCartTap,
  });

  final double topInset;

  /// `MediaQuery.textScalerOf(context).scale(1)` — the reader's text size
  /// setting. A [SliverPersistentHeaderDelegate] must declare its height
  /// from [maxExtent] / [minExtent], which have no BuildContext, so the
  /// scale has to arrive as a field.
  final double textScale;

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearQuery;
  final VoidCallback onCartTap;

  // -------------------------------------------------------------------
  //  Heights
  //
  //  These were `static const 58` and `static const 60`, and the title
  //  block OVERFLOWED AT EVERY TEXT SIZE, default included (founder
  //  report, 25 Aug 2026 — "pixel overflow in marketplace header where
  //  it says shop within the community"). The arithmetic nobody did:
  //
  //     top padding (AppSpace.sm)                         8.0
  //     'MARKETPLACE'   10pt Poppins, no explicit height ~15.0
  //     gap                                               4.0
  //     the headline    24pt Poppins, no explicit height ~36.0
  //                                                     ------
  //                                                      63.0  into 58
  //
  //  Poppins carries ~1.5em of line box in its own metrics, so a 24pt
  //  line is ~36pt tall, not 24. The two Texts were sized as if a font
  //  were exactly its point size — which is why a five-pixel overflow
  //  was baked in before the reader touched anything, and why raising
  //  the system font size made it worse rather than revealing it.
  //
  //  Fixed at both ends: the styles below now set an explicit `height`,
  //  so these numbers are the real line boxes rather than an estimate,
  //  and the total is multiplied by the reader's text scale instead of
  //  pretending it is always 1.0.
  // -------------------------------------------------------------------

  /// Line-height multipliers pinned on the two title Texts. Changing
  /// either without changing the other is how this drifts back.
  static const double _taglineHeight = 1.3;
  static const double _headlineHeight = 1.2;

  static const double _taglineSize = 10;
  static const double _headlineSize = 24;
  static const double _titleGap = 4;

  /// Clamp on how far the text setting may stretch the header.
  ///
  /// Not a refusal to honour accessibility — the text itself still
  /// scales, and the headline ellipsizes rather than being cut. It stops
  /// a 2.0x setting turning a header into most of a small phone's
  /// screen, which would leave nowhere for the products the header is
  /// there to introduce.
  static const double _maxHeaderScale = 1.5;

  double get _scale => textScale.clamp(1.0, _maxHeaderScale);

  /// Text layout rounds each line box up to whole pixels, so the sum above
  /// can come in a fraction short — a 0.2px overflow showed up in widget
  /// tests. Two pixels of slack absorbs it for both lines.
  static const double _roundingSlack = 2;

  /// Title block: tagline + headline. This is what scrolls away.
  double get _titleBody =>
      AppSpace.sm +
      (_taglineSize * _taglineHeight +
              _titleGap +
              _headlineSize * _headlineHeight) *
          _scale +
      _roundingSlack;

  /// Search row + the basket button beside it. This is what pins.
  ///
  /// Scales for the same reason: it holds a TextField whose text grows
  /// with the setting too, and 60 was measured at 1.0.
  double get _searchBody => 60 * _scale;

  @override
  double get maxExtent => topInset + _titleBody + _searchBody;

  @override
  double get minExtent => topInset + _searchBody;

  @override
  bool shouldRebuild(covariant _MarketHeaderDelegate old) =>
      old.topInset != topInset ||
      old.query != query ||
      old.textScale != textScale;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final palette = context.palette;
    final t = _titleBody <= 0
        ? 0.0
        : (shrinkOffset / _titleBody).clamp(0.0, 1.0);

    return Material(
      color: palette.scaffoldBg,
      child: Padding(
        padding: EdgeInsets.only(top: topInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Collapses to zero height as it fades, so the search row rides
            // up rather than leaving a gap behind it.
            ClipRect(
              child: Align(
                alignment: Alignment.topLeft,
                heightFactor: 1 - t,
                child: Opacity(
                  opacity: (1 - t * 1.6).clamp(0.0, 1.0),
                  child: SizedBox(
                    height: _titleBody,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpace.lg,
                        AppSpace.sm,
                        AppSpace.lg,
                        0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // `height` on both is what makes _titleBody
                          // above a measurement rather than a guess.
                          // Read the note there before changing either.
                          Text(
                            'MARKETPLACE',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.primaryBlue,
                              fontSize: _taglineSize,
                              height: _taglineHeight,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.6,
                            ),
                          ),
                          const SizedBox(height: _titleGap),
                          Text(
                            'Shop within the community',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.displayMedium.copyWith(
                              color: palette.text,
                              fontSize: _headlineSize,
                              height: _headlineHeight,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: _searchBody,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.lg,
                  AppSpace.sm,
                  AppSpace.lg,
                  AppSpace.md,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        onChanged: onQueryChanged,
                        textInputAction: TextInputAction.search,
                        style: AppTextStyles.bodyMedium,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Search products and shops',
                          prefixIcon: const Icon(
                            Icons.search,
                            color: AppColors.primaryBlue,
                            size: 20,
                          ),
                          suffixIcon: query.isEmpty
                              ? null
                              : IconButton(
                                  icon: Icon(
                                    Icons.close,
                                    size: 18,
                                    color: palette.textMuted,
                                  ),
                                  onPressed: onClearQuery,
                                ),
                          filled: true,
                          fillColor: palette.inputFill,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: AppSpace.sm,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    CartBadgeButton(onTap: onCartTap),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pins the category chips directly under the header, so filtering stays one
/// tap away however far down the grid the member has scrolled.
class _CategoryStripDelegate extends SliverPersistentHeaderDelegate {
  _CategoryStripDelegate({required this.child});

  final Widget child;

  static const double _height = 52;

  @override
  double get maxExtent => _height;

  @override
  double get minExtent => _height;

  @override
  bool shouldRebuild(covariant _CategoryStripDelegate old) =>
      old.child != child;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return Material(
      color: context.palette.scaffoldBg,
      child: SizedBox(height: _height, child: child),
    );
  }
}

/// One horizontal shelf of listings (Recently viewed, New arrivals,
/// Featured). Fixed-height tiles so prices line up across the row.
class _ProductShelf extends StatelessWidget {
  const _ProductShelf({
    required this.title,
    required this.products,
    required this.savedIds,
    required this.onToggleSave,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Product> products;
  final Set<String> savedIds;
  final void Function(Product) onToggleSave;

  static const double _tileWidth = 156;
  static const double _height = 252;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpace.xl),
        SectionHeader(title: title),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, 2, AppSpace.lg, 0),
            child: Text(
              subtitle!,
              style: AppTextStyles.bodySmall.copyWith(
                color: context.palette.textMuted,
              ),
            ),
          ),
        const SizedBox(height: AppSpace.md),
        SizedBox(
          height: _height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
            itemCount: products.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpace.md),
            itemBuilder: (context, i) {
              final p = products[i];
              return SizedBox(
                width: _tileWidth,
                // No hero tag: the same listing can sit on a shelf and in
                // the grid at once, and duplicate tags throw.
                child: ProductTile(
                  product: p,
                  saved: savedIds.contains(p.id),
                  onToggleSave: () => onToggleSave(p),
                  onTap: () => context.pushNamed(
                    'product_details',
                    pathParameters: {'id': p.id},
                    extra: p,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Filters + sort above the grid. One row: a Filters button that shows
/// how many are on, the result count, and the sort menu.
class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.filters,
    required this.resultCount,
    required this.onOpenFilters,
    required this.onSort,
    required this.onClear,
  });

  final MarketFilters filters;
  final int? resultCount;
  final VoidCallback onOpenFilters;
  final ValueChanged<MarketSort> onSort;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final n = filters.activeCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, 0),
      child: Row(
        children: [
          Material(
            color: n > 0 ? AppColors.primaryBlue : palette.card,
            borderRadius: BorderRadius.circular(AppRadius.button),
            child: InkWell(
              onTap: onOpenFilters,
              borderRadius: BorderRadius.circular(AppRadius.button),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                  border: n > 0 ? null : Border.all(color: palette.divider),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 18,
                      color: n > 0 ? AppColors.white : palette.text,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      n > 0 ? 'Filters · $n' : 'Filters',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: n > 0 ? AppColors.white : palette.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (onClear != null)
            TextButton(onPressed: onClear, child: const Text('Clear')),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              resultCount == null
                  ? ''
                  : '$resultCount listing${resultCount == 1 ? '' : 's'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
            ),
          ),
          PopupMenuButton<MarketSort>(
            initialValue: filters.sort,
            onSelected: onSort,
            tooltip: 'Sort',
            itemBuilder: (_) => [
              for (final s in MarketSort.values)
                PopupMenuItem(value: s, child: Text(s.label)),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sort_rounded, size: 18, color: palette.text),
                const SizedBox(width: 4),
                Text(
                  filters.sort.label,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: palette.text,
                    fontWeight: FontWeight.w600,
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
