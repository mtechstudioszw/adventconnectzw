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

  /// True when the current viewer is allowed to publish news in-app —
  /// gates the "Post news" entry button. The check mirrors the RLS
  /// policy: super admin OR approved church admin.
  static Future<bool> canPublish() async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    try {
      final profile = await _client
          .from('profiles')
          .select('is_super_admin')
          .eq('id', user.id)
          .maybeSingle();
      if (profile?['is_super_admin'] == true) return true;
    } catch (_) {
      // Fall through and try church_admins.
    }
    try {
      final adminRow = await _client
          .from('church_admins')
          .select('id')
          .eq('user_id', user.id)
          .eq('status', 'approved')
          .limit(1);
      return (adminRow as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Publish a new Advent News story. Server-side RLS rejects this
  /// for anyone who isn't a super admin or approved church admin,
  /// so we don't need a client-side gate beyond [canPublish] for
  /// the UI affordance.
  static Future<AdventNews> postNews({
    required String title,
    required String summary,
    String? body,
    String? coverPhotoUrl,
    NewsCategory category = NewsCategory.general,
    String? sourceUrl,
    String? sourceLabel,
    bool isPinned = false,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to publish news.');
    }
    final row = await _client
        .from(_table)
        .insert({
          'title': title.trim(),
          'summary': summary.trim(),
          'body': body?.trim().isNotEmpty == true ? body!.trim() : null,
          'cover_photo_url': coverPhotoUrl?.trim(),
          'category': category.code,
          'source_url': sourceUrl?.trim().isNotEmpty == true
              ? sourceUrl!.trim()
              : null,
          'source_label': sourceLabel?.trim().isNotEmpty == true
              ? sourceLabel!.trim()
              : null,
          'is_pinned': isPinned,
          'author_id': user.id,
          'published_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select('*, $_authorEmbed')
        .single();
    return AdventNews.fromJson(row);
  }

  /// Toggle the pinned state of an existing news article. Reserved
  /// for the same admins that can publish.
  static Future<void> setPinned(String id, bool isPinned) async {
    await _client
        .from(_table)
        .update({'is_pinned': isPinned})
        .eq('id', id);
  }

  /// Update an existing news article. RLS restricts this to the
  /// author or a super admin, so the client gate is just a UX
  /// affordance — the database is authoritative.
  static Future<AdventNews> updateNews({
    required String id,
    required String title,
    required String summary,
    String? body,
    String? coverPhotoUrl,
    NewsCategory category = NewsCategory.general,
    String? sourceUrl,
    String? sourceLabel,
  }) async {
    final row = await _client
        .from(_table)
        .update({
          'title': title.trim(),
          'summary': summary.trim(),
          'body': body?.trim().isNotEmpty == true ? body!.trim() : null,
          'cover_photo_url': coverPhotoUrl?.trim(),
          'category': category.code,
          'source_url': sourceUrl?.trim().isNotEmpty == true
              ? sourceUrl!.trim()
              : null,
          'source_label': sourceLabel?.trim().isNotEmpty == true
              ? sourceLabel!.trim()
              : null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .select('*, $_authorEmbed')
        .single();
    return AdventNews.fromJson(row);
  }

  /// Delete a news article. RLS gates this to the author or a super
  /// admin so accidental deletes by other admins are blocked.
  static Future<void> deleteNews(String id) async {
    await _client.from(_table).delete().eq('id', id);
  }
}
