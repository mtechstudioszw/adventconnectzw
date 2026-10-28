import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product_model.dart';
import '../utils/postgrest_filter.dart';
import 'seller_service.dart';
import 'post_limit_error.dart';
import 'market_ranking.dart';

class MarketplaceService {
  MarketplaceService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static const _table = 'products';
  static const _savedTable = 'saved_listings';
  static const _sellersTable = 'sellers';

  /// Approved, active sellers: auth_user_id → shop name. Gates the
  /// marketplace so products from pending / rejected / banned sellers
  /// never reach buyers (patch_031). A separate query because PostgREST
  /// doesn't compose subqueries cleanly; one row per seller.
  ///
  /// `products` has no seller-name column, so every grid tile, saved
  /// listing and basket line read the fallback and said "Seller". The
  /// approval lookup was already being made; it now brings the name too.
  static Future<Map<String, String>> _fetchApprovedSellers() async =>
      {for (final e in (await _approvedSellerMeta()).entries) e.key: e.value.name};

  /// The approved sellers with what ranking needs: name, when they were
  /// approved, and their rating. One query, as before.
  static Future<Map<String, _SellerMeta>> _approvedSellerMeta() async {
    final rows = await _client
        .from(_sellersTable)
        .select('auth_user_id, business_name, approved_at, created_at, '
            'rating, rating_count')
        .eq('status', 'approved')
        .eq('is_active', true);
    return {
      for (final r in (rows as List).cast<Map<String, dynamic>>())
        if ((r['auth_user_id'] ?? '').toString().isNotEmpty)
          r['auth_user_id'].toString(): _SellerMeta(
            name: ((r['business_name'] as String?)?.trim().isNotEmpty ?? false)
                ? (r['business_name'] as String).trim()
                : 'Seller',
            since: DateTime.tryParse(
              (r['approved_at'] ?? r['created_at'] ?? '').toString(),
            ),
            rating: (r['rating'] as num?)?.toDouble() ?? 0,
            ratingCount: (r['rating_count'] as num?)?.toInt() ?? 0,
          ),
    };
  }

  /// Fills `seller_name` on product rows from [sellers] before parsing.
  static Product _withSellerName(
    Map<String, dynamic> row,
    Map<String, String> sellers,
  ) {
    final name = sellers[(row['seller_id'] ?? '').toString()];
    if (name != null && row['seller_name'] == null) row['seller_name'] = name;
    return Product.fromJson(row);
  }

  /// Returns the set of product ids the current user has saved. Used by
  /// the marketplace heart icon and the My Saved Listings screen.
  static Future<Set<String>> fetchSavedProductIds() async {
    final user = _client.auth.currentUser;
    if (user == null) return <String>{};
    final response = await _client
        .from(_savedTable)
        .select('product_id')
        .eq('user_id', user.id);
    return (response as List)
        .map((row) => row['product_id'].toString())
        .toSet();
  }

