import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../secure_storage_service.dart';
import 'ad_config.dart';
import 'ads_service.dart';

/// Loads + shows the App-Open ad, hard-capped to once every
/// [_minGap]. Shown on resume from background (never over the splash,
/// login, biometric lock or a chat — the caller checks the route first).
class AppOpenAdManager {
  AppOpenAdManager._();

  static const _kLastShown = 'ad_app_open_last_v1';
  // "Capped" per the founder's choice — at most one App-Open ad every
  // three hours so returning users aren't carpet-bombed.
  static const Duration _minGap = Duration(hours: 3);
  // App-Open ads go stale after ~4h; refuse to show an older cached one.
  static const Duration _maxCacheAge = Duration(hours: 4);

  static AppOpenAd? _ad;
  static DateTime? _loadedAt;
  static bool _isShowing = false;
  static bool _isLoading = false;

  /// Preload an ad so it's ready the next time the user comes back.
  static void loadAd() {
    if (!AdsService.isReady || _isLoading || _ad != null) return;
    _isLoading = true;
    AppOpenAd.load(
      adUnitId: AdConfig.appOpenUnitId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loadedAt = DateTime.now();
          _isLoading = false;
        },
        onAdFailedToLoad: (error) {
          debugPrint('AppOpenAd failed to load: $error');
          _ad = null;
          _isLoading = false;
        },
      ),
    );
  }

  static bool get _isCacheFresh =>
      _loadedAt != null &&
      DateTime.now().difference(_loadedAt!) < _maxCacheAge;

  /// Show the ad if one is loaded, fresh, we're not already showing one,
  /// and the frequency cap allows it. Best-effort — always reloads after.
  static Future<void> showIfReady() async {
    if (!AdsService.isReady || _isShowing) return;
    if (_ad == null || !_isCacheFresh) {
      loadAd();
      return;
    }
    if (!await _capAllows()) return;

    final ad = _ad!;
    _ad = null; // each AppOpenAd instance is single-use
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => _isShowing = true,
      onAdDismissedFullScreenContent: (ad) {
        _isShowing = false;
        ad.dispose();
        loadAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        _isShowing = false;
        ad.dispose();
        loadAd();
      },
    );
    await SecureStorageService.write(
        _kLastShown, DateTime.now().toIso8601String());
    ad.show();
  }

  static Future<bool> _capAllows() async {
    final raw = await SecureStorageService.read(_kLastShown);
    final last = DateTime.tryParse(raw ?? '');
    if (last == null) return true;
    return DateTime.now().difference(last) >= _minGap;
  }
}
