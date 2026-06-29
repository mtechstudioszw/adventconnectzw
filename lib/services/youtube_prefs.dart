import 'cache_service.dart';

/// User preferences for the Watch experience, persisted locally (no TTL).
/// Surfaced in Settings; read by the player (autoplay-next) and the
/// in-feed auto-preview (Wi-Fi-only / Always / Never).
enum PreviewMode { wifiOnly, always, never }

class YoutubePrefs {
  YoutubePrefs._();

  static const _autoplayNextKey = 'pref:yt_autoplay_next';
  static const _previewModeKey = 'pref:yt_preview_mode';

  /// Auto-advance to the next suggestion when a video ends. Default on.
  static bool get autoplayNext =>
      (CacheService.readPref(_autoplayNextKey) ?? 'true') == 'true';
  static Future<void> setAutoplayNext(bool v) =>
      CacheService.writePref(_autoplayNextKey, v ? 'true' : 'false');

  /// When to auto-play in-feed video previews. Default Wi-Fi only
  /// (respects limited ZW bandwidth).
  static PreviewMode get previewMode {
    switch (CacheService.readPref(_previewModeKey)) {
      case 'always':
        return PreviewMode.always;
      case 'never':
        return PreviewMode.never;
      default:
        return PreviewMode.wifiOnly;
    }
  }

  static Future<void> setPreviewMode(PreviewMode m) {
    final s = switch (m) {
      PreviewMode.always => 'always',
      PreviewMode.never => 'never',
      PreviewMode.wifiOnly => 'wifi',
    };
    return CacheService.writePref(_previewModeKey, s);
  }
}
