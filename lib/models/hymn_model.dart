/// A single hymn in the structured Hymnal (patch_129 `hymns`). Searchable by
/// number, title and lyrics; displayed as text with adjustable font size.
class Hymn {
  const Hymn({
    required this.id,
    required this.title,
    required this.lyrics,
    required this.language,
    this.number,
    this.category,
  });

  final String id;
  final int? number;
  final String title;
  final String lyrics;
  final String language;
  final String? category;

  /// "123 · Title" when numbered, else just the title.
  String get displayTitle => number != null ? '$number · $title' : title;

  factory Hymn.fromJson(Map<String, dynamic> json) {
    return Hymn(
      id: json['id'].toString(),
      number: (json['number'] as num?)?.toInt(),
      title: (json['title'] ?? 'Untitled').toString(),
      lyrics: (json['lyrics'] ?? '').toString(),
      language: (json['language'] ?? 'Shona').toString(),
      category: json['category'] as String?,
    );
  }
}
