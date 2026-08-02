import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/church_model.dart';
import 'analytics_service.dart';
import 'cache_service.dart';
import 'connectivity_service.dart';

class ChurchService {
  ChurchService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static const _table = 'churches';
  static const _followsTable = 'church_followers';

  static Future<List<Church>> fetchChurches({
    String? search,
    String? city,
    int limit = 5000,
  }) async {
    var query = _client.from(_table).select();

    if (city != null && city.isNotEmpty) {
      query = query.eq('city', city);
    }

    if (search != null && search.trim().isNotEmpty) {
      final term = '%${search.trim()}%';
      query = query.or('name.ilike.$term,city.ilike.$term');
    }

    // Master reference Part 15: churches sort ALPHABETICALLY by name
    // by default. (When the user grants location, churches_screen
    // re-sorts nearest-first client-side via _sortByDistance.) The
    // previous members_count ordering was the unintended "filter
    // change" the user reported.
    final response = await query.order('name', ascending: true).limit(limit);

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
    final response = await _client.from(_table).select('city').order('city');
    // Some church rows have malformed `city` values from earlier
    // imports — bare punctuation like "(", whitespace-only strings,
    // or fragments of a parenthesised suburb that leaked into the
    // city column. Filter to entries that actually look like a place
    // name (at least one letter, length >= 2) so the filter chip row
    // doesn't get polluted.
    final cities =
        (response as List)
            .map((row) => (row['city'] ?? '').toString().trim())
            .where(_looksLikeCity)
            .toSet()
            .toList()
          ..sort();
    return cities;
  }

  static bool _looksLikeCity(String value) {
    if (value.length < 2) return false;
    return RegExp(r'[A-Za-z]').hasMatch(value);
  }

  static Future<Set<String>> fetchUserFollowedChurchIds() async {
    final user = _client.auth.currentUser;
    if (user == null) return <String>{};
    final response = await _client
        .from(_followsTable)
        .select('church_id')
        .eq('user_id', user.id);
    return (response as List).map((row) => row['church_id'].toString()).toSet();
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
    // church_followers.church_id is BIGINT — passing the raw String was
    // failing silently (or with a type error depending on the postgrest
    // server version), which is why a church picked in onboarding never
    // appeared on Home/Profile ("No church yet").
    final id = int.tryParse(churchId);
    if (id == null) {
      throw ArgumentError('Invalid church id: $churchId');
    }
    await _client.from(_followsTable).insert({
      'user_id': user.id,
      'church_id': id,
    });
    AnalyticsService.churchFollowed(id);
  }

  static Future<void> unfollow(String churchId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final id = int.tryParse(churchId);
    if (id == null) return;
    await _client
        .from(_followsTable)
        .delete()
        .eq('user_id', user.id)
        .eq('church_id', id);
  }

  /// True when at least one approved church_admins row exists for the
  /// given church. Used to gate the follow button on church_details so
  /// unclaimed churches push the viewer toward the claim flow instead
  /// of accumulating followers no one can post to.
  static Future<bool> hasApprovedAdmin(String churchId) async {
    final response = await _client
        .from('church_admins')
        .select('id')
        .eq('church_id', churchId)
        .eq('status', 'approved')
        .limit(1);
    return (response as List).isNotEmpty;
  }

  /// Insert a row into `church_edit_suggestions`. Status defaults to
  /// pending and an admin reviews it from the web dashboard.
  static Future<void> suggestEdit({
    required String churchId,
    required String fieldName,
    required String currentValue,
    required String suggestedValue,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to suggest an edit.');
    }
    await _client.from('church_edit_suggestions').insert({
      'church_id': churchId,
      'suggested_by': user.id,
      'field_name': fieldName,
      'current_value': currentValue,
      'suggested_value': suggestedValue,
    });
  }

  /// Insert into `church_suggestions` — used by suggest_church_screen
  /// to nominate a new SDA church for the directory.
  static Future<void> suggestChurch({
    required String name,
    required String province,
    String? city,
    String? suburb,
    String? pastorName,
    String? contactPhone,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to suggest a church.');
    }
    await _client.from('church_suggestions').insert({
      'suggested_by': user.id,
      'church_name': name.trim(),
      'province': province,
      'city': ?city?.trim(),
      'suburb': ?suburb?.trim(),
      'pastor_name': ?pastorName?.trim(),
      'contact_phone': ?contactPhone?.trim(),
    });
  }

