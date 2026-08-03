import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';
import 'ad_impression_counter.dart';
import 'ads_service.dart';

/// Full-screen interstitial used BETWEEN stories (the founder asked for an
/// ad while flicking through stories). Frequency-capped so a long story
/// binge shows at most one ad every [_minGap]. Preloads the next ad after
/// each show. Best-effort — a miss just means no ad that time.
class InterstitialAdManager {
  InterstitialAdManager._();

  static const Duration _minGap = Duration(minutes: 2);

  static InterstitialAd? _ad;
  static bool _isLoading = false;
  static bool _isShowing = false;
  static DateTime? _lastShown;

  /// Drop any preloaded ad (a subscription just started).
  static void discardCache() {
    _ad?.dispose();
    _ad = null;
  }

  /// Preload an interstitial so it's ready at the next story boundary.
  static void loadAd() {
    if (!AdsService.canRequestAds || _isLoading || _ad != null) return;
    _isLoading = true;
    InterstitialAd.load(
      adUnitId: AdConfig.interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _isLoading = false;
        },
        onAdFailedToLoad: (error) {
          debugPrint('Interstitial failed to load: $error');
          _ad = null;
          _isLoading = false;
        },
      ),
    );
  }

  /// True if the cap currently permits another interstitial.
  static bool get _capAllows =>
      _lastShown == null || DateTime.now().difference(_lastShown!) >= _minGap;

  /// Show an interstitial if one is loaded and the cap allows. Returns
  /// true if an ad was shown (caller may want to pause story timers).
  static Future<bool> maybeShow() async {
    if (!AdsService.canRequestAds || _isShowing || !_capAllows) {
      loadAd();
      return false;
    }
    final ad = _ad;
    if (ad == null) {
      loadAd();
      return false;
    }
    _ad = null;
    _isShowing = true;
    _lastShown = DateTime.now();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) =>
          unawaited(AdImpressionCounter.record()),
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
    await ad.show();
    return true;
  }
}
