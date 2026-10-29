/// The two hymnal collections (patch_144). The key is stored on
/// `hymns.collection`; the label is shown in the Hymnal tab's switcher.
class HymnCollection {
  const HymnCollection(this.key, this.label, this.subtitle);
  final String key;
  final String label;
  final String subtitle;

  static const kristuMunzwiyo =
      HymnCollection('kristu_munzwiyo', 'Kristu MuNzwiyo', 'Shona');
  static const sdaHymnal =
      HymnCollection('sda_hymnal', 'SDA Hymnal', 'English');

  /// English first, then Shona (owner, 29 Oct 2026). Each hymnal keeps
  /// its OWN numbering — Kristu MuNzwiyo 40 is not SDA Hymnal 40 — so a
  /// number is never shown without the hymnal it belongs to (see
  /// [Hymn.reference]).
  static const all = [sdaHymnal, kristuMunzwiyo];

  static HymnCollection fromKey(String? key) =>
      all.firstWhere((c) => c.key == key, orElse: () => kristuMunzwiyo);
}

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
    this.collection = 'kristu_munzwiyo',
  });

  final String id;
  final int? number;
  final String title;
  final String lyrics;
  final String language;
  final String? category;

  /// Which hymnal this belongs to: 'kristu_munzwiyo' | 'sda_hymnal' (patch_144).
  final String collection;

  /// "SDA Hymnal 40" / "Kristu MuNzwiyo 40" — the number with its book,
  /// because the two hymnals number independently.
  String get reference {
    final book = HymnCollection.fromKey(collection).label;
    return number == null ? book : '$book $number';
  }

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
      collection: (json['collection'] ?? 'kristu_munzwiyo').toString(),
    );
  }
}
