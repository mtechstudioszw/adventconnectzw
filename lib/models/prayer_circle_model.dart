/// A named, invite-only group a prayer can be scoped to (patch_170).
///
/// Membership is not carried on the model: the list screen needs counts,
/// the picker needs names, and neither wants to pull every member row on
/// every prayer. [memberCount] is populated where the query asks for it.
class PrayerCircle {
  const PrayerCircle({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.createdAt,
    this.memberCount = 0,
  });

  final String id;
  final String name;
  final String ownerId;
  final DateTime createdAt;
  final int memberCount;

  factory PrayerCircle.fromJson(Map<String, dynamic> json) {
    // PostgREST returns an aggregate embed as a one-element list of
    // {count: n}; tolerate both that and a plain integer.
    int count = 0;
    final raw = json['member_count'] ?? json['prayer_circle_members'];
    if (raw is int) {
      count = raw;
    } else if (raw is List && raw.isNotEmpty) {
      final first = raw.first;
      if (first is Map && first['count'] is int) count = first['count'] as int;
    } else if (raw is Map && raw['count'] is int) {
      count = raw['count'] as int;
    }
    return PrayerCircle(
      id: json['id'].toString(),
      name: (json['name'] ?? '') as String,
      ownerId: (json['owner_id'] ?? '').toString(),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
              DateTime.now(),
      memberCount: count,
    );
  }

  PrayerCircle copyWith({String? name, int? memberCount}) => PrayerCircle(
        id: id,
        name: name ?? this.name,
        ownerId: ownerId,
        createdAt: createdAt,
        memberCount: memberCount ?? this.memberCount,
      );
}

/// A member of a circle, reduced to what the manage sheet renders.
class PrayerCircleMember {
  const PrayerCircleMember({
    required this.userId,
    required this.fullName,
    this.photoUrl,
  });

  final String userId;
  final String fullName;
  final String? photoUrl;
}
