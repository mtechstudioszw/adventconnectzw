/// A hymnal (patch_144). The key is stored on `hymns.collection`; the
/// label is shown in the Hymnal tab's switcher.
class HymnCollection {
  const HymnCollection(this.key, this.label, this.subtitle, {this.family});
  final String key;
  final String label;

  /// The language, shown under the label.
  final String subtitle;

  /// Hymnals that share ONE numbering — hymn 12 is the same song in each.
  /// The 300 Christ in Song hymns were translated into many Southern
  /// African languages with the same numbers, so switching language keeps
  /// the number (owner, 29 Oct 2026). Null for a hymnal with its own
  /// numbering (the SDA Hymnal).
  final String? family;

  static const christInSong = 'christ_in_song';

  static const kristuMunzwiyo = HymnCollection(
    'kristu_munzwiyo',
    'Kristu MuNzwiyo',
    'Shona',
    family: christInSong,
  );
  static const sdaHymnal =
      HymnCollection('sda_hymnal', 'SDA Hymnal', 'English');

  /// English first, then Shona (owner, 29 Oct 2026). Each hymnal keeps
  /// its OWN numbering — Kristu MuNzwiyo 40 is not SDA Hymnal 40 — so a
  /// number is never shown without the hymnal it belongs to (see
  /// [Hymn.reference]).
  static const all = [sdaHymnal, kristuMunzwiyo];

  /// Christ in Song editions in other languages. NOT in the app: their
  /// words belong to the translators and the unions that publish them, so
  /// each is added only with permission. Listed so the switcher can say
  /// so honestly, and so an admin can load one without an app update —
  /// a collection appears in the switcher as soon as it has hymns.
  static const planned = [
    HymnCollection('cis_ndebele', 'Ndebele', 'isiNdebele',
        family: christInSong),
    HymnCollection('cis_zulu', 'Zulu', 'isiZulu', family: christInSong),
    HymnCollection('cis_xhosa', 'Xhosa', 'isiXhosa', family: christInSong),
    HymnCollection('cis_tswana', 'Tswana', 'Setswana', family: christInSong),
    HymnCollection('cis_sotho', 'Sotho', 'Sesotho', family: christInSong),
    HymnCollection('cis_chichewa', 'Chichewa', 'Chichewa',
        family: christInSong),
    HymnCollection('cis_venda', 'Venda', 'Tshivenda', family: christInSong),
    HymnCollection('cis_tonga', 'Tonga', 'Chitonga', family: christInSong),
    HymnCollection('cis_tsonga', 'Tsonga', 'Xitsonga', family: christInSong),
  ];

  /// Every hymnal the app knows about, available or not.
  static const known = [...all, ...planned];

  static HymnCollection fromKey(String? key) =>
      known.firstWhere((c) => c.key == key, orElse: () => kristuMunzwiyo);

  /// The hymnals that actually have hymns, in [known] order.
  static List<HymnCollection> availableIn(Iterable<Hymn> hymns) {
    final keys = {for (final h in hymns) h.collection};
    return [
      for (final c in known)
        if (keys.contains(c.key)) c,
    ];
  }
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
