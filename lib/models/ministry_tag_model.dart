/// A ministry role or spiritual gift a member can claim on their profile
/// (patch_168). Controlled vocabulary — the client never invents these,
/// it picks from `ministry_tags`.
enum MinistryTagKind {
  ministry('ministry', 'Ministry'),
  gift('gift', 'Spiritual gifts');

  const MinistryTagKind(this.code, this.sectionLabel);
  final String code;
  final String sectionLabel;

  static MinistryTagKind fromCode(String? code) =>
      code == 'gift' ? MinistryTagKind.gift : MinistryTagKind.ministry;
}

class MinistryTag {
  const MinistryTag({
    required this.id,
    required this.code,
    required this.label,
    required this.kind,
    this.sortOrder = 100,
  });

  final int id;
  final String code;
  final String label;
  final MinistryTagKind kind;
  final int sortOrder;

  factory MinistryTag.fromJson(Map<String, dynamic> json) {
    return MinistryTag(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse('${json['id']}') ?? 0,
      code: (json['code'] ?? '') as String,
      label: (json['label'] ?? '') as String,
      kind: MinistryTagKind.fromCode(json['kind'] as String?),
      sortOrder: json['sort_order'] is int
          ? json['sort_order'] as int
          : int.tryParse('${json['sort_order']}') ?? 100,
    );
  }

  @override
  bool operator ==(Object other) => other is MinistryTag && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
