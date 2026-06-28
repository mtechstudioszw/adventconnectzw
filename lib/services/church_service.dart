import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/church_model.dart';
import 'analytics_service.dart';

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
    final response = await query
        .order('name', ascending: true)
        .limit(limit);

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
    // Some church rows have malformed `city` values from earlier
    // imports — bare punctuation like "(", whitespace-only strings,
    // or fragments of a parenthesised suburb that leaked into the
    // city column. Filter to entries that actually look like a place
    // name (at least one letter, length >= 2) so the filter chip row
    // doesn't get polluted.
    final cities = (response as List)
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
    return (response as List)
        .map((row) => row['church_id'].toString())
        .toSet();
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
      final res = await _client
          .rpc('get_church_claim_state', params: {'p_church_id': id});
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
    await _client.from(_table).update(patch).eq('id', id);
  }

  // ---- Super-admin: church-admin claim queue (patch_112) ----------------
  static Future<List<PendingChurchAdmin>> listPendingChurchAdmins() async {
    final res = await _client.rpc('admin_list_pending_church_admins');
    if (res is! List) return const [];
    return res
        .map((row) =>
            PendingChurchAdmin.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  static Future<void> approveChurchAdmin(int id) async {
    await _client.rpc('admin_approve_church_admin', params: {'p_id': id});
  }

  static Future<void> rejectChurchAdmin(int id, {String? reason}) async {
    await _client.rpc('admin_reject_church_admin',
        params: {'p_id': id, 'p_reason': reason});
  }

  /// Fetch a church's announcements feed. Filters out expired rows.
  static Future<List<ChurchAnnouncement>> fetchAnnouncements({
    required String churchId,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final response = await _client
        .from('announcements')
        .select()
        .eq('church_id', churchId)
        .or('expires_at.is.null,expires_at.gt.$now')
        .order('is_pinned', ascending: false)
        .order('created_at', ascending: false)
        .limit(100);
    return (response as List)
        .map((row) =>
            ChurchAnnouncement.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Post an announcement on behalf of an approved church admin.
  /// Server-side RLS enforces that the caller actually owns this role.
  static Future<void> postAnnouncement({
    required String churchId,
    required String title,
    required String body,
    String category = 'general',
    bool isPinned = false,
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
    });
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

  /// Approved church-admin roles for the current user. Used to gate
  /// access to the admin dashboard and to pre-fill the church picker.
  static Future<List<ChurchAdminRole>> fetchMyAdminRoles() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    final response = await _client
        .from('church_admins')
        .select('*, churches(name, city)')
        .eq('user_id', user.id);
    return (response as List)
        .map((row) => ChurchAdminRole.fromJson(row as Map<String, dynamic>))
        .toList();
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
  });

  final String id;
  final String title;
  final String body;
  final String category;
  final bool isPinned;
  final DateTime createdAt;

  factory ChurchAnnouncement.fromJson(Map<String, dynamic> json) {
    return ChurchAnnouncement(
      id: json['id'].toString(),
      title: (json['title'] ?? '') as String,
      body: (json['body'] ?? '') as String,
      category: (json['category'] ?? 'general') as String,
      isPinned: json['is_pinned'] == true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
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
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
