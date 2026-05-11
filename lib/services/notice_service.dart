import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/notice_model.dart';

/// Reads/writes for community notices (Table 27).
class NoticeService {
  NoticeService._();

  static final SupabaseClient _client = Supabase.instance.client;
  static const _table = 'notices';

  static Future<List<Notice>> fetchRecent({String? category}) async {
    var query = _client
        .from(_table)
        .select('*, profiles(full_name)');
    if (category != null && category.isNotEmpty && category != 'all') {
      query = query.eq('category', category);
    }
    final response =
        await query.order('created_at', ascending: false).limit(100);
    return (response as List)
        .map((row) => Notice.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  static Future<Notice> post({
    required String title,
    required String body,
    required String category,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to post a notice.');
    }
    final inserted = await _client
        .from(_table)
        .insert({
          'posted_by': user.id,
          'title': title.trim(),
          'body': body.trim(),
          'category': category,
        })
        .select('*, profiles(full_name)')
        .single();
    return Notice.fromJson(inserted);
  }
}
