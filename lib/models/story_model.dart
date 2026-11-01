import '../services/e2ee/media_crypto.dart';

/// A 24-hour ephemeral story tile from the home feed. Mirrors
/// public.stories (patch_011). Rows past their expires_at are filtered
/// server-side via RLS, so anything we receive is still active.
class Story {
  const Story({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.mediaUrl,
    required this.createdAt,
    required this.expiresAt,
    this.authorPhotoUrl,
    this.authorIsVerified = false,
    this.caption,
    this.kind = 'photo',
    this.textContent,
    this.backgroundColor,
    this.textFont,
    this.e2eeVersion,
    this.mediaKey,
    this.locked = false,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String? authorPhotoUrl;

  /// Cosmetic gold tick (super admin / approved church admin, patch_134).
  final bool authorIsVerified;
  final String mediaUrl;
  final String? caption;
  final DateTime createdAt;
  final DateTime expiresAt;
  // Text status (patch_105): kind 'text' renders centred text on a
  // coloured background instead of an image.
  final String kind;
  final String? textContent;
  final String? backgroundColor;
  final String? textFont;

  /// End-to-end encrypted story (patch_300): the row holds no readable
  /// text and [mediaUrl] points at a sealed file opened with [mediaKey].
  final int? e2eeVersion;
  bool get isEncrypted => (e2eeVersion ?? 0) > 0;

  /// The photo's key, from the envelope this phone opened. Phone only.
  final MediaKey? mediaKey;

  /// Encrypted, and this phone has no key for it (an older build, or a
  /// phone that wasn't set up when it was posted).
  final bool locked;

  bool get isText => kind == 'text';

  Story opened({
    String? textContent,
    String? caption,
    MediaKey? mediaKey,
    String? mediaUrl,
    bool locked = false,
  }) => Story(
    id: id,
    authorId: authorId,
    authorName: authorName,
    mediaUrl: mediaUrl ?? this.mediaUrl,
    createdAt: createdAt,
    expiresAt: expiresAt,
    authorPhotoUrl: authorPhotoUrl,
    authorIsVerified: authorIsVerified,
    caption: caption ?? this.caption,
    kind: kind,
    textContent: textContent ?? this.textContent,
    backgroundColor: backgroundColor,
    textFont: textFont,
    e2eeVersion: e2eeVersion,
    mediaKey: mediaKey ?? this.mediaKey,
    locked: locked,
  );

  /// Time remaining until expiry. Negative means stale — the home
  /// screen drops anything where this is non-positive as a belt-and-
  /// braces guard on top of the RLS filter.
  Duration get timeRemaining => expiresAt.difference(DateTime.now());

  bool get isExpired => !timeRemaining.isNegative ? false : true;

  /// Round-trip JSON for the offline cache. Uses the same nested
  /// `profiles` shape the API returns so [fromJson] hydrates it without
  /// special-casing cached payloads.
  Map<String, dynamic> toJson() => {
        'id': id,
        'author_id': authorId,
        'profiles': {
          'full_name': authorName,
          'profile_photo_url': authorPhotoUrl,
          'is_verified_admin': authorIsVerified,
        },
        'media_url': mediaUrl,
        'caption': caption,
        'kind': kind,
        'text_content': textContent,
        'background_color': backgroundColor,
        'text_font': textFont,
        'e2ee_version': ?e2eeVersion,
        if (mediaKey != null) MediaCrypto.metaKey: mediaKey!.toMeta(),
        if (locked) '_locked': true,
        'created_at': createdAt.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
      };

  factory Story.fromJson(Map<String, dynamic> json) {
    final author = json['profiles'];
    final authorMap = author is Map<String, dynamic> ? author : null;
    final createdAt =
        DateTime.tryParse(json['created_at']?.toString() ?? '') ??
            DateTime.now();
    // Default to createdAt + 24h (NOT now() + 24h) — defaulting to
    // "now" would silently un-expire any row with a missing/invalid
    // expires_at on the way in, so stale stories would appear fresh
    // forever.
    final expiresAt =
        DateTime.tryParse(json['expires_at']?.toString() ?? '') ??
            createdAt.add(const Duration(hours: 24));
    return Story(
      id: json['id'].toString(),
      authorId: (json['author_id'] ?? '').toString(),
      authorName: (authorMap?['full_name'] as String?) ?? 'Member',
      authorPhotoUrl: authorMap?['profile_photo_url'] as String?,
      authorIsVerified: authorMap?['is_verified'] == true,
      mediaUrl: (json['media_url'] ?? '').toString(),
      caption: json['caption'] as String?,
      kind: (json['kind'] as String?) ?? 'photo',
      textContent: json['text_content'] as String?,
      backgroundColor: json['background_color'] as String?,
      textFont: json['text_font'] as String?,
      e2eeVersion: (json['e2ee_version'] as num?)?.toInt(),
      mediaKey: MediaKey.fromMeta(json),
      locked: json['_locked'] == true,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }
}
