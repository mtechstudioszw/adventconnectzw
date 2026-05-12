import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/prayer_model.dart';
import 'analytics_service.dart';

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

  static const _authorEmbed = 'author:author_id(full_name)';

  static Future<List<Prayer>> fetchPrayers() async {
    final response = await _client
        .from(_readTable)
        .select('*, $_authorEmbed')
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

  static Future<void> pray(String prayerId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to pray with the community.');
    }
    await _client.from(_responsesTable).insert({
      'user_id': user.id,
      'prayer_id': prayerId,
      'response_type': 'praying',
    });
  }

  static Future<void> unpray(String prayerId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from(_responsesTable)
        .delete()
        .eq('user_id', user.id)
        .eq('prayer_id', prayerId)
        .eq('response_type', 'praying');
  }

  static Future<Prayer> postPrayer(
    String content, {
    String visibility = 'public',
    bool isUrgent = false,
    String? title,
    String? churchId,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to share a prayer.');
    }
    // Insert and immediately read back the joined author name in a single
    // round-trip. Reading from the base `prayers` table here (not the view)
    // is fine — the author can always read their own row.
    final inserted = await _client
        .from(_writeTable)
        .insert({
          'author_id': user.id,
          'content': content.trim(),
          'visibility': visibility,
          'is_urgent': isUrgent,
          if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
          if (churchId != null) 'church_id': int.tryParse(churchId),
        })
        .select('*, author:author_id(full_name)')
        .single();
    AnalyticsService.prayerPosted(visibility: visibility);
    return _hydratePrayer(inserted);
  }

  static Future<List<PrayerComment>> fetchComments(String prayerId) async {
    final response = await _client
        .from(_responsesTable)
        .select('id, prayer_id, user_id, message, created_at, '
            'profiles:user_id(full_name)')
        .eq('prayer_id', prayerId)
        .eq('response_type', 'message')
        .order('created_at', ascending: true)
        .limit(200);
    return (response as List).map((row) {
      final map = row as Map<String, dynamic>;
      final profile = map['profiles'] as Map<String, dynamic>?;
      final name = (profile?['full_name'] as String?)?.trim();
      return PrayerComment.fromJson({
        'id': map['id'],
        'prayer_id': map['prayer_id'],
        'author_id': map['user_id'],
        'author_name': name?.isNotEmpty == true ? name : 'A friend',
        'content': map['message'] ?? '',
        'created_at': map['created_at'],
      });
    }).toList();
  }

  static Future<PrayerComment> postComment(
    String prayerId,
    String content,
  ) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to comment.');
    }
    await _client.from(_responsesTable).insert({
      'prayer_id': prayerId,
      'user_id': user.id,
      'response_type': 'message',
      'message': content.trim(),
    });

    // Refresh the comment list so the caller sees its newest row.
    final comments = await fetchComments(prayerId);
    return comments.last;
  }

  static Prayer _hydratePrayer(Map<String, dynamic> row) {
    // Mask the author for anonymous prayers in code, since we read from the
    // base table now. The author can still see their own row's author_id —
    // that's fine because the UI only shows their name to themselves.
    final isAnonymous = (row['visibility'] as String?) == 'anonymous';
    final author = row['author'] as Map<String, dynamic>?;
    final name = (author?['full_name'] as String?)?.trim();
    final masked = <String, dynamic>{
      ...row,
      if (isAnonymous) 'author_id': null,
      'author_name':
          isAnonymous ? 'Anonymous' : (name?.isNotEmpty == true ? name : 'A friend'),
    };
    return Prayer.fromJson(masked);
  }
}

class PrayingUser {
  const PrayingUser({required this.userId, required this.userName});
  final String userId;
  final String userName;
}
