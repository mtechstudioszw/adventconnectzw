/// Mirrors Table 21 (member_directory). One row per user who opted
/// into the public member directory. Joins to profiles for display
/// name/photo when listing.
class MemberDirectoryEntry {
  const MemberDirectoryEntry({
    required this.id,
    required this.userId,
    required this.isVisible,
    this.profession,
    this.skills,
    this.churchId,
    this.churchName,
    this.province,
    this.city,
    this.bio,
    this.fullName,
    this.profilePhotoUrl,
    this.createdAt,
    this.isVerified = false,
    this.suggestionReason,
    this.allowsFollowers = false,
  });

  final String id;
  final String userId;
  final bool isVisible;
  final String? profession;
  final String? skills;
  final String? churchId;
  final String? churchName;
  final String? province;
  final String? city;
  final String? bio;
  final String? fullName;
  final String? profilePhotoUrl;
  final DateTime? createdAt;

  /// Cosmetic gold tick — super admin or approved church admin (patch_134).
  final bool isVerified;

  /// Why this person is being suggested — "Goes to your church", "Also in
  /// Bulawayo". Computed by [DirectoryService.fetchSuggestedMembers]
  /// against the VIEWER, so it can't be derived from this row alone.
  ///
  /// The home cards show exactly one reason. Null when the person made
  /// the list only because they're new and discoverable, in which case
  /// the card says nothing rather than inventing something.
  final String? suggestionReason;

  /// They turned followers on (patch_287): offered with Follow in Home's
  /// "Leaders to follow" groups instead of Add friend.
  final bool allowsFollowers;

  /// Same person, tagged with why they're being suggested.
  MemberDirectoryEntry withReason(String reason) => MemberDirectoryEntry(
        id: id,
        userId: userId,
        isVisible: isVisible,
        profession: profession,
        skills: skills,
        churchId: churchId,
        churchName: churchName,
        province: province,
        city: city,
        bio: bio,
        fullName: fullName,
        profilePhotoUrl: profilePhotoUrl,
        createdAt: createdAt,
        isVerified: isVerified,
        suggestionReason: reason,
        allowsFollowers: allowsFollowers,
      );

  factory MemberDirectoryEntry.fromJson(Map<String, dynamic> json) {
    // The list endpoint joins the profiles row via Supabase's embed
    // syntax, so we read either the flat fields (own profile) or the
    // nested `profiles` object (other people's profiles).
    final profile = json['profiles'];
    final profileMap = profile is Map<String, dynamic> ? profile : null;
    final church = json['churches'];
    final churchMap = church is Map<String, dynamic> ? church : null;
    return MemberDirectoryEntry(
      id: json['id'].toString(),
      userId: (json['user_id'] ?? '').toString(),
      isVisible: json['is_visible'] != false,
      profession: json['profession'] as String?,
      skills: json['skills'] as String?,
      churchId: json['church_id']?.toString(),
      churchName: churchMap?['name'] as String?,
      province: json['province'] as String?,
      city: json['city'] as String?,
      bio: json['bio'] as String?,
      fullName: profileMap?['full_name'] as String?,
      profilePhotoUrl: profileMap?['profile_photo_url'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      isVerified: json['is_verified'] == true ||
          profileMap?['is_verified'] == true,
    );
  }

  /// Flat form for Home's offline cache — round-trips through
  /// [MemberDirectoryEntry.fromCacheJson], reason included.
  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'user_id': userId,
        'church_id': churchId,
        'church_name': churchName,
        'province': province,
        'city': city,
        'full_name': fullName,
        'profile_photo_url': profilePhotoUrl,
        'is_verified': isVerified,
        'reason': suggestionReason,
        'follows': allowsFollowers,
      };

  factory MemberDirectoryEntry.fromCacheJson(Map<String, dynamic> j) =>
      MemberDirectoryEntry(
        id: '${j['id']}',
        userId: '${j['user_id']}',
        isVisible: true,
        churchId: j['church_id'] as String?,
        churchName: j['church_name'] as String?,
        province: j['province'] as String?,
        city: j['city'] as String?,
        fullName: j['full_name'] as String?,
        profilePhotoUrl: j['profile_photo_url'] as String?,
        isVerified: j['is_verified'] == true,
        suggestionReason: j['reason'] as String?,
        allowsFollowers: j['follows'] == true,
      );
}
