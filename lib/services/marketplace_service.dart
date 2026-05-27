import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product_model.dart';

class MarketplaceService {
  MarketplaceService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static const _table = 'products';
  static const _savedTable = 'saved_listings';

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
  /// it works regardless of how the RLS view is set up.
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
    final response = await _client
        .from(_table)
        .select()
        .inFilter('id', ids)
        .order('created_at', ascending: false);
    return (response as List)
        .map((row) => Product.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  static Future<List<Product>> fetchProducts({
    String? search,
    String? category,
  }) async {
    var query = _client.from(_table).select().eq('status', 'available');

    if (category != null && category.isNotEmpty && category != 'all') {
      query = query.eq('category', category);
    }

    if (search != null && search.trim().isNotEmpty) {
      final term = '%${search.trim()}%';
      query = query.or('title.ilike.$term,description.ilike.$term');
    }

    final response =
        await query.order('created_at', ascending: false).limit(200);

    return (response as List)
        .map((row) => Product.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  static Future<Product?> fetchProductById(String id) async {
    final response =
        await _client.from(_table).select().eq('id', id).maybeSingle();
    if (response == null) return null;
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
              'business_name, phone, whatsapp, contact_name, verified, sda_verified',
            )
            .eq('auth_user_id', sellerId)
            .maybeSingle();
        if (sellerRow != null) {
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
    String? province,
    String? location,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to post a product.');
    }
    final inserted = await _client.from(_table).insert({
      'seller_id': user.id,
      'title': title.trim(),
      'description': description?.trim(),
      'price': price,
      'price_currency': priceCurrency,
      'category': category,
      'subcategory': subcategory?.trim(),
      'image_urls': imageUrls ?? const [],
      'condition': condition,
      'province': province?.trim(),
      'location': location?.trim(),
    }).select('id').single();
    return inserted['id'].toString();
  }
}
