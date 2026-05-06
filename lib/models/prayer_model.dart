class Prayer {
  const Prayer({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.content,
    required this.prayerCount,
    required this.createdAt,
    this.commentCount = 0,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String content;
  final int prayerCount;
  final int commentCount;
  final DateTime createdAt;

  factory Prayer.fromJson(Map<String, dynamic> json) {
    return Prayer(
      id: json['id'].toString(),
      authorId: (json['author_id'] ?? '').toString(),
      authorName: (json['author_name'] ?? 'A friend') as String,
      content: (json['content'] ?? '') as String,
      prayerCount: _readInt(json['prayer_count']),
      commentCount: _readInt(json['comment_count']),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Prayer copyWith({int? prayerCount, int? commentCount}) {
    return Prayer(
      id: id,
      authorId: authorId,
      authorName: authorName,
      content: content,
      prayerCount: prayerCount ?? this.prayerCount,
      commentCount: commentCount ?? this.commentCount,
      createdAt: createdAt,
    );
  }

  static int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}

class PrayerComment {
  const PrayerComment({
    required this.id,
    required this.prayerId,
    required this.authorId,
    required this.authorName,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String prayerId;
  final String authorId;
  final String authorName;
  final String content;
  final DateTime createdAt;

  factory PrayerComment.fromJson(Map<String, dynamic> json) {
    return PrayerComment(
      id: json['id'].toString(),
      prayerId: (json['prayer_id'] ?? '').toString(),
      authorId: (json['author_id'] ?? '').toString(),
      authorName: (json['author_name'] ?? 'A friend') as String,
      content: (json['content'] ?? '') as String,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
