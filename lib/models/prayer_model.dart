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

/// A person who prayed, reduced to what the card actually renders — a
/// first name and an optional avatar. Deliberately not the full profile:
/// this list is batch-loaded for every visible card, so it stays cheap.
class PrayingUserRef {
  const PrayingUserRef({
    required this.userId,
    required this.fullName,
    this.photoUrl,
  });

  final String userId;
  final String fullName;
  final String? photoUrl;

  /// "Rutendo Moyo" → "Rutendo". The summary line names people the way
  /// someone would say it out loud, not the way the directory stores it.
  String get firstName {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return '';
    final space = trimmed.indexOf(' ');
    return space == -1 ? trimmed : trimmed.substring(0, space);
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
    this.authorPhotoUrl,
    this.authorIsVerified = false,
    this.commentCount = 0,
    this.category = PrayerCategory.other,
    this.isMine = false,
    this.isAnonymous = false,
    this.isAnswered = false,
    this.answeredAt,
    this.testimony,
    this.prayedBy = const [],
  });

  final String id;
  final String authorId;
  final String authorName;
  final String? authorPhotoUrl;
  final bool authorIsVerified;
  final String content;
  final int prayerCount;
  final int commentCount;
  final DateTime createdAt;
  final PrayerCategory category;

  /// True when the signed-in user posted this prayer — computed server-side
  /// BEFORE the anonymous mask, so the owner can still delete/edit a prayer
  /// they posted anonymously (the mask only hides them from others).
  final bool isMine;

  /// True when this prayer was posted anonymously (author hidden from others).
  final bool isAnonymous;

  /// `prayers.is_answered` — has existed since the base schema; patch_006
  /// fires a notification on its FALSE → TRUE transition. Only the author
  /// can flip it (RLS gates UPDATE to `author_id = auth.uid()`).
  final bool isAnswered;

  /// patch_167. Stamped by a BEFORE UPDATE trigger on the flag transition,
  /// so it is non-null exactly when [isAnswered] is true. The Answered
  /// filter sorts on this, not on [createdAt] — a March request answered
  /// yesterday belongs at the top.
  final DateTime? answeredAt;

  /// patch_167. The author's short account of how it was answered. Shown
  /// on the card in place of a second request.
  final String? testimony;

  /// First few people who prayed, newest first — for the
  /// "Rutendo, Blessing and 41 others prayed" line. Batch-loaded by
  /// [PrayerService.fetchPrayedByPreview]; empty until it resolves, and
  /// the line falls back to the bare count.
  final List<PrayingUserRef> prayedBy;

  /// Names only, capped — the card renders at most two before "and N others".
  String? prayedBySummary() {
    if (prayedBy.isEmpty) return null;
    final names = prayedBy
        .map((p) => p.firstName)
        .where((n) => n.isNotEmpty)
        .toList();
    if (names.isEmpty) return null;
    // `prayerCount` is authoritative (DB trigger); prayedBy is a capped
    // preview, so derive the remainder from the count, never the list.
    final others = prayerCount - names.length.clamp(0, prayerCount);
    if (names.length == 1) {
      return others <= 0
          ? '${names[0]} prayed'
          : '${names[0]} and $others ${others == 1 ? "other" : "others"} prayed';
    }
    final lead = '${names[0]}, ${names[1]}';
    return others <= 0
        ? '$lead prayed'
        : '$lead and $others ${others == 1 ? "other" : "others"} prayed';
  }

  factory Prayer.fromJson(Map<String, dynamic> json) {
    return Prayer(
      id: json['id'].toString(),
      authorId: (json['author_id'] ?? '').toString(),
      authorName: (json['author_name'] ?? 'A friend') as String,
      authorPhotoUrl: json['author_photo_url'] as String?,
      authorIsVerified: json['author_is_verified'] == true,
      content: (json['content'] ?? '') as String,
      prayerCount: _readInt(json['prayer_count']),
      commentCount: _readInt(json['comment_count']),
      category: PrayerCategory.fromCode(json['category'] as String?),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      isMine: json['is_mine'] == true,
      isAnonymous: (json['visibility'] as String?) == 'anonymous',
      isAnswered: json['is_answered'] == true,
      // Nullable by design — patch_167's CHECK keeps it non-null exactly
      // when is_answered is true, but tolerate a pre-patch deployment.
      answeredAt: DateTime.tryParse(json['answered_at']?.toString() ?? ''),
      testimony: (json['testimony'] as String?)?.trim().isNotEmpty == true
          ? (json['testimony'] as String).trim()
          : null,
    );
  }

  Prayer copyWith({
    int? prayerCount,
    int? commentCount,
    bool? isAnswered,
    DateTime? answeredAt,
    String? testimony,
    List<PrayingUserRef>? prayedBy,
  }) {
    return Prayer(
      id: id,
      authorId: authorId,
      authorName: authorName,
      authorPhotoUrl: authorPhotoUrl,
      authorIsVerified: authorIsVerified,
      content: content,
      prayerCount: prayerCount ?? this.prayerCount,
      commentCount: commentCount ?? this.commentCount,
      category: category,
      createdAt: createdAt,
      isMine: isMine,
      isAnonymous: isAnonymous,
      isAnswered: isAnswered ?? this.isAnswered,
      // Un-answering must be able to clear these, so when isAnswered is
      // explicitly set to false we drop both rather than carrying stale
      // values forward — mirrors what the DB trigger does server-side.
      answeredAt: isAnswered == false ? null : (answeredAt ?? this.answeredAt),
      testimony: isAnswered == false ? null : (testimony ?? this.testimony),
      prayedBy: prayedBy ?? this.prayedBy,
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
    this.authorIsVerified = false,
    this.parentCommentId,
    this.replies = const [],
  });

  final String id;
  final String prayerId;
  final String authorId;
  final String authorName;
  final String? authorPhotoUrl;
  final bool authorIsVerified;
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
      authorIsVerified: authorIsVerified,
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
      authorIsVerified: json['author_is_verified'] == true,
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
