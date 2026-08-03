import 'package:flutter/foundation.dart';

import '../secure_storage_service.dart';

/// Counts the ads this device has actually shown.
///
/// It exists so the Premium screen can say something TRUE and personal —
/// "you've seen 214 ads in Advent Connect" — instead of a generic claim.
/// A real number the user recognises is more persuasive than a promise,
/// and it costs us nothing to be honest about it.
///
/// Deliberately device-local: it never leaves the phone, is never sent
/// to the server, and is not tied to the account. It is a display
/// counter, not analytics.
class AdImpressionCounter {
  AdImpressionCounter._();

  static const _kCount = 'ad_impressions_v1';
  static const _kSince = 'ad_impressions_since_v1';

  static int _count = 0;
  static DateTime? _since;
  static bool _loaded = false;

  /// Ads shown on this device since [since].
  static int get count => _count;

  /// When counting started — the day the user first saw an ad.
  static DateTime? get since => _since;

  /// Rebuilds when the count changes, so a screen showing it can animate
  /// the number without polling.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      _count = int.tryParse(await SecureStorageService.read(_kCount) ?? '') ?? 0;
      _since = DateTime.tryParse(await SecureStorageService.read(_kSince) ?? '');
    } catch (e) {
      debugPrint('AdImpressionCounter.load failed: $e');
    }
  }

  /// Record one ad actually shown to the user.
  ///
  /// Called when an ad RENDERS, not when one is requested — a banner
  /// that failed to fill was never seen and must not be counted, or the
  /// number stops being true.
  static Future<void> record() async {
    await load();
    _count++;
    _since ??= DateTime.now();
    revision.value++;
    try {
      await SecureStorageService.write(_kCount, '$_count');
      await SecureStorageService.write(_kSince, _since!.toIso8601String());
    } catch (e) {
      // The in-memory count still works for this session.
      debugPrint('AdImpressionCounter.record could not persist: $e');
    }
  }

  @visibleForTesting
  static void debugSet({int count = 0, DateTime? since}) {
    _loaded = true;
    _count = count;
    _since = since;
    revision.value++;
  }
}
