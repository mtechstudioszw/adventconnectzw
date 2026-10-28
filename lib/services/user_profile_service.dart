import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/require_changed.dart';

/// Snapshot of another user's public profile fields. Mirrors what the
/// profiles row exposes via RLS — `is_discoverable=false` users get a
/// cut-down version on the client side.
class PublicUserProfile {
  const PublicUserProfile({
    required this.id,
    required this.fullName,
    required this.isDiscoverable,
    required this.isVerified,
    this.isVerifiedAdmin = false,
    required this.isBusiness,
    this.profilePhotoUrl,
    this.coverPhotoUrl,
    this.bio,
    this.country,
    this.province,
    this.city,
    this.dateOfBirth,
    this.joinedAt,
    this.churchName,
    this.showAge = true,
    this.username,
    this.website,
    this.isPrivate = false,
  });

  final String id;
  final String fullName;
  final String? profilePhotoUrl;
  final String? coverPhotoUrl;
  final String? bio;

  /// ISO 3166-1 alpha-2 (patch_213). Display name and flag come from
  /// lib/config/countries.dart — never store or compare the display name.
  final String? country;
  final String? province;
  final String? city;
  final DateTime? dateOfBirth;
  final DateTime? joinedAt;
  final String? churchName;
  final bool isDiscoverable;
  final bool isVerified;

  /// Cosmetic gold tick: TRUE for the super admin and approved church admins
  /// (patch_134). Grants no powers — display only.
  final bool isVerifiedAdmin;
  final bool isBusiness;
  final bool showAge;

  /// Public handle, without the @. Null until the member picks one.
  final String? username;

  /// Public link (patch_274). Null before the patch runs or when unset.
  final String? website;

  /// Follow requests need approval and posts are hidden from non-followers
  /// (patch_274). Separate from [isDiscoverable], which hides the whole
  /// profile from search and strangers.
  final bool isPrivate;

  /// Whether to show the gold verified tick next to this user's name.
  bool get showsVerifiedTick => isVerified || isVerifiedAdmin;

  int? get age {
    if (dateOfBirth == null) return null;
    final now = DateTime.now();
    var a = now.year - dateOfBirth!.year;
    final hadBirthday =
        now.month > dateOfBirth!.month ||
        (now.month == dateOfBirth!.month && now.day >= dateOfBirth!.day);
    if (!hadBirthday) a -= 1;
    return a;
  }

  factory PublicUserProfile.fromJson(Map<String, dynamic> json) {
    final church = json['churches'];
    final churchMap = church is Map<String, dynamic> ? church : null;
    return PublicUserProfile(
      id: (json['id'] ?? '').toString(),
      fullName: (json['full_name'] as String?)?.trim().isNotEmpty == true
          ? json['full_name'] as String
          : 'Member',
      profilePhotoUrl: json['profile_photo_url'] as String?,
      coverPhotoUrl: json['cover_photo_url'] as String?,
      bio: json['bio'] as String?,
      country: json['country'] as String?,
      province: json['province'] as String?,
      city: json['city'] as String?,
      dateOfBirth: json['date_of_birth'] != null
          ? DateTime.tryParse(json['date_of_birth'].toString())
          : null,
      joinedAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      churchName: churchMap?['name'] as String?,
      isDiscoverable: json['is_discoverable'] != false,
      isVerified: json['is_verified'] == true,
      isVerifiedAdmin: json['is_verified_admin'] == true,
      isBusiness: json['is_business'] == true,
      showAge: json['show_age'] != false,
      username: (json['username'] as String?)?.trim().isNotEmpty == true
          ? (json['username'] as String).trim()
          : null,
      website: (json['website'] as String?)?.trim().isNotEmpty == true
          ? (json['website'] as String).trim()
          : null,
      isPrivate: json['is_private'] == true,
    );
  }
}

/// Read other users' profiles. Service-side so route handlers don't
/// have to know how to spell the embed.
class UserProfileService {
  UserProfileService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static const _baseColumns =
      'id, full_name, username, profile_photo_url, cover_photo_url, bio, '
      'country, province, city, date_of_birth, created_at, '
      'is_discoverable, is_verified, is_verified_admin, is_business, show_age, '
      'churches(name)';

  /// Flips false the first time patch_274's columns are missing, so later
  /// fetches go straight to the columns that exist.
  static bool _hasFollowColumns = true;

  /// Undefined column (42703) or not granted (42501). Checked in the
  /// message too: on a `.maybeSingle()` request postgrest 2.7 rebuilds the
  /// exception with the HTTP status ("400") as its code, and the Postgres
  /// code survives only inside the raw body it keeps as the message.
  static bool _isMissingColumn(PostgrestException e) {
    for (final code in const ['42703', '42501']) {
      if (e.code == code || e.message.contains('"$code"')) return true;
    }
    return false;
  }

  static Future<PublicUserProfile?> fetch(String userId) async {
    Future<Map<String, dynamic>?> query(String cols) =>
        _client.from('profiles').select(cols).eq('id', userId).maybeSingle();

    Map<String, dynamic>? row;
    if (_hasFollowColumns) {
      try {
        row = await query('$_baseColumns, website, is_private');
      } on PostgrestException catch (e) {
        // Before patch_274 runs `website` / `is_private` don't exist (42703)
        // or aren't granted (42501). The profile must still open.
        if (!_isMissingColumn(e)) rethrow;
        _hasFollowColumns = false;
        row = await query(_baseColumns);
      }
    } else {
      row = await query(_baseColumns);
    }
    if (row == null) return null;
    return PublicUserProfile.fromJson(row);
  }

  /// The member's own link + private-account setting (patch_274), or null
  /// when those columns don't exist yet — Edit profile then hides the
  /// fields instead of offering settings that can't save.
  static Future<({String? website, bool isPrivate})?> fetchOwnSettings() async {
    final me = _client.auth.currentUser?.id;
    if (me == null || !_hasFollowColumns) return null;
    try {
      final row = await _client
          .from('profiles')
          .select('website, is_private')
          .eq('id', me)
          .maybeSingle();
      if (row == null) return null;
      return (
        website: row['website'] as String?,
        isPrivate: row['is_private'] == true,
      );
    } on PostgrestException catch (e) {
      if (_isMissingColumn(e)) {
        _hasFollowColumns = false;
        return null;
      }
      rethrow;
    }
  }

  /// "example.org" → "https://example.org"; blank → null. Throws
  /// [FormatException] for anything that isn't a plain http(s) link — the
  /// same rule the column's CHECK constraint applies.
  static String? normalizeWebsite(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final withScheme = RegExp(r'^https?://', caseSensitive: false).hasMatch(t)
        ? t
        : 'https://$t';
    final uri = Uri.tryParse(withScheme);
    if (withScheme.length > 200 ||
        withScheme.contains(RegExp(r'\s')) ||
        uri == null ||
        !uri.host.contains('.')) {
      throw const FormatException('Enter a web address like example.org');
    }
    return withScheme;
  }

  static Future<void> saveOwnSettings({
    required String? website,
    required bool isPrivate,
  }) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) throw const AuthException('Sign in to edit your profile.');
    final rows = await _client
        .from('profiles')
        .update({'website': website, 'is_private': isPrivate})
        .eq('id', me)
        .select('id');
    requireChanged(rows, 'profile settings');
  }
}
