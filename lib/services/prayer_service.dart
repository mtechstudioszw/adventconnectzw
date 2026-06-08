import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/prayer_model.dart';
import 'analytics_service.dart';
import 'post_limit_error.dart';

class PrayerService {
  PrayerService._();

  static final SupabaseClient _client = Supabase.instance.client;

  // V4 schema:
  //   prayers              — base table; reads + writes go here
  //   prayer_responses     — both reactions (response_type='praying') and
  //                          comments (response_type='message')
  //   profiles             — joined to surface display names; the schema
  //                          intentionally has no denormalised name columns.
  //
  // Note: we keep `prayers_public` (a column-masking view) in the schema for
  // future server-trusted access paths, but the Flutter app reads from the
  // base table because PostgREST cannot resolve a foreign-key embed through
  // a view. Anonymous masking happens in `_hydratePrayer` below.
  static const _writeTable = 'prayers';
  static const _readTable = 'prayers';
  static const _responsesTable = 'prayer_responses';

  static const _authorEmbed =
      'author:author_id(full_name, profile_photo_url)';

  /// Optionally filter by [category] code ('healing', 'family',
  /// 'spiritual', 'provision', 'thanksgiving', 'ministry', 'other').
  /// Null = all categories. Drives the chip filter on prayer_screen.
  static Future<List<Prayer>> fetchPrayers({String? category}) async {
    var query = _client.from(_readTable).select('*, $_authorEmbed');
    if (category != null && category.isNotEmpty) {
      query = query.eq('category', category);
    }
    final response = await query
        .order('created_at', ascending: false)
        .limit(100);
    return (response as List)
        .map((row) => _hydratePrayer(row as Map<String, dynamic>))
        .toList();
  }

  static Future<Prayer?> fetchPrayerById(String id) async {
    final response = await _client
        .from(_readTable)
        .select('*, $_authorEmbed')
        .eq('id', id)
        .maybeSingle();
    if (response == null) return null;
    return _hydratePrayer(response);
  }

  static Future<Set<String>> fetchUserPrayedIds() async {
    final user = _client.auth.currentUser;
    if (user == null) return <String>{};
    final response = await _client
        .from(_responsesTable)
        .select('prayer_id')
        .eq('user_id', user.id)
        .eq('response_type', 'praying');
    return (response as List)
        .map((row) => row['prayer_id'].toString())
        .toSet();
  }

