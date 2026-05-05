class Church {
  const Church({
    required this.id,
    required this.name,
    required this.city,
    required this.membersCount,
    this.coverPhotoUrl,
    this.description,
    this.address,
    this.pastorName,
    this.foundedYear,
    this.contactPhone,
    this.contactEmail,
    this.isVerified = false,
    this.createdAt,
  });

  final String id;
  final String name;
  final String city;
  final int membersCount;
  final String? coverPhotoUrl;
  final String? description;
  final String? address;
  final String? pastorName;
  final int? foundedYear;
  final String? contactPhone;
  final String? contactEmail;
  final bool isVerified;
  final DateTime? createdAt;

  factory Church.fromJson(Map<String, dynamic> json) {
    return Church(
      id: json['id'].toString(),
      name: (json['name'] ?? '') as String,
      city: (json['city'] ?? '') as String,
      membersCount: _readInt(json['members_count']),
      coverPhotoUrl: json['cover_photo_url'] as String?,
      description: json['description'] as String?,
      address: json['address'] as String?,
      pastorName: json['pastor_name'] as String?,
      foundedYear: json['founded_year'] is int
          ? json['founded_year'] as int
          : int.tryParse('${json['founded_year']}'),
      contactPhone: json['contact_phone'] as String?,
      contactEmail: json['contact_email'] as String?,
      isVerified: json['is_verified'] == true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'city': city,
        'members_count': membersCount,
        'cover_photo_url': coverPhotoUrl,
        'description': description,
        'address': address,
        'pastor_name': pastorName,
        'founded_year': foundedYear,
        'contact_phone': contactPhone,
        'contact_email': contactEmail,
        'is_verified': isVerified,
        'created_at': createdAt?.toIso8601String(),
      };

  Church copyWith({
    int? membersCount,
    bool? isVerified,
  }) {
    return Church(
      id: id,
      name: name,
      city: city,
      membersCount: membersCount ?? this.membersCount,
      coverPhotoUrl: coverPhotoUrl,
      description: description,
      address: address,
      pastorName: pastorName,
      foundedYear: foundedYear,
      contactPhone: contactPhone,
      contactEmail: contactEmail,
      isVerified: isVerified ?? this.isVerified,
      createdAt: createdAt,
    );
  }

  static int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}