  static Future<bool> isSaved(String productId) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    final response = await _client
        .from(_savedTable)
        .select('product_id')
        .eq('user_id', user.id)
        .eq('product_id', productId)
        .maybeSingle();
    return response != null;
  }

  static Future<void> saveProduct(String productId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to save a listing.');
    }
    await _client.from(_savedTable).insert({
      'user_id': user.id,
      'product_id': productId,
    });
  }

  static Future<void> unsaveProduct(String productId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from(_savedTable)
        .delete()
        .eq('user_id', user.id)
        .eq('product_id', productId);
  }

  /// Returns the full Product rows for every listing the user saved.
  /// Joins via product_id IN (...) instead of a foreign-key embed so
  /// it works regardless of how the RLS view is set up. Hides items
  /// from sellers that are no longer approved (patch_031) so the
  /// saved-listings screen stays in sync with the public marketplace.
  static Future<List<Product>> fetchSavedProducts() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    final saved = await _client
        .from(_savedTable)
        .select('product_id')
        .eq('user_id', user.id);
    final ids = (saved as List)
        .map((row) => row['product_id'].toString())
        .toList();
    if (ids.isEmpty) return const [];
    final sellers = await _fetchApprovedSellers();
    final response = await _client
        .from(_table)
        .select()
        .inFilter('id', ids)
        .order('created_at', ascending: false);
    return (response as List)
        .map((row) => _withSellerName(row as Map<String, dynamic>, sellers))
        .where((p) => sellers.containsKey(p.sellerId))
        .toList();
  }

  /// Ranked listings for callers that just want a list (Home's rail,
  /// global search). See [fetchCatalog] for the marketplace itself.
  static Future<List<Product>> fetchProducts({
    String? search,
    String? category,
    String? country,
  }) async {
    final catalog = await fetchCatalog(
      search: search,
      category: category,
      country: country,
    );
    return catalog.ranked(viewer: _client.auth.currentUser?.id ?? '');
  }

  /// Listings plus what the ranking needs about their sellers.
  ///
  /// Everything that narrows the list happens in the query — category,
  /// country, price, condition, place, seller and the search text —
  /// so filters apply to the whole catalogue, not to a page already
  /// fetched. Search matches the title, the description AND the shop name
  /// (products have no seller-name column, so names are matched against
  /// the approved-seller list and folded in as seller ids).
  ///
  /// [country]: ISO 3166-1 alpha-2, null = worldwide. Country-scoped by
  /// default (founder, 18 Aug 2026): the sale is a WhatsApp handoff and
  /// local pickup, so another country's listing is one a buyer can't act on.
  static Future<MarketCatalog> fetchCatalog({
    String? search,
    String? category,
    String? country,
    MarketFilters filters = MarketFilters.none,
    int limit = 200,
  }) async {
    final sellers = await _approvedSellerMeta();
    if (sellers.isEmpty) return MarketCatalog.empty;
    final approvedIds = sellers.keys.toList();

    var query = _client
        .from(_table)
        .select()
        .eq('status', 'available')
        .inFilter('seller_id', approvedIds);

    if (country != null && country.isNotEmpty) {
      query = query.eq('country', country);
    }
    if (category != null && category.isNotEmpty && category != 'all') {
      query = query.eq('category', category);
    }
    if (filters.minPrice != null) query = query.gte('price', filters.minPrice!);
    if (filters.maxPrice != null) query = query.lte('price', filters.maxPrice!);
    if (filters.condition != null) {
      query = query.eq('condition', filters.condition!);
    }
    if (filters.sellerId != null) {
      query = query.eq('seller_id', filters.sellerId!);
    }
    final place = (filters.location ?? '').trim();
    if (place.isNotEmpty) {
      final t = orFilterValue('%$place%');
      query = query.or('location.ilike.$t,province.ilike.$t');
    }

    final term = (search ?? '').trim();
    final matchedSellers = <String>{};
    if (term.isNotEmpty) {
      final lower = term.toLowerCase();
      for (final e in sellers.entries) {
        if (e.value.name.toLowerCase().contains(lower)) matchedSellers.add(e.key);
      }
      final t = orFilterValue('%$term%');
      query = query.or([
        'title.ilike.$t',
        'description.ilike.$t',
        if (matchedSellers.isNotEmpty)
          'seller_id.in.(${matchedSellers.join(',')})',
      ].join(','));
    }

    final response =
        await query.order('created_at', ascending: false).limit(limit);
    final products = (response as List)
        .map((row) => _withSellerName(
              row as Map<String, dynamic>,
              {for (final e in sellers.entries) e.key: e.value.name},
            ))
        .toList();

    final now = DateTime.now();
    return MarketCatalog(
      products: products,
      // A seller's first three weeks after approval.
      newSellerIds: {
        for (final e in sellers.entries)
          if (e.value.since != null &&
              now.difference(e.value.since!).inDays <= 21)
            e.key,
      },
      // Only ratings that rest on enough reviews to mean something.
      sellerRatings: {
        for (final e in sellers.entries)
          if (e.value.ratingCount >= 3) e.key: e.value.rating,
      },
      matchedSellerIds: matchedSellers,
    );
  }

  /// Counts a buyer opening a listing (patch_277). Once per viewer per
  /// listing per day, never the seller; the server decides all of that.
  /// Fire-and-forget — before the patch runs this simply does nothing.
  static Future<void> recordView(String productId) async {
    final id = int.tryParse(productId);
    if (id == null || _client.auth.currentUser == null) return;
    try {
      await _client.rpc('record_product_view', params: {'p_product': id});
    } catch (_) {}
  }

  static Future<Product?> fetchProductById(String id) async {
    final response =
        await _client.from(_table).select().eq('id', id).maybeSingle();
    if (response == null) return null;
    final viewerId = _client.auth.currentUser?.id;
    // A listing the seller took down is gone for everyone but them. It used
    // to open from a shared link anyway, labelled "RESERVED".
    // Super admins still open it — that is how they restore a listing
    // after an appeal (patch_272 lets them read it).
    if (response['status'] == 'removed' &&
        response['seller_id']?.toString() != viewerId &&
        !await SellerService.isCurrentUserSuperAdmin()) {
      return null;
    }
    // products has no seller_phone / seller_name column — those live on
    // the sellers row keyed by auth_user_id. Hydrate them here so the
    // product details screen can render the WhatsApp + name affordances
    // without a second round-trip on the screen side.
    final sellerId = (response['seller_id'] ?? '').toString();
    if (sellerId.isNotEmpty) {
      try {
        final sellerRow = await _client
            .from('sellers')
            .select(
              'business_name, phone, whatsapp, contact_name, verified, '
                  'sda_verified, status, is_active',
            )
            .eq('auth_user_id', sellerId)
            .maybeSingle();
        if (sellerRow != null) {
          // patch_031: hide products from non-approved storefronts
          // from everyone except the owning seller (who needs to see
          // their own listings in the dashboard).
          final approved = sellerRow['status'] == 'approved' &&
              sellerRow['is_active'] != false;
          if (!approved && sellerId != viewerId) return null;
          response['seller_phone'] =
              (sellerRow['whatsapp'] as String?)?.trim().isNotEmpty == true
                  ? sellerRow['whatsapp']
                  : sellerRow['phone'];
          response['seller_name'] =
              sellerRow['business_name'] ?? response['seller_name'];
          response['seller_verified'] =
              sellerRow['verified'] == true ||
                  sellerRow['sda_verified'] == true;
        }
      } catch (_) {
        // Don't fail product load if seller lookup hiccups — buyer can
        // still see the product, just without the WhatsApp shortcut.
      }
    }
    return Product.fromJson(response);
  }

  static Future<String> postProduct({
    required String title,
    required double price,
    required String category,
    String? description,
    String priceCurrency = 'USD',
    String? subcategory,
    List<String>? imageUrls,
    String? condition,
    /// ISO 3166-1 alpha-2 (patch_213). Always send it: the column DEFAULTs
    /// to 'ZW', so omitting it silently brands a Kenyan listing Zimbabwean.
    String? country,
    /// Province for ZW, free-text region elsewhere. Optional either way.
    String? province,
    String? location,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to post a product.');
    }
    final inserted = await PostLimitError.guard(
      PostSection.product,
      () => _client.from(_table).insert({
        'seller_id': user.id,
        'title': title.trim(),
        'description': description?.trim(),
        'price': price,
        'price_currency': priceCurrency,
        'category': category,
        'subcategory': subcategory?.trim(),
        'image_urls': imageUrls ?? const [],
        'condition': condition,
        'country': country,
        'province': province?.trim(),
        'location': location?.trim(),
      }).select('id').single(),
    );
    return inserted['id'].toString();
  }
}

class _SellerMeta {
  const _SellerMeta({
    required this.name,
    required this.since,
    required this.rating,
    required this.ratingCount,
  });
  final String name;
  final DateTime? since;
  final double rating;
  final int ratingCount;
}

/// What the marketplace query returns: the listings, unordered, and the
/// seller facts the ranking reads.
class MarketCatalog {
  const MarketCatalog({
    required this.products,
    this.newSellerIds = const {},
    this.sellerRatings = const {},
    this.matchedSellerIds = const {},
  });

  final List<Product> products;
  final Set<String> newSellerIds;
  final Map<String, double> sellerRatings;

  /// Shops whose NAME matched the search.
  final Set<String> matchedSellerIds;

  static const empty = MarketCatalog(products: []);

  List<Product> ranked({
    String viewer = '',
    MarketSort sort = MarketSort.best,
    Set<String> interestCategories = const {},
    DateTime? now,
  }) => MarketRanking.rank(
    products,
    sort: sort,
    now: now ?? DateTime.now(),
    viewer: viewer,
    newSellerIds: newSellerIds,
    sellerRatings: sellerRatings,
    interestCategories: interestCategories,
  );
}