  static Future<bool> hasPrayed(String prayerId) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    final response = await _client
        .from(_responsesTable)
        .select('id')
        .eq('user_id', user.id)
        .eq('prayer_id', prayerId)
        .eq('response_type', 'praying')
        .maybeSingle();
    return response != null;
  }

  static Future<List<PrayingUser>> fetchPrayingUsers(String prayerId) async {
    final response = await _client
        .from(_responsesTable)
        .select('user_id, created_at, profiles:user_id(full_name)')
        .eq('prayer_id', prayerId)
        .eq('response_type', 'praying')
        .order('created_at', ascending: false)
        .limit(50);
    return (response as List).map((row) {
      final map = row as Map<String, dynamic>;
      final profile = map['profiles'] as Map<String, dynamic>?;
      final name = (profile?['full_name'] as String?)?.trim();
      return PrayingUser(
        userId: map['user_id']?.toString() ?? '',
        userName: name?.isNotEmpty == true ? name! : 'A friend',
      );
    }).toList();
  }

  /// Insert the "praying" reaction. Returns the authoritative
  /// post-insert prayer_count so the caller doesn't have to trust its
  /// own optimistic increment (which can drift when the DB trigger
  /// lags or a unique-violation re-tap is swallowed).
  static Future<int> pray(String prayerId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to pray with the community.');
    }
    try {
      await _client.from(_responsesTable).insert({
        'user_id': user.id,
        'prayer_id': prayerId,
        'response_type': 'praying',
      });
    } on PostgrestException catch (e) {
      // Already praying — unique constraint (prayer_id,user_id,
      // response_type). Treat as success so the caller's "isPraying"
      // state matches what the DB has, and re-read the canonical count.
      if (e.code != '23505') rethrow;
    }
    return _readPrayerCount(prayerId);
  }

  /// Delete the "praying" reaction. Returns the authoritative
  /// post-delete prayer_count.
  static Future<int> unpray(String prayerId) async {
    final user = _client.auth.currentUser;
    if (user == null) return 0;
    await _client
        .from(_responsesTable)
        .delete()
        .eq('user_id', user.id)
        .eq('prayer_id', prayerId)
        .eq('response_type', 'praying');
    return _readPrayerCount(prayerId);
  }

  static Future<int> _readPrayerCount(String prayerId) async {
    try {
      final row = await _client
          .from(_readTable)
          .select('prayer_count')
          .eq('id', prayerId)
          .maybeSingle();
      final raw = row?['prayer_count'];
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      return int.tryParse('$raw') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<Prayer> postPrayer(
    String content, {
    String visibility = 'public',
    bool isUrgent = false,
    String? title,
    String? churchId,
    String category = 'other',
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to share a prayer.');
    }
    // Insert and immediately read back the joined author name in a single
    // round-trip. Reading from the base `prayers` table here (not the view)
    // is fine — the author can always read their own row.
    final inserted = await PostLimitError.guard(
      PostSection.prayer,
      () => _client
          .from(_writeTable)
          .insert({
            'author_id': user.id,
            'content': content.trim(),
            'visibility': visibility,
            'is_urgent': isUrgent,
            'category': category,
            if (title != null && title.trim().isNotEmpty)
              'title': title.trim(),
            if (churchId != null) 'church_id': int.tryParse(churchId),
          })
          .select('*, author:author_id(full_name, profile_photo_url)')
          .single(),
    );
    AnalyticsService.prayerPosted(visibility: visibility);
    return _hydratePrayer(inserted);
  }

  /// Edit a prayer the current user posted. Server-side RLS enforces
  /// that author_id == auth.uid().
  static Future<void> updatePrayer({
    required String prayerId,
    required String content,
    String visibility = 'public',
    bool isUrgent = false,
    String? title,
    String? category,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to edit your prayer.');
    }
    await _client.from(_writeTable).update({
      'content': content.trim(),
      'visibility': visibility,
      'is_urgent': isUrgent,
      'title': title?.trim().isNotEmpty == true ? title!.trim() : null,
      // ignore: use_null_aware_elements
      if (category != null) 'category': category,
    }).eq('id', prayerId).eq('author_id', user.id);
  }

  static Future<List<PrayerComment>> fetchComments(String prayerId) async {
    final response = await _client
        .from(_responsesTable)
        .select('id, prayer_id, user_id, message, created_at, '
            'parent_response_id, '
            'profiles:user_id(full_name, profile_photo_url)')
        .eq('prayer_id', prayerId)
        .eq('response_type', 'message')
        .order('created_at', ascending: true)
        .limit(400);
    return (response as List).map((row) {
      final map = row as Map<String, dynamic>;
      final profile = map['profiles'] as Map<String, dynamic>?;
      final name = (profile?['full_name'] as String?)?.trim();
      return PrayerComment.fromJson({
        'id': map['id'],
        'prayer_id': map['prayer_id'],
        'author_id': map['user_id'],
        'author_name': name?.isNotEmpty == true ? name : 'A friend',
        'author_photo_url': profile?['profile_photo_url'],
        'content': map['message'] ?? '',
        'created_at': map['created_at'],
        'parent_comment_id': map['parent_response_id'],
      });
    }).toList();
  }

  static Future<PrayerComment> postComment(
    String prayerId,
    String content, {
    String? parentCommentId,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to comment.');
    }
    final payload = <String, dynamic>{
      'prayer_id': prayerId,
      'user_id': user.id,
      'response_type': 'message',
      'message': content.trim(),
    };
    if (parentCommentId != null && parentCommentId.isNotEmpty) {
      payload['parent_response_id'] =
          int.tryParse(parentCommentId) ?? parentCommentId;
    }
    try {
      await _client.from(_responsesTable).insert(payload);
    } catch (_) {
      // Older deployments without patch_035 don't have the
      // parent_response_id column — retry without it so the comment
      // still posts (as top-level).
      payload.remove('parent_response_id');
      await _client.from(_responsesTable).insert(payload);
    }

    // Refresh the comment list so the caller sees its newest row.
    final comments = await fetchComments(prayerId);
    return comments.last;
  }

  /// Delete a prayer comment (a `message` response). RLS (patch_044)
  /// allows this when the caller wrote it OR owns the prayer, so the
  /// one call covers "delete my comment" and "remove a comment from
  /// my prayer". No-op server-side if neither applies.
  static Future<void> deletePrayerComment(String responseId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to delete comments.');
    }
    await _client
        .from(_responsesTable)
        .delete()
        .eq('id', int.tryParse(responseId) ?? responseId);
  }

  static Prayer _hydratePrayer(Map<String, dynamic> row) {
    // Mask the author for anonymous prayers in code, since we read from the
    // base table now. The author can still see their own row's author_id —
    // that's fine because the UI only shows their name to themselves.
    final isAnonymous = (row['visibility'] as String?) == 'anonymous';
    final author = row['author'] as Map<String, dynamic>?;
    final name = (author?['full_name'] as String?)?.trim();
    final photo = (author?['profile_photo_url'] as String?)?.trim();
    final masked = <String, dynamic>{
      ...row,
      if (isAnonymous) 'author_id': null,
      'author_name':
          isAnonymous ? 'Anonymous' : (name?.isNotEmpty == true ? name : 'A friend'),
      // Strip the photo for anonymous posts — the whole point is the
      // poster isn't identifiable. Otherwise pass it through so the
      // prayer card can render a real avatar instead of initials.
      'author_photo_url':
          isAnonymous ? null : (photo?.isNotEmpty == true ? photo : null),
    };
    return Prayer.fromJson(masked);
  }

  /// Delete a prayer the current user posted. RLS on `prayers` already
  /// restricts DELETE to the author (`author_id = auth.uid()`), but
  /// we also pass the predicate explicitly so a transient role issue
  /// never silently affects another user's row.
  static Future<void> deletePrayer(String prayerId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to delete your prayer.');
    }
    await _client
        .from(_writeTable)
        .delete()
        .eq('id', prayerId)
        .eq('author_id', user.id);
  }
}

class PrayingUser {
  const PrayingUser({required this.userId, required this.userName});
  final String userId;
  final String userName;
}
