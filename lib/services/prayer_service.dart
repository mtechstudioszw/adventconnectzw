import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/prayer_model.dart';

class PrayerService {
  PrayerService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static const _table = 'prayers';
  static const _responsesTable = 'prayer_responses';
  static const _commentsTable = 'prayer_comments';

  static Future<List<Prayer>> fetchPrayers() async {
    final response = await _client
        .from(_table)
        .select()
        .order('created_at', ascending: false)
        .limit(100);
    return (response as List)
        .map((row) => Prayer.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  static Future<Prayer?> fetchPrayerById(String id) async {
    final response =
        await _client.from(_table).select().eq('id', id).maybeSingle();
    if (response == null) return null;
    return Prayer.fromJson(response);
  }

  static Future<Set<String>> fetchUserPrayedIds() async {
    final user = _client.auth.currentUser;
    if (user == null) return <String>{};
    final response = await _client
        .from(_responsesTable)
        .select('prayer_id')
        .eq('user_id', user.id);
    return (response as List)
        .map((row) => row['prayer_id'].toString())
        .toSet();
  }

  static Future<bool> hasPrayed(String prayerId) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    final response = await _client
        .from(_responsesTable)
        .select('prayer_id')
        .eq('user_id', user.id)
        .eq('prayer_id', prayerId)
        .maybeSingle();
    return response != null;
  }

  static Future<List<PrayingUser>> fetchPrayingUsers(String prayerId) async {
    final response = await _client
        .from(_responsesTable)
        .select('user_id, user_name, created_at')
        .eq('prayer_id', prayerId)
        .order('created_at', ascending: false)
        .limit(50);
    return (response as List)
        .map((row) => PrayingUser(
              userId: row['user_id']?.toString() ?? '',
              userName: (row['user_name'] ?? 'A friend').toString(),
            ))
        .toList();
  }

  static Future<void> pray(String prayerId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to pray with the community.');
    }
    final meta = user.userMetadata ?? const {};
    final userName = (meta['full_name'] as String?)?.trim();
    await _client.from(_responsesTable).insert({
      'user_id': user.id,
      'prayer_id': prayerId,
      'user_name': userName?.isNotEmpty == true ? userName : 'A friend',
    });
  }

  static Future<void> unpray(String prayerId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from(_responsesTable)
        .delete()
        .eq('user_id', user.id)
        .eq('prayer_id', prayerId);
  }

  static Future<Prayer> postPrayer(String content) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to share a prayer.');
    }
    final meta = user.userMetadata ?? const {};
    final authorName = (meta['full_name'] as String?)?.trim();
    final response = await _client
        .from(_table)
        .insert({
          'author_id': user.id,
          'author_name': authorName?.isNotEmpty == true ? authorName : 'A friend',
          'content': content.trim(),
          'prayer_count': 0,
          'comment_count': 0,
        })
        .select()
        .single();
    return Prayer.fromJson(response);
  }

  static Future<List<PrayerComment>> fetchComments(String prayerId) async {
    final response = await _client
        .from(_commentsTable)
        .select()
        .eq('prayer_id', prayerId)
        .order('created_at', ascending: true)
        .limit(200);
    return (response as List)
        .map((row) => PrayerComment.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  static Future<PrayerComment> postComment(
    String prayerId,
    String content,
  ) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to comment.');
    }
    final meta = user.userMetadata ?? const {};
    final authorName = (meta['full_name'] as String?)?.trim();
    final response = await _client
        .from(_commentsTable)
        .insert({
          'prayer_id': prayerId,
          'author_id': user.id,
          'author_name': authorName?.isNotEmpty == true ? authorName : 'A friend',
          'content': content.trim(),
        })
        .select()
        .single();
    return PrayerComment.fromJson(response);
  }
}

class PrayingUser {
  const PrayingUser({required this.userId, required this.userName});
  final String userId;
  final String userName;
}
