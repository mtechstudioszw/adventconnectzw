/// Coarse topical category for a prayer request. Keeps the screen
/// from feeling like an undifferentiated firehose as the corpus
/// grows. Persisted in `prayers.category` (patch_020) — any value
/// outside the seven allowed codes is rejected by the DB CHECK.
enum PrayerCategory {
  healing('healing', 'Healing'),
  family('family', 'Family'),
  spiritual('spiritual', 'Spiritual'),
  provision('provision', 'Provision'),
  thanksgiving('thanksgiving', 'Thanksgiving'),
  ministry('ministry', 'Ministry'),
  other('other', 'Other');

  const PrayerCategory(this.code, this.label);
  final String code;
  final String label;

  static PrayerCategory fromCode(String? code) {
    for (final c in PrayerCategory.values) {
      if (c.code == code) return c;
    }
    return PrayerCategory.other;
  }
}

class Prayer {
  const Prayer({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.content,
    required this.prayerCount,
    required this.createdAt,
    this.commentCount = 0,
    this.category = PrayerCategory.other,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String content;
  final int prayerCount;
  final int commentCount;
  final DateTime createdAt;
  final PrayerCategory category;

  factory Prayer.fromJson(Map<String, dynamic> json) {
    return Prayer(
      id: json['id'].toString(),
      authorId: (json['author_id'] ?? '').toString(),
      authorName: (json['author_name'] ?? 'A friend') as String,
      content: (json['content'] ?? '') as String,
      prayerCount: _readInt(json['prayer_count']),
      commentCount: _readInt(json['comment_count']),
      category: PrayerCategory.fromCode(json['category'] as String?),
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
      category: category,
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
    this.authorPhotoUrl,
    this.parentCommentId,
    this.replies = const [],
  });

  final String id;
  final String prayerId;
  final String authorId;
  final String authorName;
  final String? authorPhotoUrl;
  final String content;
  final DateTime createdAt;
  // patch_035: NULL for top-level comments; otherwise the id of the
  // comment this row replies to. Threading is rendered one level
  // deep in the UI — replies-to-replies flatten to siblings.
  final String? parentCommentId;
  // Populated by [PrayerComment.buildTree] — direct children only.
  final List<PrayerComment> replies;

  bool get isReply => parentCommentId != null;

  PrayerComment copyWith({List<PrayerComment>? replies}) {
    return PrayerComment(
      id: id,
      prayerId: prayerId,
      authorId: authorId,
      authorName: authorName,
      authorPhotoUrl: authorPhotoUrl,
      content: content,
      createdAt: createdAt,
      parentCommentId: parentCommentId,
      replies: replies ?? this.replies,
    );
  }

  factory PrayerComment.fromJson(Map<String, dynamic> json) {
    return PrayerComment(
      id: json['id'].toString(),
      prayerId: (json['prayer_id'] ?? '').toString(),
      authorId: (json['author_id'] ?? '').toString(),
      authorName: (json['author_name'] ?? 'A friend') as String,
      authorPhotoUrl: json['author_photo_url'] as String?,
      content: (json['content'] ?? '') as String,
      parentCommentId: json['parent_comment_id']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  /// Re-shape a flat comment list into a 1-level tree: top-level
  /// comments keep their server order, replies group under their
  /// top-level ancestor. Deeper nesting flattens to siblings.
  static List<PrayerComment> buildTree(List<PrayerComment> flat) {
    final byId = {for (final c in flat) c.id: c};
    final repliesByRoot = <String, List<PrayerComment>>{};
    final roots = <PrayerComment>[];

    String? rootIdOf(PrayerComment c) {
      var cursor = c;
      var hops = 0;
      while (cursor.parentCommentId != null && hops < 16) {
        final parent = byId[cursor.parentCommentId];
        if (parent == null) return null;
        if (parent.parentCommentId == null) return parent.id;
        cursor = parent;
        hops += 1;
      }
      return null;
    }

    for (final c in flat) {
      if (c.parentCommentId == null) {
        roots.add(c);
      } else {
        final root = rootIdOf(c);
        if (root == null) {
          roots.add(c);
        } else {
          repliesByRoot.putIfAbsent(root, () => []).add(c);
        }
      }
    }

    return roots
        .map((r) => r.copyWith(replies: repliesByRoot[r.id] ?? const []))
        .toList();
  }
}
