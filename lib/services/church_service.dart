import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/church_model.dart';

class ChurchService {
  ChurchService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static const _table = 'churches';
  static const _followsTable = 'church_followers';

  static Future<List<Church>> fetchChurches({
    String? search,
    String? city,
  }) async {
    var query = _client.from(_table).select();

    if (city != null && city.isNotEmpty) {
      query = query.eq('city', city);
    }

    if (search != null && search.trim().isNotEmpty) {
      final term = '%${search.trim()}%';
      query = query.or('name.ilike.$term,city.ilike.$term');
    }

    final response = await query
        .order('members_count', ascending: false)
        .limit(100);

    return (response as List)
        .map((row) => Church.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  static Future<Church?> fetchChurchById(String id) async {
    final response = await _client
        .from(_table)
        .select()
        .eq('id', id)
        .maybeSingle();
    if (response == null) return null;
    return Church.fromJson(response);
  }

  static Future<List<String>> fetchAvailableCities() async {
    final response = await _client
        .from(_table)
        .select('city')
        .order('city');
    final cities = (response as List)
        .map((row) => (row['city'] ?? '').toString())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return cities;
  }

  static Future<bool> isFollowing(String churchId) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    final response = await _client
        .from(_followsTable)
        .select('church_id')
        .eq('user_id', user.id)
        .eq('church_id', churchId)
        .maybeSingle();
    return response != null;
  }

  static Future<void> follow(String churchId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('You must be signed in to follow a church.');
    }
    await _client.from(_followsTable).insert({
      'user_id': user.id,
      'church_id': churchId,
    });
  }

  static Future<void> unfollow(String churchId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from(_followsTable)
        .delete()
        .eq('user_id', user.id)
        .eq('church_id', churchId);
  }
}
