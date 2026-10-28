import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product_model.dart';
import '../utils/postgrest_filter.dart';
import 'post_limit_error.dart';

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
  static Future<Map<String, String>> _fetchApprovedSellers() async {
    final rows = await _client
        .from(_sellersTable)
        .select('auth_user_id, business_name')
        .eq('status', 'approved')
        .eq('is_active', true);
    return {
      for (final r in (rows as List).cast<Map<String, dynamic>>())
        if ((r['auth_user_id'] ?? '').toString().isNotEmpty)
          r['auth_user_id'].toString():
              ((r['business_name'] as String?)?.trim().isNotEmpty ?? false)
                  ? (r['business_name'] as String).trim()
                  : 'Seller',
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

  static Future<List<Product>> fetchProducts({
    String? search,
    String? category,
    /// ISO 3166-1 alpha-2. Null means worldwide.
    ///
    /// The marketplace is country-scoped by default (founder, 18 Aug 2026)
    /// because this app never handles the sale: handoff is WhatsApp plus
    /// local pickup, so a listing in another country is one the buyer
    /// cannot act on. Showing it is not generosity, it is noise — and it
    /// mixes currencies in the grid for no reachable listing.
    ///
    /// Worldwide stays one tap away rather than being removed: the
    /// diaspora genuinely does buy from home, and a member whose profile
    /// country is wrong needs an escape hatch that is not "edit profile".
    String? country,
  }) async {
    final sellers = await _fetchApprovedSellers();
    if (sellers.isEmpty) return const [];
    final approvedIds = sellers.keys.toSet();

    var query = _client
        .from(_table)
        .select()
        .eq('status', 'available')
        .inFilter('seller_id', approvedIds.toList());

    if (country != null && country.isNotEmpty) {
      query = query.eq('country', country);
    }

    if (category != null && category.isNotEmpty && category != 'all') {
      query = query.eq('category', category);
    }

    if (search != null && search.trim().isNotEmpty) {
      final term = orFilterValue('%${search.trim()}%');
      query = query.or('title.ilike.$term,description.ilike.$term');
    }

    // Pull the most recent 200, then SHUFFLE so the grid is mixed rather
    // than strictly newest-first — newer sellers' items still surface and
    // the marketplace doesn't look like a chronological feed.
    final response =
        await query.order('created_at', ascending: false).limit(200);

    final list = (response as List)
        .map((row) => _withSellerName(row as Map<String, dynamic>, sellers))
        .toList();
    list.shuffle();
    return list;
  }

  static Future<Product?> fetchProductById(String id) async {
    final response =
        await _client.from(_table).select().eq('id', id).maybeSingle();
    if (response == null) return null;
    final viewerId = _client.auth.currentUser?.id;
    // A listing the seller took down is gone for everyone but them. It used
    // to open from a shared link anyway, labelled "RESERVED".
    if (response['status'] == 'removed' &&
        response['seller_id']?.toString() != viewerId) {
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
