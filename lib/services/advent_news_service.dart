import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/advent_news_model.dart';
import 'post_limit_error.dart';

/// Read-mostly service for the Advent News surface. Writes happen
/// via the dashboard / Edge Functions / admin pipelines; the app
/// only consumes. Auth is enforced server-side via patch_021 RLS.
class AdventNewsService {
  AdventNewsService._();

  static final SupabaseClient _client = Supabase.instance.client;
  static const _table = 'advent_news';
  static const _authorEmbed = 'profiles!advent_news_author_id_fkey(full_name)';

  /// Top news for the home hero card. Fetches a larger candidate
  /// pool (default 12) then shuffles with a per-user seed so each
  /// reader sees a different slice on home, but their own order is
  /// stable within a session. Pinned stories always rise to the top
  /// regardless of the shuffle so editorial overrides still work.
  static Future<List<AdventNews>> fetchTopNews({int limit = 5}) async {
    try {
      final response = await _client
          .from(_table)
          .select('*, $_authorEmbed')
          .order('is_pinned', ascending: false)
          .order('published_at', ascending: false)
          .limit(limit * 4);
      final all = (response as List)
          .map((row) => AdventNews.fromJson(row as Map<String, dynamic>))
          .toList();
      if (all.length <= limit) return all;
      final pinned = all.where((n) => n.isPinned).toList();
      final rest = all.where((n) => !n.isPinned).toList();
      final user = _client.auth.currentUser;
      final seed = user?.id.hashCode ?? 0;
      rest.shuffle(Random(seed));
      final mixed = <AdventNews>[
        ...pinned,
        ...rest,
      ].take(limit).toList();
      return mixed;
    } catch (_) {
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

  /// True when the current viewer can publish news. Open to every
  /// signed-in user as of patch_030 — authoring is no longer
  /// admin-gated. Returns false only when there is no session.
  static Future<bool> canPublish() async {
    return _client.auth.currentUser != null;
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
    final row = await PostLimitError.guard(
      PostSection.adventNews,
      () => _client
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
          .single(),
    );
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

  // ────────────────────────────────────────────────────────────────
  // Super-admin approval queue (patch_047). Backed by SECURITY DEFINER
  // RPCs gated on is_super_admin — same surface the web dashboard uses.
  // ────────────────────────────────────────────────────────────────

  /// Member-submitted news awaiting review.
  static Future<List<Map<String, dynamic>>> fetchPendingNews() async {
    final response = await _client.rpc('admin_list_pending_news');
    if (response is List) {
      return response
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
    }
    return const [];
  }

  /// Approve a pending news post — it goes live + the author is notified.
  static Future<void> approveNews(String id) async {
    await _client.rpc('admin_approve_news', params: {'p_id': int.parse(id)});
  }

  /// Reject a pending news post with an optional reason (shown to author).
  static Future<void> rejectNews(String id, {String? reason}) async {
    await _client.rpc(
      'admin_reject_news',
      params: {'p_id': int.parse(id), 'p_reason': reason?.trim()},
    );
  }
}
