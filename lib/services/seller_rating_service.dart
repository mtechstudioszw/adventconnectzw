import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps `seller_ratings` (V4 Table 12, added in patch_002).
///
/// Rating rows are unique on (seller_id, rated_by) — a buyer can only
/// post one review per seller, but they can update or delete their own.
/// A DB trigger keeps `sellers.rating` and `sellers.rating_count`
/// in sync automatically.
class SellerRatingService {
  SellerRatingService._();

  static final SupabaseClient _client = Supabase.instance.client;
  static const _table = 'seller_ratings';

  /// Recent reviews for a storefront. `seller_id` here is the BIGSERIAL
  /// id from `sellers.id` (not the seller's auth user id).
  static Future<List<SellerRating>> fetchForSeller(
    String sellerId, {
    int limit = 20,
  }) async {
    if (sellerId.isEmpty) return const [];
    final response = await _client
        .from(_table)
        .select()
        .eq('seller_id', sellerId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (response as List)
        .map((row) => SellerRating.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// The signed-in user's existing rating for this seller, if any.
  /// Used by the composer to show "Update your review" instead of "Rate".
  static Future<SellerRating?> fetchMine(String sellerId) async {
    final user = _client.auth.currentUser;
    if (user == null || sellerId.isEmpty) return null;
    final row = await _client
        .from(_table)
        .select()
        .eq('seller_id', sellerId)
        .eq('rated_by', user.id)
        .maybeSingle();
    if (row == null) return null;
    return SellerRating.fromJson(row);
  }

  /// Upsert the current user's rating. The unique constraint on
  /// (seller_id, rated_by) means this safely handles "rate then change
  /// your mind".
  static Future<SellerRating> rate({
    required String sellerId,
    required int rating,
    String? review,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to leave a review.');
    }
    if (rating < 1 || rating > 5) {
      throw ArgumentError('Rating must be between 1 and 5.');
    }
    final response = await _client
        .from(_table)
        .upsert({
          'seller_id': sellerId,
          'rated_by': user.id,
          'rating': rating,
          'review': review?.trim().isEmpty == true ? null : review?.trim(),
        }, onConflict: 'seller_id,rated_by')
        .select()
        .single();
    return SellerRating.fromJson(response);
  }

  /// Remove the current user's review. Trigger recomputes the seller's
  /// rolling average.
  static Future<void> deleteMine(String sellerId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from(_table)
        .delete()
        .eq('seller_id', sellerId)
        .eq('rated_by', user.id);
  }
}

class SellerRating {
  const SellerRating({
    required this.id,
    required this.sellerId,
    required this.ratedBy,
    required this.rating,
    required this.createdAt,
    this.review,
  });

  final String id;
  final String sellerId;
  final String ratedBy;
  final int rating;
  final String? review;
  final DateTime createdAt;

  factory SellerRating.fromJson(Map<String, dynamic> json) {
    return SellerRating(
      id: json['id'].toString(),
      sellerId: json['seller_id'].toString(),
      ratedBy: (json['rated_by'] ?? '').toString(),
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      review: (json['review'] as String?)?.trim().isEmpty == true
          ? null
          : json['review'] as String?,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
