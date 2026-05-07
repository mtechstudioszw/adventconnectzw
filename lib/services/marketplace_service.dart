import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product_model.dart';

class MarketplaceService {
  MarketplaceService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static const _table = 'products';

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
