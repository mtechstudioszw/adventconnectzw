import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/member_directory_model.dart';

/// Reads/writes for the opt-in public member directory (Table 21).
class DirectoryService {
  DirectoryService._();

  static final SupabaseClient _client = Supabase.instance.client;
  static const _table = 'member_directory';

  /// Fetch every visible entry, optionally filtered by free-text search
  /// (profession / skills / city) and province.
  static Future<List<MemberDirectoryEntry>> fetchEntries({
    String? search,
    String? province,
  }) async {
    var query = _client
        .from(_table)
        .select('*, profiles(full_name, profile_photo_url), churches(name)')
        .eq('is_visible', true);

    if (province != null && province.isNotEmpty) {
      query = query.eq('province', province);
    }

    if (search != null && search.trim().isNotEmpty) {
      final term = '%${search.trim()}%';
      query = query.or(
        'profession.ilike.$term,skills.ilike.$term,city.ilike.$term,bio.ilike.$term',
      );
    }

    final response =
        await query.order('created_at', ascending: false).limit(200);
    return (response as List)
        .map((row) =>
            MemberDirectoryEntry.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Returns the current user's directory entry, or null if they
  /// haven't opted in yet.
  static Future<MemberDirectoryEntry?> fetchMyEntry() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final row = await _client
        .from(_table)
        .select('*, churches(name)')
        .eq('user_id', user.id)
        .maybeSingle();
    if (row == null) return null;
    return MemberDirectoryEntry.fromJson(row);
  }

  /// Upsert the current user's directory entry. Passing `isVisible:
  /// false` hides the row but keeps the fields so the user can flip
  /// the toggle back on later without re-typing.
  static Future<MemberDirectoryEntry> upsertMyEntry({
    String? profession,
    String? skills,
    String? churchId,
    String? province,
    String? city,
    String? bio,
    bool isVisible = true,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to update the directory.');
    }
    final payload = <String, dynamic>{
      'user_id': user.id,
      'profession': ?profession?.trim(),
      'skills': ?skills?.trim(),
      'church_id': ?churchId,
      'province': ?province,
      'city': ?city?.trim(),
      'bio': ?bio?.trim(),
      'is_visible': isVisible,
    };
    final upserted = await _client
        .from(_table)
        .upsert(payload, onConflict: 'user_id')
        .select('*, churches(name)')
        .single();
    return MemberDirectoryEntry.fromJson(upserted);
  }
}
