/// Editorial Advent News item — distinct from user posts. Published
/// by approved church / conference admins (or service role). The
/// home screen surfaces these in a dedicated card; the dedicated
/// /news route hosts a full feed with category chips.
enum NewsCategory {
  trending('trending', 'Trending'),
  announcement('announcement', 'Announcements'),
  globalSda('global_sda', 'Global SDA'),
  eventRecap('event_recap', 'Event recap'),
  spiritual('spiritual', 'Spiritual'),
  general('general', 'General');

  const NewsCategory(this.code, this.label);
  final String code;
  final String label;

  static NewsCategory fromCode(String? code) {
    for (final c in NewsCategory.values) {
      if (c.code == code) return c;
    }
    return NewsCategory.general;
  }
}

class AdventNews {
  const AdventNews({
    required this.id,
    required this.title,
    required this.summary,
    required this.publishedAt,
    this.body,
    this.coverPhotoUrl,
    this.category = NewsCategory.general,
    this.sourceUrl,
    this.sourceLabel,
    this.authorName,
    this.isPinned = false,
  });

  final String id;
  final String title;
  final String summary;
  final String? body;
  final String? coverPhotoUrl;
  final NewsCategory category;
  /// Optional outbound link to the original source (e.g.
  /// Adventist News Network article, conference press release).
  final String? sourceUrl;
  /// Display name for the source (e.g. "ANN", "ZUC press").
  final String? sourceLabel;
  final String? authorName;
  final bool isPinned;
  final DateTime publishedAt;

  factory AdventNews.fromJson(Map<String, dynamic> json) {
    final author = json['profiles'];
    final authorMap = author is Map<String, dynamic> ? author : null;
    return AdventNews(
      id: json['id'].toString(),
      title: (json['title'] ?? '') as String,
      summary: (json['summary'] ?? '') as String,
      body: json['body'] as String?,
      coverPhotoUrl: json['cover_photo_url'] as String?,
      category: NewsCategory.fromCode(json['category'] as String?),
      sourceUrl: json['source_url'] as String?,
      sourceLabel: json['source_label'] as String?,
      authorName: (authorMap?['full_name'] as String?)?.trim(),
      isPinned: json['is_pinned'] == true,
      publishedAt:
          DateTime.tryParse(json['published_at']?.toString() ?? '') ??
              DateTime.tryParse(json['created_at']?.toString() ?? '') ??
              DateTime.now(),
    );
  }
}
