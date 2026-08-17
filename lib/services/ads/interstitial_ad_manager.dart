import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:stack_appodeal_flutter/stack_appodeal_flutter.dart';

import 'ad_impression_counter.dart';
import 'ads_service.dart';

/// The app's ONE full-screen interstitial, and the only thing allowed to
/// show one.
///
/// Used between stories (the founder asked for an ad while flicking
/// through), after posting, at quiz boot / results, and — since Appodeal
/// has no App-Open format — on return from background via [ResumeAdManager],
/// which delegates here rather than running a second full-screen ad of its
/// own. That matters: two managers each keeping their own cap would happily
/// show two interstitials back to back.
///
/// Frequency-capped so a long binge shows at most one ad every [_minGap].
/// Best-effort — a miss just means no ad that time.
class InterstitialAdManager {
  InterstitialAdManager._();

  static const Duration _minGap = Duration(minutes: 2);

  /// Appodeal auto-caches interstitials by default, so there is no load
  /// call to make and no ad object to hold. All we track is whether the
  /// SDK told us one is ready.
  static bool _loaded = false;
  static bool _isShowing = false;
  static DateTime? _lastShown;

  /// Registered once, by [AdsService.init]. There is a single interstitial
  /// method-call handler per process — whoever sets it last wins — so this
  /// must never be called from anywhere else.
  static void attachCallbacks() {
    Appodeal.setInterstitialCallbacks(
      onInterstitialLoaded: (_) => _loaded = true,
      onInterstitialFailedToLoad: () => _loaded = false,
      onInterstitialExpired: () => _loaded = false,
      onInterstitialShown: () {
        _loaded = false;
        unawaited(AdImpressionCounter.record());
      },
      onInterstitialShowFailed: () {
        _loaded = false;
        _isShowing = false;
      },
      onInterstitialClosed: () => _isShowing = false,
    );
  }

  /// Kept for call-site compatibility with the AdMob version, and it still
  /// does something useful: auto-cache is on, but an explicit cache call
  /// after a failure brings the next attempt forward.
  static void loadAd() {
    if (!AdsService.canRequestAds || _loaded) return;
    try {
      Appodeal.cache(AppodealAdType.Interstitial);
    } catch (e) {
      debugPrint('Interstitial cache failed: $e');
    }
  }

  /// True if the cap currently permits another interstitial.
  static bool get _capAllows =>
      _lastShown == null || DateTime.now().difference(_lastShown!) >= _minGap;

  /// Whether a show right now would actually produce an ad. Used by
  /// [ResumeAdManager] so it doesn't burn its own 3-hour cap on a miss.
  static bool get canShowNow =>
      AdsService.canRequestAds && !_isShowing && _capAllows && _loaded;

  /// Show an interstitial if one is loaded and the cap allows. Returns true
  /// if an ad was shown (caller may want to pause story timers).
  static Future<bool> maybeShow() async {
    if (!AdsService.canRequestAds || _isShowing || !_capAllows) {
      loadAd();
      return false;
    }
    if (!_loaded) {
      loadAd();
      return false;
    }
    _isShowing = true;
    try {
      final shown = await Appodeal.show(AppodealAdType.Interstitial);
      if (!shown) {
        // Appodeal declined — a placement rule, or the cached ad went stale
        // between the check and the call. Do NOT burn the cap on a no-show.
        _isShowing = false;
        _loaded = false;
        loadAd();
        return false;
      }
      _lastShown = DateTime.now();
      return true;
    } catch (e) {
      debugPrint('Interstitial show failed: $e');
      _isShowing = false;
      return false;
    }
  }

  /// Forget any cached ad — a subscription just started, or auto-cache was
  /// turned off underneath us, so the "loaded" flag would otherwise stay
  /// stale-true until the SDK next contradicted it.
  static void markUnavailable() {
    _loaded = false;
    _isShowing = false;
  }

  @visibleForTesting
  static void debugSet({bool loaded = false, DateTime? lastShown}) {
    _loaded = loaded;
    _lastShown = lastShown;
    _isShowing = false;
  }

  @visibleForTesting
  static Duration get debugMinGap => _minGap;
}
