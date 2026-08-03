import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';
import 'ads_service.dart';

/// Opt-in rewarded ads — the user CHOOSES to watch for a bonus (e.g. a Bible
/// Quiz hint). Loads ahead of time and reloads after each show.
class RewardedAdManager {
  RewardedAdManager._();

  static RewardedAd? _ad;
  static bool _isLoading = false;
  static bool _isShowing = false;

  /// True only when there's an ad to show AND we're allowed to show it.
  /// For a premium subscriber this is always false, and the quiz's
  /// lifeline path already grants the lifeline free when no ad is
  /// available — which is exactly the right premium behaviour: they get
  /// the hint without the ad, rather than losing the hint.
  static bool get isReady => _ad != null && AdsService.canRequestAds;

  /// Drop any preloaded ad (a subscription just started).
  static void discardCache() {
    _ad?.dispose();
    _ad = null;
  }

  /// Preload a rewarded ad so it's ready when the user taps "watch".
  static void loadAd() {
    if (!AdsService.canRequestAds || _isLoading || _ad != null) return;
    _isLoading = true;
    RewardedAd.load(
      adUnitId: AdConfig.rewardedUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _isLoading = false;
        },
        onAdFailedToLoad: (error) {
          debugPrint('Rewarded failed to load: $error');
          _ad = null;
          _isLoading = false;
        },
      ),
    );
  }

  /// Show the rewarded ad. Returns true only if the user EARNED the reward
  /// (watched enough). Returns false if no ad was ready or it was dismissed
  /// early — the caller grants the bonus only on true.
  static Future<bool> showForReward() async {
    if (_isShowing) return false;
    final ad = _ad;
    if (ad == null) {
      loadAd();
      return false;
    }
    _ad = null;
    _isShowing = true;
    var earned = false;
    // ad.show() resolves as soon as the ad is DISPLAYED, not when it's
    // dismissed — so reading `earned` right after it would always be false
    // (the reward callback fires later). Gate completion on dismissal via a
    // Completer so the caller gets the real earned/not-earned result.
    final done = Completer<bool>();
    void finish(bool value) {
      if (!done.isCompleted) done.complete(value);
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        _isShowing = false;
        ad.dispose();
        loadAd();
        finish(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        _isShowing = false;
        ad.dispose();
        loadAd();
        finish(false);
      },
    );
    await ad.show(
      onUserEarnedReward: (_, _) {
        earned = true;
      },
    );
    return done.future;
  }
}
