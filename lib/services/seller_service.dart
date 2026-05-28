import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/product_model.dart';
import '../models/seller_model.dart';
import 'analytics_service.dart';

/// All seller-side reads/writes — the application row in `sellers`, plus
/// product management for the currently-signed-in seller. Public reads
/// of products by buyers stay in `MarketplaceService`.
class SellerService {
  SellerService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static const _sellersTable = 'sellers';
  static const _productsTable = 'products';

  /// Public lookup by the auth user id. Products store the seller's
  /// `auth_user_id` (not the row id), so the buyer-facing
  /// product_details → seller_profile jump goes through this.
  static Future<Seller?> fetchSellerByAuthUserId(String authUserId) async {
    if (authUserId.isEmpty) return null;
    final row = await _client
        .from(_sellersTable)
        .select()
        .eq('auth_user_id', authUserId)
        .maybeSingle();
    if (row == null) return null;
    return Seller.fromJson(row);
  }

  /// Public list of an approved seller's available products. Hidden
  /// rows are filtered out — buyers shouldn't see paused listings.
  static Future<List<Product>> fetchPublicProductsByAuthUserId(
    String authUserId,
  ) async {
    if (authUserId.isEmpty) return const [];
    final response = await _client
        .from(_productsTable)
        .select()
        .eq('seller_id', authUserId)
        .eq('status', 'available')
        .order('created_at', ascending: false);
    return (response as List)
        .map((row) => Product.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Returns the current user's seller row, or null if they have not
  /// applied yet. Used by the dashboard to decide whether to show the
  /// setup CTA, the pending/rejected banners, or the full dashboard.
  static Future<Seller?> fetchMySellerProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final row = await _client
        .from(_sellersTable)
        .select()
        .eq('auth_user_id', user.id)
        .maybeSingle();
    if (row == null) return null;
    return Seller.fromJson(row);
  }

  /// Open a storefront. Self-serve as of patch_022 — anyone authenticated
  /// can publish immediately, gated by the Marketplace Code of Conduct
  /// (acceptance enforced by the [termsVersion] arg + a CHECK on the
  /// sellers table). Admin moderation is reactive (is_active = false /
  /// status = 'banned') rather than gatekeeping.
  ///
  /// [termsVersion] MUST be the value the user accepted on
  /// MarketplaceGuidelinesScreen — the DB constraint rejects insert
  /// if terms_accepted_at is null on an approved row.
  static Future<Seller> applyAsSeller({
    required String businessName,
    required String category,
    required String phone,
    required String termsVersion,
    String? description,
    String? province,
    String? city,
    String? suburb,
    String? address,
    String? whatsapp,
    String? contactName,
    String? profilePhotoUrl,
    String? coverPhotoUrl,
    String? paymentMethods,
    bool offersDelivery = false,
    String? deliveryArea,
    String? deliveryFee,
    bool observesSabbath = false,
    String? sabbathNoticeText,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to open a store.');
    }
    final row = <String, dynamic>{
      'auth_user_id': user.id,
      'business_name': businessName.trim(),
      'category': category,
      'description': description?.trim(),
      'province': province,
      'city': city?.trim(),
      'suburb': suburb?.trim(),
      'address': address?.trim(),
      'phone': phone.trim(),
      'whatsapp': whatsapp?.trim(),
      'contact_name': contactName?.trim(),
      'profile_photo_url': profilePhotoUrl,
      'cover_photo_url': coverPhotoUrl,
      'payment_methods': paymentMethods?.trim(),
      'offers_delivery': offersDelivery,
      'delivery_area': deliveryArea?.trim(),
      'delivery_fee': deliveryFee?.trim(),
      'observes_sabbath': observesSabbath,
      'sabbath_notice_text': sabbathNoticeText?.trim(),
      // Self-serve: insert as already-approved + record the code of
      // conduct version they accepted on the gate screen.
      'status': 'approved',
      'approved_at': DateTime.now().toUtc().toIso8601String(),
      'terms_accepted_at': DateTime.now().toUtc().toIso8601String(),
      'terms_version': termsVersion,
    };
    Map<String, dynamic> inserted;
    try {
      inserted = await _client
          .from(_sellersTable)
          .insert(row)
          .select()
          .single();
    } catch (_) {
      // Older deployments may not have the cover_photo_url column yet —
      // retry without it so the application still goes through.
      row.remove('cover_photo_url');
      inserted = await _client
          .from(_sellersTable)
          .insert(row)
          .select()
          .single();
    }
    AnalyticsService.sellerApplied();
    return Seller.fromJson(inserted);
  }

  /// Update the seller's storefront. Category is intentionally not in
  /// the parameter list — once approved a seller cannot drift into a
  /// different category without admin re-review.
  static Future<Seller> updateMySellerProfile({
    required String sellerId,
    String? businessName,
    String? description,
    String? province,
    String? city,
    String? suburb,
    String? address,
    String? phone,
    String? whatsapp,
    String? contactName,
    String? profilePhotoUrl,
    String? coverPhotoUrl,
    String? paymentMethods,
    bool? offersDelivery,
    String? deliveryArea,
    String? deliveryFee,
    bool? observesSabbath,
    String? sabbathNoticeText,
    bool? isActive,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to update your storefront.');
    }
    // Each `?` drops the entry when the value is null, so callers can
    // pass a partial update without explicit nullability noise.
    final updates = <String, dynamic>{
      'business_name': ?businessName?.trim(),
      'description': ?description?.trim(),
      'province': ?province,
      'city': ?city?.trim(),
      'suburb': ?suburb?.trim(),
      'address': ?address?.trim(),
      'phone': ?phone?.trim(),
      'whatsapp': ?whatsapp?.trim(),
      'contact_name': ?contactName?.trim(),
      'profile_photo_url': ?profilePhotoUrl,
      'cover_photo_url': ?coverPhotoUrl,
      'payment_methods': ?paymentMethods?.trim(),
      'offers_delivery': ?offersDelivery,
      'delivery_area': ?deliveryArea?.trim(),
      'delivery_fee': ?deliveryFee?.trim(),
      'observes_sabbath': ?observesSabbath,
      'sabbath_notice_text': ?sabbathNoticeText?.trim(),
      'is_active': ?isActive,
    };
    Map<String, dynamic> updated;
    try {
      updated = await _client
          .from(_sellersTable)
          .update(updates)
          .eq('id', sellerId)
          .eq('auth_user_id', user.id)
          .select()
          .single();
    } catch (_) {
      // Retry without cover_photo_url when the column hasn't been
      // migrated yet.
      updates.remove('cover_photo_url');
      updated = await _client
          .from(_sellersTable)
          .update(updates)
          .eq('id', sellerId)
          .eq('auth_user_id', user.id)
          .select()
          .single();
    }
    return Seller.fromJson(updated);
  }

  /// Lists every product owned by the current user — including
  /// unavailable ones, since the dashboard needs to show both. The
  /// public marketplace filters out unavailable items elsewhere.
  static Future<List<Product>> fetchMyProducts() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to view your products.');
    }
    final response = await _client
        .from(_productsTable)
        .select()
        .eq('seller_id', user.id)
        .order('created_at', ascending: false);
    return (response as List)
        .map((row) => Product.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Update an existing product's editable fields. Only the owning
  /// seller can call this — the `.eq('seller_id', user.id)` is
  /// belt-and-braces on top of the RLS policy.
  static Future<Product> updateProduct({
    required String productId,
    required String title,
    required double price,
    required String currency,
    required String category,
    String? description,
    List<String>? imageUrls,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to update your products.');
    }
    final updates = <String, dynamic>{
      'title': title.trim(),
      'price': price,
      'currency': currency,
      'category': category,
      'description': description?.trim(),
      // ignore: use_null_aware_elements
      if (imageUrls != null) 'image_urls': imageUrls,
    };
    final updated = await _client
        .from(_productsTable)
        .update(updates)
        .eq('id', productId)
        .eq('seller_id', user.id) // security: owner-only
        .select()
        .single();
    return Product.fromJson(updated);
  }

  /// Toggle a product between visible/hidden on the public marketplace.
  /// We use `status` because the marketplace query already filters by
  /// `status = 'available'`; flipping it to `unavailable` hides it
  /// without deleting the product or its photos.
  static Future<void> setProductAvailability({
    required String productId,
    required bool available,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to update your products.');
    }
    // The schema carries both `status` (string) and `is_available` (bool)
    // from earlier migrations; keep them in sync so the public listing
    // query and the model's `isAvailable` getter agree.
    await _client
        .from(_productsTable)
        .update({
          'status': available ? 'available' : 'unavailable',
          'is_available': available,
        })
        .eq('id', productId)
        .eq('seller_id', user.id);
  }

  /// Permanently delete a product. RLS additionally restricts this to
  /// the owning seller — the `eq seller_id` here is belt-and-braces.
  static Future<void> deleteProduct(String productId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to delete your products.');
    }
    await _client
        .from(_productsTable)
        .delete()
        .eq('id', productId)
        .eq('seller_id', user.id);
  }

  /// Permanently delete the current user's seller row + every product
  /// they listed. RLS limits this to the owning user. The cascading
  /// product wipe is explicit (not relying on FK ON DELETE CASCADE) so
  /// callers can show progress and fail fast if any product can't be
  /// removed (e.g. RLS race after handing the store off).
  static Future<void> deleteMySellerProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to delete your store.');
    }
    await _client.from(_productsTable).delete().eq('seller_id', user.id);
    await _client.from(_sellersTable).delete().eq('auth_user_id', user.id);
  }

  /// Aggregate stats shown at the top of the dashboard. Computed
  /// client-side from a single product list fetch — cheaper than three
  /// separate count queries and the lists are small.
  static SellerStats statsFor(List<Product> products) {
    var available = 0;
    var hidden = 0;
    for (final p in products) {
      if (p.isAvailable) {
        available += 1;
      } else {
        hidden += 1;
      }
    }
    return SellerStats(
      totalProducts: products.length,
      available: available,
      hidden: hidden,
    );
  }
}

class SellerStats {
  const SellerStats({
    required this.totalProducts,
    required this.available,
    required this.hidden,
  });

  final int totalProducts;
  final int available;
  final int hidden;
}
