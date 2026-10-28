import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/product_model.dart';

/// Sizes/colours, stock and specifications (patch_280).
///
/// Until the patch runs the columns and the product_variants table don't
/// exist: [probe] finds that out once, the form hides the new section and
/// listings save exactly as before.
class ProductOptionsService {
  ProductOptionsService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static bool? _available;
  static bool get available => _available ?? true;

  static bool _missing(Object e) {
    final s = e.toString();
    return s.contains('42703') ||
        s.contains('PGRST204') ||
        s.contains('PGRST205') ||
        s.contains('42P01') ||
        s.contains('stock_quantity') ||
        s.contains('product_variants');
  }

  /// Whether patch_280 is in. Cached for the session.
  static Future<bool> probe() async {
    if (_available != null) return _available!;
    try {
      await _client.from('products').select('id, stock_quantity').limit(1);
      return _available = true;
    } catch (e) {
      if (_missing(e)) return _available = false;
      return true; // offline etc. — don't hide anything on a guess
    }
  }

  /// The product's option combinations, in the seller's order.
  static Future<List<ProductVariant>> fetchVariants(String productId) async {
    final id = int.tryParse(productId);
    if (id == null || !available) return const [];
    try {
      final rows = await _client
          .from('product_variants')
          .select()
          .eq('product_id', id)
          .order('sort');
      return [
        for (final r in rows as List)
          ProductVariant.fromJson(r as Map<String, dynamic>),
      ];
    } catch (e) {
      if (_missing(e)) _available = false;
      return const [];
    }
  }

  /// Saves stock, options, specs and the option combinations together.
  ///
  /// [stockQuantity] is written only for a product without options — with
  /// options the server keeps it as the combinations' total.
  static Future<void> save({
    required String productId,
    required int? stockQuantity,
    required List<ProductOptionGroup> optionGroups,
    required List<ProductSpec> specs,
    required List<ProductVariant> variants,
  }) async {
    final id = int.parse(productId);
    await _client
        .from('products')
        .update({
          'option_groups': [for (final g in optionGroups) g.toJson()],
          'specs': [for (final r in specs) r.toJson()],
          if (optionGroups.isEmpty) 'stock_quantity': stockQuantity,
        })
        .eq('id', id);

    final keep = optionGroups.isEmpty ? const <ProductVariant>[] : variants;
    final existing = await _client
        .from('product_variants')
        .select('id, label')
        .eq('product_id', id);
    final keepLabels = {for (final v in keep) v.label};
    final stale = [
      for (final r in existing as List)
        if (!keepLabels.contains((r as Map)['label'])) r['id'],
    ];
    if (stale.isNotEmpty) {
      await _client.from('product_variants').delete().inFilter('id', stale);
    }
    if (keep.isNotEmpty) {
      await _client.from('product_variants').upsert([
        for (final v in keep) v.toRow(productId),
      ], onConflict: 'product_id,label');
    }
  }
}
