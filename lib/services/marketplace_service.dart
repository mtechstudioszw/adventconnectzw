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
    var query = _client.from(_table).select().eq('is_available', true);

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
}
