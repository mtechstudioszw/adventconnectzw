import 'dart:async';

import 'package:flutter/foundation.dart';

import '../secure_storage_service.dart';
import 'interstitial_ad_manager.dart';

/// The ad shown when a member comes back to the app from the background.
///
/// ## Why this replaced AppOpenAdManager
///
/// **Appodeal has no App-Open format.** Its formats are interstitial,
/// banner, MREC, video, rewarded and native — there is no equivalent of
/// AdMob's App-Open ad, so the resume slot is now a regular interstitial
/// under a much stricter cap.
///
/// Two things follow from that, and both are the whole point of this class
/// existing instead of the resume path just calling the interstitial
/// manager directly:
///
///  1. **The route blocklist comes with it.** A full-screen ad on resume is
///     the most intrusive placement in the app, and [blockedPrefixes] is
///     where it must never appear. That list used to live privately in
///     `main.dart`; it belongs next to the thing it restrains, where a test
///     can read it.
///  2. **It shares the interstitial cap.** Delegating to
///     [InterstitialAdManager] means the 2-minute global gap applies here
///     too, so coming back to the app right after a story-boundary ad can't
///     produce a second full-screen ad on top of it. Two managers each
///     holding their own cap would have done exactly that.
class ResumeAdManager {
  ResumeAdManager._();

  /// Deliberately the App-Open key from the AdMob era. Existing installs
  /// keep the cap they had earned — renaming it would hand every upgrading
  /// user a free full-screen ad on their first resume.
  static const _kLastShown = 'ad_app_open_last_v1';

  /// "Capped" per the founder's choice — at most one resume ad every three
  /// hours so returning users aren't carpet-bombed.
  static const Duration minGap = Duration(hours: 3);

  /// Routes where a full-screen ad must NOT appear.
  ///
  /// Advent Chat is absolute (founder, 18 Aug 2026): **nothing to do with
  /// messaging ever carries an ad** — not this, not a banner, not a feed
  /// card. Prayer is the same kind of rule. The rest are places where a
  /// tester hit an unskippable ad every time they opened something;
  /// revenue stays on the home feed and stories.
  static const List<String> blockedPrefixes = <String>[
    '/messages', // Advent Chat — inbox, conversations, groups, requests
    '/prayer',
    '/splash',
    '/biometric-lock',
    '/onboarding',
    '/login',
    '/signup',
    '/email-verification',
    '/profile-setup',
    '/forgot-password',
    '/reset-password',
    '/account-banned',
    '/update-required',
    '/admin',
    '/marketplace',
    '/events',
    '/churches',
    '/library',
    '/news',
  ];

  /// True if a full-screen ad is allowed on top of [location].
  static bool allowedOn(String location) =>
      !blockedPrefixes.any(location.startsWith);

  /// Keep an interstitial warm for the next resume.
  static void loadAd() => InterstitialAdManager.loadAd();

  /// Show a resume ad if everything allows it. Returns true if one showed.
  ///
  /// Order matters: the cheap in-memory checks run before the stored
  /// timestamp read, and the timestamp is only WRITTEN once an ad has
  /// actually been presented. The AdMob version wrote it just before
  /// `show()`, so a failed show still burned three hours of eligibility.
  static Future<bool> showIfReady(String location) async {
    if (!allowedOn(location)) {
      // Still keep one warm for when they land somewhere it's allowed.
      loadAd();
      return false;
    }
    if (!InterstitialAdManager.canShowNow) {
      loadAd();
      return false;
    }
    if (!await _capAllows()) return false;

    final shown = await InterstitialAdManager.maybeShow();
    if (shown) {
      await SecureStorageService.write(
        _kLastShown,
        DateTime.now().toIso8601String(),
      );
    }
    return shown;
  }

  static Future<bool> _capAllows() async {
    try {
      final raw = await SecureStorageService.read(_kLastShown);
      final last = DateTime.tryParse(raw ?? '');
      if (last == null) return true;
      return DateTime.now().difference(last) >= minGap;
    } catch (e) {
      debugPrint('ResumeAdManager cap read failed: $e');
      return false;
    }
  }
}
