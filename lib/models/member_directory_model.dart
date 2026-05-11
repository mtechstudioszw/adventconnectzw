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
    );
  }
}
