import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/org_page_model.dart';
import '../models/post_model.dart';
import '../utils/postgrest_filter.dart';
import '../utils/require_changed.dart';
import 'feed_service.dart';
import 'content_filter_error.dart';

/// Organization Pages (patch_275): directory, create/edit, follow, admins,
/// and posting as a Page.
///
/// Every rule that matters — who may edit, who may post as the Page, the
/// 3-Page limit, verification — is enforced by the database. This class
/// only asks.
class PageService {
  PageService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static const _cols =
      'id, name, category, description, logo_url, cover_url, city, country, '
      'service_area, contact_email, contact_phone, website, is_verified, '
      'status, moderation_reason, created_at';

  /// False once the `pages` table turns out not to exist (patch_275 not
  /// run). Screens then say so instead of showing an empty directory.
  static bool available = true;

  /// Bumped after a create/edit/delete/follow so lists refresh.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static bool _missing(Object e) {
    final s = e.toString();
    return s.contains('PGRST205') ||
        s.contains('PGRST202') ||
        s.contains('42P01') ||
        s.contains("relation \"public.pages\"") ||
        s.contains("table 'public.pages'") ||
        s.contains('page_stats') ||
        s.contains('list_page_admins');
  }

  static Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      final r = await run();
      available = true;
      return r;
    } catch (e) {
      if (_missing(e)) available = false;
      rethrow;
    }
  }

  /// The directory: active Pages, optionally one category and/or a name
  /// search, verified first, then newest.
  static Future<List<OrgPage>> directory({
    PageCategory? category,
    String? query,
    int limit = 60,
  }) => _guard(() async {
    var q = _client.from('pages').select(_cols).eq('status', 'active');
    if (category != null) q = q.eq('category', category.wire);
    final term = (query ?? '').trim();
    if (term.isNotEmpty) {
      q = q.or(
        'name.ilike.${orFilterValue('%$term%')},'
        'city.ilike.${orFilterValue('%$term%')}',
      );
    }
    final rows = await q
        .order('is_verified', ascending: false)
        .order('created_at', ascending: false)
        .limit(limit);
    return [
      for (final r in rows as List) OrgPage.fromJson(r as Map<String, dynamic>),
    ];
  });

  static Future<OrgPage?> fetch(String id) => _guard(() async {
    final rows = await _client
        .from('pages')
        .select(_cols)
        .eq('id', id)
        .limit(1);
    final list = rows as List;
    return list.isEmpty
        ? null
        : OrgPage.fromJson(list.first as Map<String, dynamic>);
  });

  /// Pages the viewer owns or edits, including hidden ones.
  static Future<List<OrgPage>> mine() => _guard(() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return const <OrgPage>[];
    final rows = await _client
        .from('page_admins')
        .select('role, pages($_cols)')
        .eq('user_id', me);
    return [
      for (final r in rows as List)
        if ((r as Map)['pages'] is Map<String, dynamic>)
          OrgPage.fromJson(r['pages'] as Map<String, dynamic>),
    ];
  });

  static Future<PageStats> stats(String id) => _guard(() async {
    final res = await _client.rpc('page_stats', params: {'p_page': id});
    final row = res is List
        ? (res.isEmpty ? null : res.first as Map<String, dynamic>)
        : res as Map<String, dynamic>?;
    if (row == null) return PageStats.empty;
    return PageStats(
      followers: (row['followers'] as num?)?.toInt() ?? 0,
      iFollow: row['i_follow'] == true,
      myRole: row['my_role'] as String?,
    );
  });

  static Future<OrgPage> create(OrgPage draft) => _guard(() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) throw const AuthException('Sign in to create a Page.');
    final row = await _client
        .from('pages')
        .insert({...draft.toWrite(), 'created_by': me})
        .select(_cols)
        .single();
    revision.value++;
    return OrgPage.fromJson(row);
  });

  static Future<OrgPage> update(OrgPage page) => _guard(() async {
    final rows = await _client
        .from('pages')
        .update(page.toWrite())
        .eq('id', page.id)
        .select(_cols);
    requireChanged(rows, 'Page');
    revision.value++;
    return OrgPage.fromJson((rows as List).first as Map<String, dynamic>);
  });

  static Future<void> delete(String id) => _guard(() async {
    final rows = await _client.from('pages').delete().eq('id', id).select('id');
    requireChanged(rows, 'Page');
    revision.value++;
  });

  /// Pages the viewer follows — the Home feed ranks their updates higher.
  /// Never throws: an empty set just means no boost.
  static Future<Set<String>> myFollowedPageIds() async {
    try {
      final me = _client.auth.currentUser?.id;
      if (me == null) return const <String>{};
      final rows = await _client
          .from('page_follows')
          .select('page_id')
          .eq('user_id', me);
      return {for (final r in rows as List) (r as Map)['page_id'].toString()};
    } catch (_) {
      return const <String>{};
    }
  }

  static Future<void> follow(String id) => _guard(() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) throw const AuthException('Sign in to follow Pages.');
    await _client.from('page_follows').insert({'page_id': id, 'user_id': me});
    revision.value++;
  });

  static Future<void> unfollow(String id) => _guard(() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return;
    await _client
        .from('page_follows')
        .delete()
        .eq('page_id', id)
        .eq('user_id', me);
    revision.value++;
  });

  static Future<List<PageAdmin>> admins(String id) => _guard(() async {
    final rows = await _client.rpc('list_page_admins', params: {'p_page': id});
    return [
      for (final r in rows as List)
        PageAdmin.fromJson(r as Map<String, dynamic>),
    ];
  });

  static Future<void> addAdmin(
    String id,
    String username, {
    String role = 'editor',
  }) => _guard(
    () => _client.rpc(
      'add_page_admin',
      params: {'p_page': id, 'p_username': username, 'p_role': role},
    ),
  );

  static Future<void> removeAdmin(String id, String userId) => _guard(
    () => _client.rpc(
      'remove_page_admin',
      params: {'p_page': id, 'p_user': userId},
    ),
  );

  /// Super admin only (the RPC refuses anyone else).
  static Future<void> adminSetState(
    String id, {
    required bool verified,
    required bool hidden,
    String? reason,
  }) async {
    await _client.rpc(
      'admin_set_page_state',
      params: {
        'p_page': id,
        'p_verified': verified,
        'p_hidden': hidden,
        'p_reason': reason,
      },
    );
    revision.value++;
  }

  /// The Page's posts, newest first.
  static Future<List<Post>> posts(String id, {int limit = 50}) =>
      _guard(() => FeedService.fetchPagePosts(id, limit: limit));

  /// A friendly sentence for a server refusal, or null to use the caller's.
  static String? messageFor(Object e) {
    final s = e.toString();
    if (ContentFilterError.matches(e)) return ContentFilterError.message;
    if (s.contains('PAGE_LIMIT')) return 'You can create up to 3 Pages.';
    if (s.contains('NO_SUCH_USER')) return 'No member has that username.';
    if (s.contains('LAST_OWNER')) {
      return 'A Page needs at least one owner. Add another owner first.';
    }
    if (s.contains('pages_contact_email_check')) {
      return 'That email address does not look right.';
    }
    if (s.contains('pages_contact_phone_check')) {
      return 'That phone number does not look right.';
    }
    if (s.contains('pages_website_check')) {
      return 'Enter a web address like example.org';
    }
    if (!available) {
      return 'Pages need a database update (patch_275) before they can be '
          'used.';
    }
    return null;
  }
}
