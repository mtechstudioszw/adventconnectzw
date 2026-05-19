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

  /// Suggested members for the home-screen "People to meet" row.
  /// Surfaces opted-in directory entries first, then tops the row up
  /// with raw discoverable profiles so the section is never empty when
  /// the directory hasn't seen much opt-in traffic yet. Best-effort —
  /// returns an empty list on error.
  static Future<List<MemberDirectoryEntry>> fetchSuggestedMembers({
    int limit = 8,
  }) async {
    try {
      final user = _client.auth.currentUser;

      // 1) Opt-in directory entries (richer profile data).
      var dirQuery = _client
          .from(_table)
          .select('*, profiles(full_name, profile_photo_url), churches(name)')
          .eq('is_visible', true);
      if (user != null) {
        dirQuery = dirQuery.neq('user_id', user.id);
      }
      final dirResponse =
          await dirQuery.order('created_at', ascending: false).limit(limit);
      final dirEntries = (dirResponse as List)
          .map((row) =>
              MemberDirectoryEntry.fromJson(row as Map<String, dynamic>))
          .toList();

      if (dirEntries.length >= limit) return dirEntries;

      // 2) Top up with discoverable profiles that aren't already in the
      // directory result. Maps each profile into a MemberDirectoryEntry
      // shape so the UI doesn't need a second model.
      final coveredIds =
          dirEntries.map((e) => e.userId).toSet();

      var profilesQuery = _client
          .from('profiles')
          .select('id, full_name, profile_photo_url, province, city, bio')
          .eq('is_discoverable', true)
          .eq('is_banned', false);
      if (user != null) {
        profilesQuery = profilesQuery.neq('id', user.id);
      }
      final profilesResponse = await profilesQuery
          .order('created_at', ascending: false)
          .limit(limit * 3);
      final profileEntries = (profilesResponse as List)
          .map((row) => row as Map<String, dynamic>)
          .where((row) => !coveredIds.contains(row['id']?.toString()))
          .take(limit - dirEntries.length)
          .map((row) => MemberDirectoryEntry(
                // We don't have a directory row id, so reuse the user id.
                id: row['id'].toString(),
                userId: row['id'].toString(),
                isVisible: true,
                fullName: row['full_name'] as String?,
                profilePhotoUrl: row['profile_photo_url'] as String?,
                province: row['province'] as String?,
                city: row['city'] as String?,
                bio: row['bio'] as String?,
              ))
          .toList();

      return [...dirEntries, ...profileEntries];
    } catch (_) {
      return const [];
    }
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
