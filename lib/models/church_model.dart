class Church {
  const Church({
    required this.id,
    required this.name,
    required this.city,
    required this.membersCount,
    this.coverPhotoUrl,
    this.profilePhotoUrl,
    this.description,
    this.address,
    this.suburb,
    this.pastorName,
    this.foundedYear,
    this.contactPhone,
    this.contactEmail,
    this.isVerified = false,
    this.createdAt,
    this.latitude,
    this.longitude,
    this.province,
    this.conference,
  });

  final String id;
  final String name;
  final String city;
  final int membersCount;
  final String? coverPhotoUrl;
  /// Square church logo / avatar (`churches.profile_photo_url`). Shown as
  /// the round avatar on the church profile; distinct from the wide
  /// [coverPhotoUrl] banner.
  final String? profilePhotoUrl;
  final String? description;
  final String? address;
  /// Suburb / neighbourhood (`churches.suburb`). Editable by the church
  /// admin; folded into the address line on the profile.
  final String? suburb;
  final String? pastorName;
  final int? foundedYear;
  final String? contactPhone;
  final String? contactEmail;
  final bool isVerified;
  final DateTime? createdAt;
  final double? latitude;
  final double? longitude;
  /// Zimbabwe province this church sits in. Drives the "My Province"
  /// filter chip — matched against the viewer's profile province.
  final String? province;
  /// SDA conference (e.g. "North Zimbabwe Conference"). Surfaced in
  /// the conference dropdown filter per master reference Part 15.
  final String? conference;

  bool get hasLocation => latitude != null && longitude != null;

  factory Church.fromJson(Map<String, dynamic> json) {
    return Church(
      id: json['id'].toString(),
      name: (json['name'] ?? '') as String,
      city: (json['city'] ?? '') as String,
      // The DB column is `follower_count` (set by the
      // bump_church_follower_count trigger in schema.sql). Earlier
      // dev iterations called it `members_count` — read both so the
      // model stays compatible while old caches drain. Without this
      // the count never shows on church_details and the optimistic
      // +1 in _toggleFollow never persists across reloads.
      membersCount: _readInt(json['follower_count'] ?? json['members_count']),
      coverPhotoUrl: json['cover_photo_url'] as String?,
      profilePhotoUrl: json['profile_photo_url'] as String?,
      description: json['description'] as String?,
      address: json['address'] as String?,
      suburb: json['suburb'] as String?,
      pastorName: json['pastor_name'] as String?,
      foundedYear: json['founded_year'] is int
          ? json['founded_year'] as int
          : int.tryParse('${json['founded_year']}'),
      // Live columns are `phone` / `email`; older code/caches used
      // `contact_phone` / `contact_email`. Read whichever is present so
      // the details + edit screens actually show the contact info.
      contactPhone: (json['phone'] ?? json['contact_phone']) as String?,
      contactEmail: (json['email'] ?? json['contact_email']) as String?,
      // Live column is `verified`; keep `is_verified` as a fallback for
      // older cached rows.
      isVerified: json['verified'] == true || json['is_verified'] == true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      latitude: _readDouble(json['latitude']),
      longitude: _readDouble(json['longitude']),
      province: (json['province'] as String?)?.trim().isNotEmpty == true
          ? (json['province'] as String).trim()
          : null,
      conference: (json['conference'] as String?)?.trim().isNotEmpty == true
          ? (json['conference'] as String).trim()
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'city': city,
        // Write back under the canonical column name so a cache
        // round-trip stays consistent with what fromJson reads.
        'follower_count': membersCount,
        'cover_photo_url': coverPhotoUrl,
        'profile_photo_url': profilePhotoUrl,
        'description': description,
        'address': address,
        'suburb': suburb,
        'pastor_name': pastorName,
        'founded_year': foundedYear,
        'phone': contactPhone,
        'email': contactEmail,
        'verified': isVerified,
        'created_at': createdAt?.toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'province': province,
        'conference': conference,
      };

  Church copyWith({
    int? membersCount,
    bool? isVerified,
    String? coverPhotoUrl,
    String? profilePhotoUrl,
    String? description,
    String? address,
    String? suburb,
    String? city,
    String? pastorName,
    int? foundedYear,
    String? contactPhone,
    String? contactEmail,
    double? latitude,
    double? longitude,
  }) {
    return Church(
      id: id,
      name: name,
      city: city ?? this.city,
      membersCount: membersCount ?? this.membersCount,
      coverPhotoUrl: coverPhotoUrl ?? this.coverPhotoUrl,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      description: description ?? this.description,
      address: address ?? this.address,
      suburb: suburb ?? this.suburb,
      pastorName: pastorName ?? this.pastorName,
      foundedYear: foundedYear ?? this.foundedYear,
      contactPhone: contactPhone ?? this.contactPhone,
      contactEmail: contactEmail ?? this.contactEmail,
      isVerified: isVerified ?? this.isVerified,
      createdAt: createdAt,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      province: province,
      conference: conference,
    );
  }

  static int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  static double? _readDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }
}
