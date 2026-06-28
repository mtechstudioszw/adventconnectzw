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
    // Show the directory A→Z (per request). The name is joined from
    // profiles, which can't be ordered at the DB level here, so sort the
    // fetched page client-side.
    return (response as List)
        .map((row) =>
            MemberDirectoryEntry.fromJson(row as Map<String, dynamic>))
        .toList()
      ..sort(_byNameCi);
  }

  /// The signed-in user's accepted friends as directory entries (via the
  /// SECURITY DEFINER `my_friends` RPC, so friends show with their real
  /// name/photo even when their profile isn't publicly discoverable).
  /// Powers the friends-only "New chat" and group member pickers.
  static Future<List<MemberDirectoryEntry>> fetchFriends() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    final rows = await _client.rpc('my_friends');
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      final id = (m['friend_id'] ?? '').toString();
      return MemberDirectoryEntry(
        id: id,
        userId: id,
        isVisible: true,
        fullName: m['full_name'] as String?,
        profilePhotoUrl: m['profile_photo_url'] as String?,
        churchName: m['church_name'] as String?,
      );
    }).toList();
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
      // Alphabetical, not newest-first — the suggestion row reads like a
      // mini directory, so users expect A→Z (per request) rather than
      // "whoever signed up most recently".
      final profilesResponse = await profilesQuery
          .order('full_name', ascending: true)
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

      // Final list shown alphabetically (case-insensitive). The directory
      // query can't be ordered by the joined profiles.full_name at the DB
      // level, so we sort the merged result here to guarantee A→Z.
      return [...dirEntries, ...profileEntries]..sort(_byNameCi);
    } catch (_) {
      return const [];
    }
  }

  /// Every discoverable member on Advent, A→Z. RLS already restricts the
  /// `profiles` table to discoverable (or self) rows, so this returns exactly
  /// the people who can be messaged. The caller filters out existing friends
  /// + self. Used by New chat → "Find people" so the user can browse EVERYONE
  /// who isn't already a friend, alphabetically (not just a few suggestions).
  static Future<List<MemberDirectoryEntry>> fetchAllDiscoverableProfiles({
    int limit = 500,
  }) async {
    final user = _client.auth.currentUser;
    try {
      var q = _client
          .from('profiles')
          .select('id, full_name, profile_photo_url, province, city, bio')
          .eq('is_discoverable', true)
          .eq('is_banned', false);
      if (user != null) q = q.neq('id', user.id);
      final response =
          await q.order('full_name', ascending: true).limit(limit);
      return (response as List)
          .map((row) => row as Map<String, dynamic>)
          .map((row) => MemberDirectoryEntry(
                id: row['id'].toString(),
                userId: row['id'].toString(),
                isVisible: true,
                fullName: row['full_name'] as String?,
                profilePhotoUrl: row['profile_photo_url'] as String?,
                province: row['province'] as String?,
                city: row['city'] as String?,
                bio: row['bio'] as String?,
              ))
          .toList()
        ..sort(_byNameCi);
    } catch (_) {
      return const [];
    }
  }

  /// Case-insensitive A→Z comparator on full name; blank names sort last.
  static int _byNameCi(MemberDirectoryEntry a, MemberDirectoryEntry b) {
    final an = (a.fullName ?? '').trim().toLowerCase();
    final bn = (b.fullName ?? '').trim().toLowerCase();
    if (an.isEmpty && bn.isEmpty) return 0;
    if (an.isEmpty) return 1;
    if (bn.isEmpty) return -1;
    return an.compareTo(bn);
  }

  /// Free-text search over discoverable profiles directly (not the
  /// opt-in member_directory). The home tab's "See accounts" section
  /// surfaces profiles even if they don't have a directory row, so
  /// search had to gain a matching path or the user could see a name
  /// on the home tab and then fail to find it in search.
  ///
  /// Cascading fallback: try the strict query first (is_discoverable +
  /// is_banned). If that returns empty (or 400s because the columns
  /// don't exist on this deployment) retry without those filters so
  /// users can actually find each other by name. This was the cause
  /// of "I search and see nothing" — users hadn't set is_discoverable
  /// to true (or the column never shipped).
  static Future<List<MemberDirectoryEntry>> searchProfilesByName(
    String query, {
    int limit = 30,
  }) async {
    final term = query.trim();
    if (term.isEmpty) return const [];

    // Pass 1 — strict filter.
    final strict = await _searchByNameOnce(
      term,
      limit: limit,
      filters: const {'is_discoverable': true, 'is_banned': false},
    );
    if (strict.isNotEmpty) return strict;

    // Pass 2 — drop the discoverable flag (column might be missing,
    // or nobody opted in).
    final loose = await _searchByNameOnce(
      term,
      limit: limit,
      filters: const {'is_banned': false},
    );
    if (loose.isNotEmpty) return loose;

    // Pass 3 — name-only, no flag filters at all.
    return _searchByNameOnce(term, limit: limit, filters: const {});
  }

  static Future<List<MemberDirectoryEntry>> _searchByNameOnce(
    String term, {
    required int limit,
    required Map<String, bool> filters,
  }) async {
    try {
      final user = _client.auth.currentUser;
      var q = _client
          .from('profiles')
          .select('id, full_name, profile_photo_url, province, city, bio');
      filters.forEach((column, value) {
        q = q.eq(column, value);
      });
      var filtered = q.ilike('full_name', '%$term%');
      if (user != null) {
        filtered = filtered.neq('id', user.id);
      }
      final response =
          await filtered.order('full_name', ascending: true).limit(limit);
      return (response as List)
          .map((row) => row as Map<String, dynamic>)
          .map((row) => MemberDirectoryEntry(
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
    } catch (_) {
      // Column missing, RLS rejection, etc. Return empty so the
      // caller can fall through to the next pass.
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
