import 'package:supabase_flutter/supabase_flutter.dart';

/// Snapshot of another user's public profile fields. Mirrors what the
/// profiles row exposes via RLS — `is_discoverable=false` users get a
/// cut-down version on the client side.
class PublicUserProfile {
  const PublicUserProfile({
    required this.id,
    required this.fullName,
    required this.isDiscoverable,
    required this.isVerified,
    required this.isBusiness,
    this.profilePhotoUrl,
    this.coverPhotoUrl,
    this.bio,
    this.province,
    this.city,
    this.dateOfBirth,
    this.joinedAt,
    this.churchName,
    this.showAge = true,
  });

  final String id;
  final String fullName;
  final String? profilePhotoUrl;
  final String? coverPhotoUrl;
  final String? bio;
  final String? province;
  final String? city;
  final DateTime? dateOfBirth;
  final DateTime? joinedAt;
  final String? churchName;
  final bool isDiscoverable;
  final bool isVerified;
  final bool isBusiness;
  final bool showAge;

  int? get age {
    if (dateOfBirth == null) return null;
    final now = DateTime.now();
    var a = now.year - dateOfBirth!.year;
    final hadBirthday = now.month > dateOfBirth!.month ||
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
      isBusiness: json['is_business'] == true,
      showAge: json['show_age'] != false,
    );
  }
}

/// Read other users' profiles. Service-side so route handlers don't
/// have to know how to spell the embed.
class UserProfileService {
  UserProfileService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static Future<PublicUserProfile?> fetch(String userId) async {
    final row = await _client
        .from('profiles')
        .select(
          'id, full_name, profile_photo_url, cover_photo_url, bio, '
          'province, city, date_of_birth, created_at, '
          'is_discoverable, is_verified, is_business, show_age, '
          'churches(name)',
        )
        .eq('id', userId)
        .maybeSingle();
    if (row == null) return null;
    return PublicUserProfile.fromJson(row);
  }
}
