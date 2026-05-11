import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps `urgent_banners` (V4 Table 24, added in patch_002).
///
/// Banners are conference- or nationwide-level alerts surfaced on the
/// home screen. Only super-admin / conference-admin users post — the
/// app is read-only here.
class UrgentBannerService {
  UrgentBannerService._();

  static final SupabaseClient _client = Supabase.instance.client;
  static const _table = 'urgent_banners';

  /// Latest active banner that hasn't expired yet, or null.
  /// We surface a single banner at a time on home — if multiple are
  /// active the most recently posted wins.
  static Future<UrgentBanner?> fetchActive() async {
    try {
      final response = await _client
          .from(_table)
          .select()
          .eq('is_active', true)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (response == null) return null;
      return UrgentBanner.fromJson(response);
    } catch (_) {
      // Banners are non-essential; never bubble up the error to home.
      return null;
    }
  }
}

class UrgentBanner {
  const UrgentBanner({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.expiresAt,
    this.conference,
  });

  final String id;
  final String title;
  final String body;
  final String? conference;
  final DateTime createdAt;
  final DateTime expiresAt;

  factory UrgentBanner.fromJson(Map<String, dynamic> json) {
    return UrgentBanner(
      id: json['id'].toString(),
      title: (json['title'] ?? '') as String,
      body: (json['body'] ?? '') as String,
      conference: json['conference'] as String?,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? '') ??
          DateTime.now().add(const Duration(hours: 48)),
    );
  }
}
