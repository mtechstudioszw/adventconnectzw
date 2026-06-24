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

  bool get isPdf => kind == 'hymnal' || kind == 'egw_book';
  bool get isAudio => kind == 'music';

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
    );
  }
}
