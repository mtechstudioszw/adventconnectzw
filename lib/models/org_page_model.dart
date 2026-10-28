import 'package:flutter/material.dart';

/// Kinds of organization Page (patch_275). Churches are NOT one of them:
/// they keep their own directory and appointment-letter verification, and
/// the database refuses a 'church' Page so nobody can sidestep that.
enum PageCategory { ministry, school, community, business }

extension PageCategoryX on PageCategory {
  String get wire => name;

  String get label => switch (this) {
    PageCategory.ministry => 'Ministry',
    PageCategory.school => 'School',
    PageCategory.community => 'Community organization',
    PageCategory.business => 'Business',
  };

  /// Short form for chips.
  String get shortLabel => switch (this) {
    PageCategory.ministry => 'Ministries',
    PageCategory.school => 'Schools',
    PageCategory.community => 'Community',
    PageCategory.business => 'Businesses',
  };

  IconData get icon => switch (this) {
    PageCategory.ministry => Icons.volunteer_activism_outlined,
    PageCategory.school => Icons.school_outlined,
    PageCategory.community => Icons.groups_outlined,
    PageCategory.business => Icons.storefront_outlined,
  };

  static PageCategory fromWire(String? s) => PageCategory.values.firstWhere(
    (c) => c.name == s,
    orElse: () => PageCategory.community,
  );
}

/// An organization Page. Named OrgPage so it never collides with Flutter's
/// own `Page` (navigator pages).
class OrgPage {
  const OrgPage({
    required this.id,
    required this.name,
    required this.category,
    this.description,
    this.logoUrl,
    this.coverUrl,
    this.city,
    this.country,
    this.serviceArea,
    this.contactEmail,
    this.contactPhone,
    this.website,
    this.isVerified = false,
    this.isHidden = false,
    this.moderationReason,
    this.createdAt,
  });

  final String id;
  final String name;
  final PageCategory category;
  final String? description;
  final String? logoUrl;
  final String? coverUrl;
  final String? city;
  final String? country;
  final String? serviceArea;
  final String? contactEmail;
  final String? contactPhone;
  final String? website;

  /// Official organization verification — set only by the super admin
  /// after review. Never bought.
  final bool isVerified;

  /// Hidden by the moderators; only its admins still see it.
  final bool isHidden;
  final String? moderationReason;
  final DateTime? createdAt;

  String get initials {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    return words.take(2).map((w) => w[0].toUpperCase()).join();
  }

  static String? _s(Object? v) {
    final t = v?.toString().trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  factory OrgPage.fromJson(Map<String, dynamic> j) => OrgPage(
    id: j['id'].toString(),
    name: (_s(j['name']) ?? 'Page'),
    category: PageCategoryX.fromWire(j['category'] as String?),
    description: _s(j['description']),
    logoUrl: _s(j['logo_url']),
    coverUrl: _s(j['cover_url']),
    city: _s(j['city']),
    country: _s(j['country']),
    serviceArea: _s(j['service_area']),
    contactEmail: _s(j['contact_email']),
    contactPhone: _s(j['contact_phone']),
    website: _s(j['website']),
    isVerified: j['is_verified'] == true,
    isHidden: j['status'] == 'hidden',
    moderationReason: _s(j['moderation_reason']),
    createdAt: DateTime.tryParse(j['created_at']?.toString() ?? ''),
  );

  /// The editable fields, as written on create/update. Verification,
  /// status and ownership are the server's (guard trigger) and never sent.
  Map<String, dynamic> toWrite() => {
    'name': name.trim(),
    'category': category.wire,
    'description': description,
    'logo_url': logoUrl,
    'cover_url': coverUrl,
    'city': city,
    'country': country,
    'service_area': serviceArea,
    'contact_email': contactEmail,
    'contact_phone': contactPhone,
    'website': website,
  };
}

/// Follower count and the viewer's relationship to a Page.
class PageStats {
  const PageStats({
    required this.followers,
    required this.iFollow,
    this.myRole,
  });
  final int followers;
  final bool iFollow;

  /// 'owner', 'editor' or null.
  final String? myRole;
  bool get canEdit => myRole != null;
  bool get isOwner => myRole == 'owner';

  static const empty = PageStats(followers: 0, iFollow: false);
}

/// One admin of a Page, for the management screen.
class PageAdmin {
  const PageAdmin({
    required this.userId,
    required this.fullName,
    required this.role,
    this.username,
    this.photoUrl,
  });
  final String userId;
  final String fullName;
  final String role;
  final String? username;
  final String? photoUrl;

  factory PageAdmin.fromJson(Map<String, dynamic> j) => PageAdmin(
    userId: j['user_id'].toString(),
    fullName: (j['full_name'] as String?)?.trim().isNotEmpty == true
        ? (j['full_name'] as String).trim()
        : 'Member',
    role: (j['role'] as String?) ?? 'editor',
    username: j['username'] as String?,
    photoUrl: j['profile_photo_url'] as String?,
  );
}
