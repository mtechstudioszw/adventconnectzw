import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';

import 'secure_storage_service.dart';

/// Gently asks happy users to rate the app on the Play Store using
/// Google's NATIVE in-app review sheet (no jump to the store).
///
/// We don't try to detect whether someone already rated — Google handles
/// that for us: `requestReview()` is quota-limited and silently does
/// nothing for users who've already reviewed (or who've seen the sheet
/// recently). So "only ask people who haven't rated" is satisfied by the
/// platform. On top of that we gate our OWN calls so we only ask:
///   * after the app has been installed for [_minDaysSinceInstall] days,
///   * once the user has opened it at least [_minOpens] times,
///   * no more than once every [_reAskDays] days,
///   * and at most [_maxRequests] times ever.
///
/// All keys live in secure storage and are preserved across sign-out
/// (see SecureStorageService._preservedKeys) so the cadence is per-device,
/// not per-login. Every method is best-effort and never throws.
class RatingPromptService {
  RatingPromptService._();

  static const _kFirstLaunch = 'rate_prompt_first_launch_v1';
  static const _kOpens = 'rate_prompt_opens_v1';
  static const _kLastShown = 'rate_prompt_last_shown_v1';
  static const _kRequests = 'rate_prompt_requests_v1';

  static const int _minDaysSinceInstall = 7;
  static const int _minOpens = 4;
  static const int _reAskDays = 14;
  static const int _maxRequests = 3;

  static bool _countedThisSession = false;
  static final InAppReview _inAppReview = InAppReview.instance;

  /// Record an app open (once per process) and, if every gate passes,
  /// surface the native review sheet. Call this from the home screen.
  static Future<void> maybeRequestReview() async {
    try {
      await _recordOpen();
      final now = DateTime.now();

      final first =
          DateTime.tryParse(await SecureStorageService.read(_kFirstLaunch) ?? '');
      if (first == null || now.difference(first).inDays < _minDaysSinceInstall) {
        return;
      }

      final opens =
          int.tryParse(await SecureStorageService.read(_kOpens) ?? '') ?? 0;
      if (opens < _minOpens) return;

      final requests =
          int.tryParse(await SecureStorageService.read(_kRequests) ?? '') ?? 0;
      if (requests >= _maxRequests) return;

      final last =
          DateTime.tryParse(await SecureStorageService.read(_kLastShown) ?? '');
      if (last != null && now.difference(last).inDays < _reAskDays) return;

      // No Play services / non-Play build → skip silently rather than
      // yanking the user out to a store listing they didn't ask for.
      if (!await _inAppReview.isAvailable()) return;

      await _inAppReview.requestReview();
      await SecureStorageService.write(_kLastShown, now.toIso8601String());
      await SecureStorageService.write(_kRequests, '${requests + 1}');
    } catch (e) {
      debugPrint('RatingPromptService skipped: $e');
    }
  }

  static Future<void> _recordOpen() async {
    if (_countedThisSession) return;
    _countedThisSession = true;

    if (await SecureStorageService.read(_kFirstLaunch) == null) {
      await SecureStorageService.write(
          _kFirstLaunch, DateTime.now().toIso8601String());
    }
    final opens =
        int.tryParse(await SecureStorageService.read(_kOpens) ?? '') ?? 0;
    await SecureStorageService.write(_kOpens, '${opens + 1}');
  }
}
