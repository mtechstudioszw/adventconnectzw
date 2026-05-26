import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/advent_news_model.dart';

/// Read-mostly service for the Advent News surface. Writes happen
/// via the dashboard / Edge Functions / admin pipelines; the app
/// only consumes. Auth is enforced server-side via patch_021 RLS.
class AdventNewsService {
  AdventNewsService._();

  static final SupabaseClient _client = Supabase.instance.client;
  static const _table = 'advent_news';
  static const _authorEmbed = 'profiles!advent_news_author_id_fkey(full_name)';

  /// Top news for the home hero card — pinned first, then newest.
  /// Limit is small (3-5) so the cold-start payload stays light.
  static Future<List<AdventNews>> fetchTopNews({int limit = 5}) async {
    try {
      final response = await _client
          .from(_table)
          .select('*, $_authorEmbed')
          .order('is_pinned', ascending: false)
          .order('published_at', ascending: false)
          .limit(limit);
      return (response as List)
          .map((row) => AdventNews.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Empty list rather than throwing — a missing news table or
      // RLS hiccup shouldn't break the home screen.
      return const [];
    }
  }

  /// Full news feed for the dedicated /news screen. Filter by
  /// [category] code or pass null for "All".
  static Future<List<AdventNews>> fetchNews({
    NewsCategory? category,
    int limit = 50,
  }) async {
    try {
      var query = _client.from(_table).select('*, $_authorEmbed');
      if (category != null) {
        query = query.eq('category', category.code);
      }
      final response = await query
          .order('is_pinned', ascending: false)
          .order('published_at', ascending: false)
          .limit(limit);
      return (response as List)
          .map((row) => AdventNews.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Fetch a single news article by id — used by the details
  /// screen when arriving via a deep link / push notification.
  static Future<AdventNews?> fetchNewsById(String id) async {
    try {
      final response = await _client
          .from(_table)
          .select('*, $_authorEmbed')
          .eq('id', id)
          .maybeSingle();
      if (response == null) return null;
      return AdventNews.fromJson(response);
    } catch (_) {
      return null;
    }
  }
}
