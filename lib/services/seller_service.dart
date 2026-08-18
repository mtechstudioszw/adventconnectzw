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

  /// Approved, active storefronts for the buyer-facing shops rail.
  ///
  /// Ordered by rating then recency so a new marketplace still shows
  /// somebody, and capped because the rail is a taster — the full list
  /// lives behind "See all".
  static Future<List<Seller>> fetchApprovedSellers({int limit = 12}) async {
    final rows = await _client
        .from(_sellersTable)
        .select()
        .eq('status', 'approved')
        .eq('is_active', true)
        .order('rating', ascending: false)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((row) => Seller.fromJson(row as Map<String, dynamic>))
        .toList();
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

  /// Open a storefront. As of patch_031 the row is inserted as
  /// `pending` — a super admin must approve it once before products
  /// from this seller appear on the public marketplace. After that
  /// the seller can list / edit / hide products freely with no
  /// further per-product review.
  ///
  /// [termsVersion] MUST be the value the user accepted on
  /// MarketplaceGuidelinesScreen so the audit trail records which
  /// version of the Code of Conduct they agreed to.
  static Future<Seller> applyAsSeller({
    required String businessName,
    required String category,
    required String phone,
    required String termsVersion,
    String? description,
    /// ISO 3166-1 alpha-2 (patch_213). Always send it — the column DEFAULTs
    /// to 'ZW', so a store opened from Nairobi without this is filed under
    /// Zimbabwe and every product it lists inherits the mistake.
    String? country,
    /// Province for ZW, free-text region elsewhere. Nullable since 213.
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
      'country': country,
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
      // patch_031: new sellers go in as pending and wait for a super
      // admin to approve. terms_accepted_at is still recorded because
      // the Code of Conduct gate runs before this screen.
      'status': 'pending',
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
    /// ISO 3166-1 alpha-2 (patch_213). Also the only way an existing seller
    /// can correct the 'ZW' the backfill gave them.
    String? country,
    /// Province for ZW, free-text region elsewhere. Travels with [country].
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
      // Country and province are written as a pair. Note the asymmetry:
      // country uses `?` because omitting it means "not editing location",
      // but province is guarded on COUNTRY and goes in even when null —
      // `?province` would skip the null and leave "Harare" on a store that
      // just moved to Kenya. Callers not touching location pass neither.
      'country': ?country,
      if (country != null) 'province': province,
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
    /// ISO 3166-1 alpha-2 (patch_213). The edit form shows a country
    /// picker, so it has to be able to save one — without this the picker
    /// would silently discard the change.
    String? country,
    /// Province for ZW, free-text region elsewhere.
    String? province,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to update your products.');
    }
    final updates = <String, dynamic>{
      'title': title.trim(),
      'price': price,
      // DB column is `price_currency` (CHECK in 'USD','ZWL','ZAR') —
      // writing to `currency` returns PGRST204 / 42703 and silently
      // surfaces as "Could not edit product".
      'price_currency': currency,
      'category': category,
      'description': description?.trim(),
      // ignore: use_null_aware_elements
      if (imageUrls != null) 'image_urls': imageUrls,
      // Location goes in as a pair. Note the asymmetry: country uses `?`
      // because omitting it means "not editing location", but province is
      // guarded on COUNTRY and written even when null — `?province` would
      // skip the null and leave "Harare" sitting on a listing the seller
      // just moved to Kenya, the exact bad data the picker exists to stop.
      'country': ?country,
      if (country != null) 'province': province?.trim(),
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
  /// `status = 'available'`; flipping it to `'removed'` hides it from
  /// buyers (per the products_select_visible RLS policy) without
  /// deleting the product or its photos. The owner still sees the
  /// row in the seller dashboard and can flip it back.
  static Future<void> setProductAvailability({
    required String productId,
    required bool available,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to update your products.');
    }
    // The DB has only `status` (CHECK in 'available','sold','reserved',
    // 'removed') — no `is_available` column. 'removed' is what the
    // existing RLS treats as "hide from buyers, owner can still see"
    // (see products_select_visible policy), so it's the right state
    // for a paused listing the seller can flip back later.
    await _client
        .from(_productsTable)
        .update({
          'status': available ? 'available' : 'removed',
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

  // ────────────────────────────────────────────────────────────────
  // Super-admin operations (patch_031)
  // ────────────────────────────────────────────────────────────────

  /// True when the signed-in user has `profiles.is_super_admin = TRUE`.
  /// Used to gate the Seller Approvals entry in Settings + the route.
  /// Returns false on any error so a transient network blip never
  /// accidentally surfaces admin UI.
  static Future<bool> isCurrentUserSuperAdmin() async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    try {
      final row = await _client
          .from('profiles')
          .select('is_super_admin')
          .eq('id', user.id)
          .maybeSingle();
      return row?['is_super_admin'] == true;
    } catch (_) {
      return false;
    }
  }

  /// All pending seller rows — admin queue. Backed by the SECURITY
  /// DEFINER RPC `admin_pending_sellers` which itself re-checks the
  /// caller's super-admin flag.
  static Future<List<Seller>> fetchPendingSellers() async {
    final response = await _client.rpc('admin_pending_sellers');
    if (response is List) {
      return response
          .map((row) => Seller.fromJson(row as Map<String, dynamic>))
          .toList();
    }
    return const [];
  }

  /// Approve a pending seller. Flips status to approved + sends a
  /// notification to the seller. Caller must be a super admin.
  ///
  /// sellers.id is BIGINT, so we parse the stringified id back to an
  /// int before sending — passing the raw string makes PostgREST throw
  /// a cast error before the function body ever runs.
  static Future<Seller> approveSeller(String sellerId) async {
    final response = await _client.rpc(
      'admin_approve_seller',
      params: {'p_seller_id': int.parse(sellerId)},
    );
    final row = response is List
        ? response.first as Map<String, dynamic>
        : response as Map<String, dynamic>;
    return Seller.fromJson(row);
  }

  /// Reject a pending seller with an optional human-readable reason.
  /// The reason is surfaced back to the seller in the dashboard so
  /// they know what to fix before re-submitting.
  ///
  /// On a third-attempt rejection (current status `final_review_pending`)
  /// the RPC transitions to `rejected_final` — see patch_037. The
  /// returned Seller will reflect that state so the admin UI can move
  /// the row out of the queue immediately.
  static Future<Seller> rejectSeller(
    String sellerId, {
    String? reason,
  }) async {
    final response = await _client.rpc(
      'admin_reject_seller',
      params: {
        'p_seller_id': int.parse(sellerId),
        'p_reason': reason?.trim(),
      },
    );
    final row = response is List
        ? response.first as Map<String, dynamic>
        : response as Map<String, dynamic>;
    return Seller.fromJson(row);
  }

  /// Seller-side reapply (patch_037). Called after the rejected seller
  /// edits their store details — flips status back to `pending` (or
  /// `final_review_pending` on the third attempt), bumps the attempt
  /// counter, clears rejection_reason. The RPC validates that the row
  /// is owned by the caller and that status is `rejected`, so the Dart
  /// side just needs to surface the friendly error.
  static Future<Seller> reapplyAsSeller(String sellerId) async {
    final response = await _client.rpc(
      'seller_reapply',
      params: {'p_seller_id': int.parse(sellerId)},
    );
    final row = response is List
        ? response.first as Map<String, dynamic>
        : response as Map<String, dynamic>;
    return Seller.fromJson(row);
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
