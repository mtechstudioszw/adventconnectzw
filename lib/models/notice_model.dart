/// Community notices posted from the Home tab. Mirrors Table 27.
class Notice {
  const Notice({
    required this.id,
    required this.postedBy,
    required this.title,
    required this.body,
    required this.category,
    required this.createdAt,
    this.posterName,
  });

  final String id;
  final String postedBy;
  final String title;
  final String body;
  final String category;
  final DateTime createdAt;
  final String? posterName;

  factory Notice.fromJson(Map<String, dynamic> json) {
    final poster = json['profiles'];
    final posterMap = poster is Map<String, dynamic> ? poster : null;
    return Notice(
      id: json['id'].toString(),
      postedBy: (json['posted_by'] ?? '').toString(),
      title: (json['title'] ?? '') as String,
      body: (json['body'] ?? '') as String,
      category: (json['category'] ?? 'general') as String,
      posterName: posterMap?['full_name'] as String?,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class NoticeCategory {
  const NoticeCategory({
    required this.id,
    required this.label,
    required this.icon,
  });
  final String id;
  final String label;
  final String icon;

  static const all = [
    NoticeCategory(id: 'general', label: 'General notice', icon: '📣'),
    NoticeCategory(id: 'lost_and_found', label: 'Lost & found', icon: '🔎'),
    NoticeCategory(id: 'accommodation', label: 'Accommodation', icon: '🏠'),
    NoticeCategory(id: 'transport', label: 'Transport', icon: '🚐'),
    NoticeCategory(id: 'congratulations', label: 'Congratulations', icon: '🎉'),
    NoticeCategory(id: 'other', label: 'Other', icon: '✨'),
  ];

  static String labelFor(String id) {
    return all
        .firstWhere(
          (c) => c.id == id,
          orElse: () => const NoticeCategory(
            id: 'other',
            label: 'Other',
            icon: '✨',
          ),
        )
        .label;
  }
}
