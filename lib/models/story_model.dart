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

  bool get isText => kind == 'text';

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
      authorIsVerified: authorMap?['is_verified'] == true ||
          authorMap?['is_verified_admin'] == true,
      mediaUrl: (json['media_url'] ?? '').toString(),
      caption: json['caption'] as String?,
      kind: (json['kind'] as String?) ?? 'photo',
      textContent: json['text_content'] as String?,
      backgroundColor: json['background_color'] as String?,
      textFont: json['text_font'] as String?,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }
}
