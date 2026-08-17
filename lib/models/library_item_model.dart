/// A single item in the in-app Library (patch_128 `library_items`).
///
/// `kind` is one of: 'hymnal', 'music', 'egw_book'. The Bible is a bundled
/// offline asset and is NOT represented here.
class LibraryItem {
  const LibraryItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.fileUrl,
    this.author,
    this.description,
    this.language,
    this.coverUrl,
    this.durationSeconds,
    this.epubUrl,
  });

  final String id;
  final String kind;
  final String title;

  /// PDF (hymnal / egw_book) or audio (music) URL in the public `library`
  /// storage bucket.
  final String fileUrl;
  final String? author;
  final String? description;
  final String? language;
  final String? coverUrl;

  /// Track length for `music` items; null otherwise.
  final int? durationSeconds;

  /// EPUB in the same bucket, when one exists.
  ///
  /// This is what unlocks the reflowable reader: the EPUB carries text,
  /// the canonical page numbers inline and pre-tagged scripture, none of
  /// which a rendered PDF page can give. Null-safe on purpose — the column
  /// may not be present yet, and every reader path falls back to the PDF.
  final String? epubUrl;

  bool get isPdf => kind == 'hymnal' || kind == 'egw_book';
  bool get isAudio => kind == 'music';

  /// True when this book can open in the reflowable reader.
  bool get hasEpub => (epubUrl ?? '').isNotEmpty;

  factory LibraryItem.fromJson(Map<String, dynamic> json) {
    return LibraryItem(
      id: json['id'].toString(),
      kind: (json['kind'] ?? '').toString(),
      title: (json['title'] ?? 'Untitled').toString(),
      fileUrl: (json['file_url'] ?? '').toString(),
      author: json['author'] as String?,
      description: json['description'] as String?,
      language: json['language'] as String?,
      coverUrl: json['cover_url'] as String?,
      durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
      // patch_206. Read defensively: an older client reading a newer row is
      // fine either way, and a build that predates the column must not
      // throw on its absence.
      epubUrl: json['epub_url'] as String?,
    );
  }
}