  /// Apply to become a church admin. Status defaults to pending — admin
  /// reviews via the web dashboard and verifies via WhatsApp.
  /// Apply to manage a church. Contact-based verification (no document):
  /// the applicant leaves a WhatsApp number + optional email + a short note,
  /// the super admin talks to them off-app, then approves from the dashboard.
  static Future<void> applyForChurchAdmin({
    required String churchId,
    required String role,
    required String applicantName,
    required String applicantPhone,
    String? applicantEmail,
    String? note,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to claim a church.');
    }
    await _client.from('church_admins').upsert({
      'church_id': churchId,
      'user_id': user.id,
      'role': role,
      'applicant_name': applicantName.trim(),
      'applicant_phone': applicantPhone.trim(),
      'applicant_email': ?applicantEmail?.trim(),
      'applicant_note': ?note?.trim(),
      'status': 'pending',
    }, onConflict: 'church_id,user_id');
    AnalyticsService.churchClaimed(int.tryParse(churchId) ?? 0);
  }

  /// Read the caller's claim eligibility for [churchId] via the
  /// `get_church_claim_state` RPC (patch_121). RLS hides other users'
  /// pending rows, so this SECURITY DEFINER reader is the only way the
  /// claim screen can tell "already claimed" / "under review by someone
  /// else" / "you already have a claim" apart. Returns null on error so
  /// callers can fall back to showing the form.
  static Future<ChurchClaimState?> fetchClaimState(String churchId) async {
    final id = int.tryParse(churchId);
    if (id == null) return null;
    try {
      final res = await _client.rpc(
        'get_church_claim_state',
        params: {'p_church_id': id},
      );
      // RPC returns a single-row table → a list with one map.
      final row = res is List && res.isNotEmpty ? res.first : res;
      if (row is Map<String, dynamic>) return ChurchClaimState.fromJson(row);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Update the editable fields of a church. Server-side RLS
  /// (`churches_update_admin`, patch_121) only lets an APPROVED admin of
  /// this church write, and a column guard keeps trust/rollup columns
  /// (verified, follower_count, status…) read-only.
  static Future<void> updateChurch({
    required String churchId,
    String? description,
    String? address,
    String? suburb,
    String? city,
    String? pastorName,
    String? phone,
    String? email,
    int? foundedYear,
    double? latitude,
    double? longitude,
    String? coverPhotoUrl,
    String? profilePhotoUrl,
    List<ServiceTime>? serviceTimes,
  }) async {
    final id = int.tryParse(churchId);
    if (id == null) throw ArgumentError('Invalid church id: $churchId');
    final patch = <String, dynamic>{
      'description': description?.trim(),
      'address': address?.trim(),
      'suburb': suburb?.trim(),
      'city': city?.trim(),
      'pastor_name': pastorName?.trim(),
      'phone': phone?.trim(),
      'email': email?.trim(),
      'founded_year': foundedYear,
      'latitude': latitude,
      'longitude': longitude,
    };
    // Only overwrite a photo column when a new URL was supplied — passing
    // null would blow away the existing image.
    if (coverPhotoUrl != null) patch['cover_photo_url'] = coverPhotoUrl;
    if (profilePhotoUrl != null) patch['profile_photo_url'] = profilePhotoUrl;
    // An empty list is meaningful here (the admin cleared them all), so
    // this checks for null rather than for emptiness.
    if (serviceTimes != null) {
      patch['service_times'] = serviceTimes.map((e) => e.toJson()).toList();
    }
    await _client.from(_table).update(patch).eq('id', id);
    // The churches tab hydrates from a 24h Hive cache before it hits the
    // network, so without this an admin who just changed the logo still
    // sees the old one in the directory — and keeps seeing it offline.
    await CacheService.invalidate(churchesListCacheKey);
  }

  /// Hive key for the cached church directory. Shared so the screen that
  /// reads it and the mutations that invalidate it can't drift apart.
  static const String churchesListCacheKey = 'churches_list';

  // ---- Super-admin: church-admin claim queue (patch_112) ----------------
  static Future<List<PendingChurchAdmin>> listPendingChurchAdmins() async {
    final res = await _client.rpc('admin_list_pending_church_admins');
    if (res is! List) return const [];
    return res
        .map((row) => PendingChurchAdmin.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  static Future<void> approveChurchAdmin(int id) async {
    await _client.rpc('admin_approve_church_admin', params: {'p_id': id});
  }

  static Future<void> rejectChurchAdmin(int id, {String? reason}) async {
    await _client.rpc(
      'admin_reject_church_admin',
      params: {'p_id': id, 'p_reason': reason},
    );
  }

  /// Fetch a church's announcements feed. Filters out expired rows, and
  /// (unless [includeScheduled]) anything not yet due to publish.
  ///
  /// The admin dashboard passes includeScheduled so a secretary can see
  /// and cancel what they've queued; members never should.
  static Future<List<ChurchAnnouncement>> fetchAnnouncements({
    required String churchId,
    bool includeScheduled = false,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    var query = _client
        .from('announcements')
        .select()
        .eq('church_id', churchId)
        .or('expires_at.is.null,expires_at.gt.$now');
    if (!includeScheduled) {
      query = query.or('publish_at.is.null,publish_at.lte.$now');
    }
    final response = await query
        .order('is_pinned', ascending: false)
        .order('created_at', ascending: false)
        .limit(100);
    return (response as List)
        .map((row) => ChurchAnnouncement.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Record that the signed-in member opened this announcement.
  ///
  /// Feeds the admin reach sparkline (patch_173). Best-effort and
  /// idempotent — the primary key swallows repeats, and a member who
  /// reads the same notice twice is still one reader.
  static Future<void> markAnnouncementRead(String announcementId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final id = int.tryParse(announcementId);
    if (id == null) return;
    try {
      await _client
          .from('announcement_reads')
          .upsert(
            {'announcement_id': id, 'user_id': user.id},
            onConflict: 'announcement_id,user_id',
            ignoreDuplicates: true,
          );
    } catch (_) {
      // Analytics must never break reading an announcement.
    }
  }

  /// Set, change or clear my reaction on an announcement, returning the
  /// fresh tally.
  ///
  /// Passing null — or the reaction already set — CLEARS it, so tapping
  /// the same face twice un-reacts. Returns null if the call failed, so
  /// the caller can roll its optimistic update back.
  ///
  /// Goes through an RPC rather than a client `.upsert()` on purpose. An
  /// upsert is `INSERT … ON CONFLICT DO UPDATE … RETURNING`, which needs
  /// SELECT *and* UPDATE policies or it raises 42501 into a catch and
  /// fails silently — that has bitten this project three times. The RPC
  /// also hands back the new counts in the SAME round trip, so the UI
  /// never has to re-query to show the number it just changed.
  static Future<AnnouncementReactionState?> setAnnouncementReaction(
    String announcementId,
    AnnouncementReaction? reaction,
  ) async {
    final id = int.tryParse(announcementId);
    if (id == null) return null;
    try {
      final res = await _client.rpc(
        'set_announcement_reaction',
        params: {'p_announcement_id': id, 'p_reaction': reaction?.id},
      );
      if (res is! Map) return null;
      return AnnouncementReactionState.fromJson(Map<String, dynamic>.from(res));
    } catch (_) {
      return null;
    }
  }

  /// Reactions for a batch of announcements, keyed by announcement id.
  ///
  /// Batched because the list screen renders many announcements at once
  /// and one call per row would be N round trips.
  static Future<Map<String, AnnouncementReactionState>>
  fetchAnnouncementReactions(List<String> announcementIds) async {
    final ids = announcementIds
        .map(int.tryParse)
        .whereType<int>()
        .toList(growable: false);
    if (ids.isEmpty) return const {};
    try {
      final res = await _client.rpc(
        'announcement_reactions_for',
        params: {'p_ids': ids},
      );
      if (res is! List) return const {};
      final out = <String, AnnouncementReactionState>{};
      for (final row in res) {
        final m = Map<String, dynamic>.from(row as Map);
        out[m['announcement_id'].toString()] =
            AnnouncementReactionState.fromJson(m);
      }
      return out;
    } catch (_) {
      // Reactions are decoration on top of the announcement — never let
      // them stop it rendering.
      return const {};
    }
  }

  /// Reaction analytics for the admin dashboard. Returns empty for anyone
  /// who isn't an approved admin of the church (the RPC enforces it).
  static Future<List<AnnouncementReactionStat>> fetchAnnouncementReactionStats(
    String churchId, {
    int limit = 8,
  }) async {
    try {
      final res = await _client.rpc(
        'church_announcement_reactions',
        params: {
          'p_church_id': int.tryParse(churchId) ?? churchId,
          'p_limit': limit,
        },
      );
      if (res is! List) return const [];
      return res
          .map(
            (r) => AnnouncementReactionStat.fromJson(
              Map<String, dynamic>.from(r as Map),
            ),
          )
          .toList()
          .reversed // oldest → newest, matching the reach sparkline
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Sent vs opened for this church's recent announcements (patch_173).
  /// Returns empty for anyone who isn't an approved admin of the church.
  static Future<List<AnnouncementReach>> fetchAnnouncementReach(
    String churchId, {
    int limit = 8,
  }) async {
    try {
      final res = await _client.rpc(
        'church_announcement_reach',
        params: {
          'p_church_id': int.tryParse(churchId) ?? churchId,
          'p_limit': limit,
        },
      );
      if (res is! List) return const [];
      return res
          .map(
            (r) =>
                AnnouncementReach.fromJson(Map<String, dynamic>.from(r as Map)),
          )
          .toList()
          .reversed // oldest → newest, so the sparkline reads left to right
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// How many of MY friends belong to each of these churches (patch_176).
  /// Returns a churchId → count map; churches with none are absent.
  static Future<Map<String, int>> fetchFriendCounts(
    List<String> churchIds,
  ) async {
    if (churchIds.isEmpty) return const {};
    final ids = churchIds
        .map(int.tryParse)
        .whereType<int>()
        .toList(growable: false);
    if (ids.isEmpty) return const {};
    try {
      final res = await _client.rpc(
        'church_friend_counts',
        params: {'p_church_ids': ids},
      );
      if (res is! List) return const {};
      return {
        for (final r in res)
          (r as Map)['church_id'].toString():
              ((r['friend_count'] as num?)?.toInt() ?? 0),
      };
    } catch (_) {
      return const {};
    }
  }

  /// Set (or clear) the signed-in member's home church — `profiles
  /// .church_id`. Needs no RPC: profiles_update_self already allows a
  /// member to write their own row.
  ///
  /// This matters more than it looks: patch_171 made announcements fan
  /// out to `profiles.church_id`, so a member who never sets one only
  /// hears from churches they explicitly followed.
  static Future<void> setHomeChurch(String? churchId) async {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('Sign in first.');
    await _client
        .from('profiles')
        .update({'church_id': churchId == null ? null : int.tryParse(churchId)})
        .eq('id', user.id);
  }

  /// The signed-in member's home church id, or null.
  static Future<String?> fetchHomeChurchId() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    try {
      final row = await _client
          .from('profiles')
          .select('church_id')
          .eq('id', user.id)
          .maybeSingle();
      return row?['church_id']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Everything waiting on this church's admin, oldest-waiting first.
  ///
  /// Three queues that were previously invisible from the dashboard:
  /// community events proposed against this church, member-suggested
  /// edits to the church profile, and (patch_175) nominated admins. The
  /// `pending_approvals` screen has always handled the first two — the
  /// dashboard just never linked to it, so nothing told an admin there
  /// was anything to do.
  static Future<List<AdminTask>> fetchNeedsYou(String churchId) async {
    final out = <AdminTask>[];
    Future<void> collect(
      String table,
      AdminTaskKind kind,
      String Function(Map<String, dynamic>) title,
    ) async {
      try {
        final rows = await _client
            .from(table)
            .select()
            .eq('church_id', churchId)
            .eq('status', 'pending')
            .order('created_at', ascending: true)
            .limit(20);
        for (final r in (rows as List).cast<Map<String, dynamic>>()) {
          out.add(
            AdminTask(
              id: r['id'].toString(),
              kind: kind,
              title: title(r),
              waitingSince: DateTime.tryParse(
                r['created_at']?.toString() ?? '',
              )?.toLocal(),
            ),
          );
        }
      } catch (_) {
        // One unreadable queue must not blank the whole card.
      }
    }

    await Future.wait([
      collect(
        'events',
        AdminTaskKind.event,
        (r) => (r['title'] ?? 'Untitled event').toString(),
      ),
      collect(
        'church_edit_suggestions',
        AdminTaskKind.edit,
        (r) => 'Suggested edit to your church details',
      ),
      collect(
        'church_admins',
        AdminTaskKind.admin,
        (r) => 'Admin nomination awaiting approval',
      ),
    ]);

    // Longest wait first. That IS the ordering the queue is for: a
    // three-week-old request is a member who has been ignored, and a
    // newest-first list buries exactly those.
    out.sort((a, b) {
      final av = a.waitingSince;
      final bv = b.waitingSince;
      if (av == null && bv == null) return 0;
      if (av == null) return 1;
      if (bv == null) return -1;
      return av.compareTo(bv);
    });
    return out;
  }

  // ---- Multiple admins per church (patch_175) --------------------------

  /// The admin roster for a church. Approved admins of that church only.
  static Future<List<ChurchAdminMember>> fetchChurchAdmins(
    String churchId,
  ) async {
    try {
      final res = await _client.rpc(
        'church_admin_list',
        params: {'p_church_id': int.tryParse(churchId) ?? churchId},
      );
      if (res is! List) return const [];
      return res
          .map(
            (r) =>
                ChurchAdminMember.fromJson(Map<String, dynamic>.from(r as Map)),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Primary admin nominates a member as a standard admin. Lands as
  /// `pending` — super-admin approval is still the only route to power.
  static Future<void> nominateChurchAdmin({
    required String churchId,
    required String userId,
  }) async {
    await _client.rpc(
      'church_admin_nominate',
      params: {
        'p_church_id': int.tryParse(churchId) ?? churchId,
        'p_user_id': userId,
      },
    );
  }

  static Future<void> revokeChurchAdmin(int id) async {
    await _client.rpc('church_admin_revoke', params: {'p_id': id});
  }

  /// Resolve an announcement id to the church that posted it.
  ///
  /// Announcement notifications carry the ANNOUNCEMENT id in
  /// `reference_id`, but the announcements screen is keyed on the church —
  /// so a tap has to make this hop before it can open anything. Returns
  /// null when the announcement (or its church) is gone, so callers can
  /// fall back rather than push a broken route.
  static Future<Church?> fetchChurchForAnnouncement(
    String announcementId,
  ) async {
    final row = await _client
        .from('announcements')
        .select('church_id')
        .eq('id', announcementId)
        .maybeSingle();
    final churchId = row?['church_id']?.toString() ?? '';
    if (churchId.isEmpty) return null;
    return fetchChurchById(churchId);
  }

  /// Post an announcement on behalf of an approved church admin.
  /// Server-side RLS enforces that the caller actually owns this role.
  /// Post an announcement, or queue one for later.
  ///
  /// [publishAt] in the future defers the whole thing: the insert trigger
  /// skips the fan-out and patch_174's cron job posts it on time. Members
  /// don't see it in the meantime (see [fetchAnnouncements]).
  static Future<void> postAnnouncement({
    required String churchId,
    required String title,
    required String body,
    String category = 'general',
    bool isPinned = false,
    DateTime? publishAt,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to post.');
    }
    await _client.from('announcements').insert({
      'church_id': churchId,
      'posted_by': user.id,
      'title': title.trim(),
      'body': body.trim(),
      'category': category,
      'is_pinned': isPinned,
      if (publishAt != null) 'publish_at': publishAt.toUtc().toIso8601String(),
    });
  }

  /// Cancel a queued announcement. Only meaningful before it publishes —
  /// once notified_at is set the notifications are already out.
  static Future<void> cancelScheduledAnnouncement(String announcementId) async {
    final id = int.tryParse(announcementId);
    if (id == null) return;
    await _client
        .from('announcements')
        .delete()
        .eq('id', id)
        .isFilter('notified_at', null);
  }

  /// How many members follow this church. Returns 0 unless the caller is the
  /// super admin or an approved admin of the church (patch_135).
  static Future<int> fetchFollowerCount(String churchId) async {
    try {
      final res = await _client.rpc(
        'church_member_count',
        params: {'p_church_id': int.tryParse(churchId) ?? churchId},
      );
      return (res as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Dashboard stats (members / announcements / events) for an approved admin
  /// of the church or the super admin (patch_139).
  static Future<ChurchAdminStats> fetchAdminStats(String churchId) async {
    try {
      final res = await _client.rpc(
        'church_admin_stats',
        params: {'p_church_id': int.tryParse(churchId) ?? churchId},
      );
      final list = res as List;
      if (list.isEmpty) return const ChurchAdminStats();
      final r = list.first as Map<String, dynamic>;
      return ChurchAdminStats(
        members: (r['members'] as num?)?.toInt() ?? 0,
        announcements: (r['announcements'] as num?)?.toInt() ?? 0,
        events: (r['events'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return const ChurchAdminStats();
    }
  }

  /// Members (followers) of the church, with name + photo, A→Z. Empty unless
  /// the caller is the church's approved admin / super admin (patch_139).
  static Future<List<ChurchMember>> fetchMembers(String churchId) async {
    try {
      final res = await _client.rpc(
        'church_member_list',
        params: {'p_church_id': int.tryParse(churchId) ?? churchId},
      );
      return (res as List)
          .map((r) => ChurchMember.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Approved church-admin roles for the current user. Used to gate
  /// access to the admin dashboard and to pre-fill the church picker.
  ///
  /// Cached locally (per user) so an approved admin can still reach their
  /// dashboard offline — RLS-gated content inside still needs a connection,
  /// but the entry point + role survive a dropped network.
  static Future<List<ChurchAdminRole>> fetchMyAdminRoles() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    final cacheKey = 'church_admin_roles:${user.id}';
    if (!ConnectivityService.isOnline) {
      return _readRolesCache(cacheKey);
    }
    try {
      final response = await _client
          .from('church_admins')
          .select('*, churches(name, city)')
          .eq('user_id', user.id);
      final rows = (response as List).cast<Map<String, dynamic>>();
      CacheService.writeString(cacheKey, jsonEncode(rows));
      return rows.map((row) => ChurchAdminRole.fromJson(row)).toList();
    } catch (_) {
      return _readRolesCache(cacheKey);
    }
  }

  static List<ChurchAdminRole> _readRolesCache(String key) {
    try {
      final raw = CacheService.readStringStale(key);
      if (raw == null) return const [];
      return (jsonDecode(raw) as List)
          .map((r) => ChurchAdminRole.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

class ChurchAnnouncement {
  const ChurchAnnouncement({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.category = 'general',
    this.isPinned = false,
    this.publishAt,
    this.notifiedAt,
  });

  final String id;
  final String title;
  final String body;
  final String category;
  final bool isPinned;
  final DateTime createdAt;

  /// When this is due to go out (patch_174). Null means it went out on
  /// insert, like every announcement before scheduling existed.
  final DateTime? publishAt;

  /// When the fan-out actually ran (patch_173). Null means it hasn't yet
  /// — the announcement is queued and no member can see it.
  final DateTime? notifiedAt;

  /// Queued, not published. The admin dashboard shows these; the member
  /// feed filters them out.
  bool get isScheduled =>
      notifiedAt == null &&
      publishAt != null &&
      publishAt!.isAfter(DateTime.now());

  factory ChurchAnnouncement.fromJson(Map<String, dynamic> json) {
    return ChurchAnnouncement(
      id: json['id'].toString(),
      title: (json['title'] ?? '') as String,
      body: (json['body'] ?? '') as String,
      category: (json['category'] ?? 'general') as String,
      isPinned: json['is_pinned'] == true,
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      publishAt: DateTime.tryParse(
        json['publish_at']?.toString() ?? '',
      )?.toLocal(),
      notifiedAt: DateTime.tryParse(
        json['notified_at']?.toString() ?? '',
      )?.toLocal(),
    );
  }
}

enum AdminTaskKind { event, edit, admin }

/// One item in the dashboard's "needs you" queue.
class AdminTask {
  const AdminTask({
    required this.id,
    required this.kind,
    required this.title,
    this.waitingSince,
  });

  final String id;
  final AdminTaskKind kind;
  final String title;
  final DateTime? waitingSince;

  /// How long this has been sitting there. Null when the row has no
  /// usable timestamp.
  Duration? get waited =>
      waitingSince == null ? null : DateTime.now().difference(waitingSince!);

  /// "3 weeks", "2 days", "4 hours". Deliberately blunt — the point of
  /// the queue is that a long number should be uncomfortable to read.
  String get waitedLabel {
    final d = waited;
    if (d == null) return '';
    if (d.inDays >= 14) return '${d.inDays ~/ 7} weeks';
    if (d.inDays >= 1) return '${d.inDays} day${d.inDays == 1 ? '' : 's'}';
    if (d.inHours >= 1) return '${d.inHours} hour${d.inHours == 1 ? '' : 's'}';
    return 'just now';
  }

  /// Past a week, the row turns red. Not a threshold with a rule behind
  /// it — just long enough that a member has noticed being ignored.
  bool get isOverdue => (waited?.inDays ?? 0) >= 7;
}

/// One bar of the admin dashboard's reach sparkline (patch_173).
/// The four reactions a member can leave on a church announcement. The DB
/// enforces the same set with a CHECK constraint — an open text column
/// would become an emoji dumping ground and make the admin breakdown
/// impossible to aggregate.
enum AnnouncementReaction {
  amen('amen', 'Amen', '\u{1F64F}'),
  praise('praise', 'Praise', '\u{1F64C}'),
  pray('pray', 'Praying', '\u{1F91D}'),
  love('love', 'Love', '\u{2764}\u{FE0F}');

  const AnnouncementReaction(this.id, this.label, this.emoji);

  /// Matches `announcement_reactions.reaction` exactly.
  final String id;
  final String label;
  final String emoji;

  static AnnouncementReaction? fromId(String? id) {
    if (id == null) return null;
    for (final r in AnnouncementReaction.values) {
      if (r.id == id) return r;
    }
    // An unknown value means the DB gained a reaction this build predates.
    // Drop it rather than crash the announcement list.
    return null;
  }
}

/// How one announcement was received: the tally per reaction, and which
/// one the signed-in member left (null if they haven't reacted).
class AnnouncementReactionState {
  const AnnouncementReactionState({required this.counts, this.mine});

  final Map<AnnouncementReaction, int> counts;
  final AnnouncementReaction? mine;

  int get total => counts.values.fold(0, (a, b) => a + b);

  static const empty = AnnouncementReactionState(counts: {});

  /// What this state becomes when the member taps [tapped], computed
  /// locally so the UI can paint the tap before the server answers.
  ///
  /// Mirrors `set_announcement_reaction` exactly: tapping the reaction you
  /// already left CLEARS it, and moving between reactions decrements the
  /// old one as it increments the new. Kept here rather than in the screen
  /// so the optimistic path and the server agree by construction — if they
  /// drift, the count visibly jumps when the RPC returns.
  AnnouncementReactionState afterTapping(AnnouncementReaction tapped) {
    final next = Map<AnnouncementReaction, int>.from(counts);
    final current = mine;

    if (current != null) {
      final remaining = (next[current] ?? 1) - 1;
      if (remaining > 0) {
        next[current] = remaining;
      } else {
        next.remove(current);
      }
    }
    if (current == tapped) {
      return AnnouncementReactionState(counts: next, mine: null);
    }
    next[tapped] = (next[tapped] ?? 0) + 1;
    return AnnouncementReactionState(counts: next, mine: tapped);
  }

  factory AnnouncementReactionState.fromJson(Map<String, dynamic> json) {
    final raw = json['counts'];
    final counts = <AnnouncementReaction, int>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        final kind = AnnouncementReaction.fromId(key?.toString());
        final n = (value as num?)?.toInt() ?? 0;
        if (kind != null && n > 0) counts[kind] = n;
      });
    }
    return AnnouncementReactionState(
      counts: counts,
      mine: AnnouncementReaction.fromId(json['mine'] as String?),
    );
  }
}

/// One announcement's row in the admin dashboard: how many opened it and
/// how they responded. Deliberately shaped like [AnnouncementReach] so the
/// dashboard can put reach and reactions side by side.
class AnnouncementReactionStat {
  const AnnouncementReactionStat({
    required this.id,
    required this.title,
    required this.category,
    required this.createdAt,
    required this.readCount,
    required this.reactions,
  });

  final String id;
  final String title;
  final String category;
  final DateTime createdAt;

  /// Members who opened it (announcement_reads, patch_173).
  final int readCount;

  final AnnouncementReactionState reactions;

  int get reactionCount => reactions.total;

  factory AnnouncementReactionStat.fromJson(Map<String, dynamic> json) {
    return AnnouncementReactionStat(
      id: json['id'].toString(),
      title: (json['title'] as String?) ?? '',
      category: (json['category'] as String?) ?? '',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      readCount: (json['read_count'] as num?)?.toInt() ?? 0,
      reactions: AnnouncementReactionState.fromJson(json),
    );
  }
}

class AnnouncementReach {
  const AnnouncementReach({
    required this.id,
    required this.title,
    required this.category,
    required this.createdAt,
    required this.sentCount,
    required this.readCount,
  });

  final String id;
  final String title;
  final String category;
  final DateTime createdAt;

  /// Notifications actually written by the fan-out — delivery, not opens.
  final int sentCount;

  /// Members who opened it. Always <= [sentCount].
  final int readCount;

  /// 0..1. Zero when nothing was sent, so the bar renders empty rather
  /// than dividing by zero.
  double get openRate => sentCount <= 0 ? 0 : readCount / sentCount;

  factory AnnouncementReach.fromJson(Map<String, dynamic> json) =>
      AnnouncementReach(
        id: json['id'].toString(),
        title: (json['title'] ?? '') as String,
        category: (json['category'] ?? 'general') as String,
        createdAt:
            DateTime.tryParse(
              json['created_at']?.toString() ?? '',
            )?.toLocal() ??
            DateTime.now(),
        sentCount: (json['sent_count'] as num?)?.toInt() ?? 0,
        readCount: (json['read_count'] as num?)?.toInt() ?? 0,
      );
}

/// A row of the church's admin roster (patch_175).
class ChurchAdminMember {
  const ChurchAdminMember({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.role,
    required this.status,
    this.photoUrl,
    this.createdAt,
  });

  final int id;
  final String userId;
  final String fullName;
  final String? photoUrl;

  /// 'primary' | 'standard'. Only one primary per church.
  final String role;

  /// 'pending' | 'approved' | 'rejected'.
  final String status;
  final DateTime? createdAt;

  bool get isPrimary => role == 'primary';
  bool get isApproved => status == 'approved';

  factory ChurchAdminMember.fromJson(Map<String, dynamic> json) =>
      ChurchAdminMember(
        id: (json['id'] as num?)?.toInt() ?? 0,
        userId: json['user_id'].toString(),
        fullName: (json['full_name'] ?? 'Member') as String,
        photoUrl: json['photo_url'] as String?,
        role: (json['role'] ?? 'standard') as String,
        status: (json['status'] ?? 'pending') as String,
        createdAt: DateTime.tryParse(
          json['created_at']?.toString() ?? '',
        )?.toLocal(),
      );
}

class ChurchAdminRole {
  const ChurchAdminRole({
    required this.id,
    required this.churchId,
    required this.churchName,
    required this.role,
    required this.status,
    this.city,
  });

  final String id;
  final String churchId;
  final String churchName;
  final String role; // 'primary' / 'standard'
  final String status; // 'pending' / 'approved' / 'rejected'
  final String? city;

  bool get isApproved => status == 'approved';

  factory ChurchAdminRole.fromJson(Map<String, dynamic> json) {
    final church = json['churches'];
    final churchMap = church is Map<String, dynamic> ? church : null;
    return ChurchAdminRole(
      id: json['id'].toString(),
      churchId: (json['church_id'] ?? '').toString(),
      churchName: (churchMap?['name'] as String?) ?? 'Church',
      role: (json['role'] ?? 'standard') as String,
      status: (json['status'] ?? 'pending') as String,
      city: churchMap?['city'] as String?,
    );
  }
}

/// Aggregate stats for the church-admin dashboard (patch_139).
class ChurchAdminStats {
  const ChurchAdminStats({
    this.members = 0,
    this.announcements = 0,
    this.events = 0,
  });

  final int members;
  final int announcements;
  final int events;
}

/// A follower of the church, shown by name in the admin's members list
/// (patch_139).
class ChurchMember {
  const ChurchMember({
    required this.userId,
    required this.fullName,
    this.profilePhotoUrl,
    this.joinedAt,
  });

  final String userId;
  final String fullName;
  final String? profilePhotoUrl;
  final DateTime? joinedAt;

  factory ChurchMember.fromJson(Map<String, dynamic> json) {
    return ChurchMember(
      userId: (json['user_id'] ?? '').toString(),
      fullName: (json['full_name'] as String?)?.trim().isNotEmpty == true
          ? json['full_name'] as String
          : 'Member',
      profilePhotoUrl: json['profile_photo_url'] as String?,
      joinedAt: json['joined_at'] == null
          ? null
          : DateTime.tryParse(json['joined_at'].toString()),
    );
  }
}

/// Caller-specific claim eligibility for a single church
/// (get_church_claim_state RPC, patch_121). Drives which message the
/// claim screen shows.
class ChurchClaimState {
  const ChurchClaimState({
    required this.churchHasApprovedAdmin,
    required this.churchHasPendingOther,
    required this.myStatusForChurch,
    required this.myOtherPendingCount,
    required this.myOtherApprovedCount,
  });

  /// This church already has an approved admin.
  final bool churchHasApprovedAdmin;

  /// Someone ELSE has a pending claim on this church.
  final bool churchHasPendingOther;

  /// The caller's own latest status for THIS church: null / 'pending' /
  /// 'approved' / 'rejected'.
  final String? myStatusForChurch;

  /// The caller's pending claims on OTHER churches.
  final int myOtherPendingCount;

  /// The caller's approved roles on OTHER churches.
  final int myOtherApprovedCount;

  bool get myClaimPending => myStatusForChurch == 'pending';
  bool get myClaimApproved => myStatusForChurch == 'approved';

  factory ChurchClaimState.fromJson(Map<String, dynamic> json) {
    int readInt(dynamic v) =>
        v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
    return ChurchClaimState(
      churchHasApprovedAdmin: json['church_has_approved_admin'] == true,
      churchHasPendingOther: json['church_has_pending_other'] == true,
      myStatusForChurch: json['my_status_for_church'] as String?,
      myOtherPendingCount: readInt(json['my_other_pending_count']),
      myOtherApprovedCount: readInt(json['my_other_approved_count']),
    );
  }
}

/// A pending church-admin claim shown in the super-admin approval queue
/// (admin_list_pending_church_admins, patch_112).
class PendingChurchAdmin {
  const PendingChurchAdmin({
    required this.id,
    required this.churchId,
    required this.churchName,
    required this.role,
    required this.applicantName,
    required this.applicantPhone,
    this.churchCity,
    this.applicantEmail,
    this.note,
    required this.createdAt,
  });

  final int id;
  final String churchId;
  final String churchName;
  final String? churchCity;
  final String role;
  final String applicantName;
  final String applicantPhone;
  final String? applicantEmail;
  final String? note;
  final DateTime createdAt;

  factory PendingChurchAdmin.fromJson(Map<String, dynamic> json) {
    return PendingChurchAdmin(
      id: (json['id'] as num).toInt(),
      churchId: (json['church_id'] ?? '').toString(),
      churchName: (json['church_name'] as String?) ?? 'Church',
      churchCity: json['church_city'] as String?,
      role: (json['role'] ?? 'standard') as String,
      applicantName: (json['applicant_name'] as String?) ?? 'Applicant',
      applicantPhone: (json['applicant_phone'] as String?) ?? '',
      applicantEmail: json['applicant_email'] as String?,
      note: json['note'] as String?,
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
