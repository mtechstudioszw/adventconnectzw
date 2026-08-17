import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:stack_appodeal_flutter/stack_appodeal_flutter.dart';

import 'ad_impression_counter.dart';
import 'ads_service.dart';

/// Opt-in rewarded ads — the user CHOOSES to watch for a bonus.
///
/// Every rewarded placement in the app goes through here: the quiz's
/// survival continue, double-points, coin top-up, streak repair and
/// lifelines. Appodeal auto-caches rewarded video, so there is no ad object
/// to hold — only the SDK's word on whether one is ready.
///
/// ## Why [available] is a notifier and not just a bool
///
/// Under AdMob the quiz offered a rewarded ad only when one happened to
/// already be loaded, and silently granted the bonus for free otherwise —
/// so the button never *said* anything, and the founder's read was that the
/// quiz wasn't serving ads at all. The offers now render from [available],
/// which means a placement can appear the moment fill arrives instead of
/// being decided once, invisibly, at the wrong moment.
class RewardedAdManager {
  RewardedAdManager._();

  static bool _loaded = false;
  static bool _isShowing = false;
  static Completer<bool>? _pending;

  /// Whether the user actually earned the reward this showing. Set by
  /// `onRewardedVideoFinished`, read when the ad closes.
  static bool _earned = false;

  /// True only when there's an ad to show AND we're allowed to show it.
  /// Always false for a premium subscriber.
  static bool get isReady => _loaded && AdsService.canRequestAds;

  /// [isReady] as something the UI can rebuild on.
  static final ValueNotifier<bool> available = ValueNotifier<bool>(false);

  /// Registered once, by [AdsService.init]. One handler per process.
  static void attachCallbacks() {
    Appodeal.setRewardedVideoCallbacks(
      onRewardedVideoLoaded: (_) => _setLoaded(true),
      onRewardedVideoFailedToLoad: () => _setLoaded(false),
      onRewardedVideoExpired: () => _setLoaded(false),
      onRewardedVideoShown: () {
        _setLoaded(false);
        unawaited(AdImpressionCounter.record());
      },
      onRewardedVideoShowFailed: () {
        _setLoaded(false);
        _finish(false);
      },
      onRewardedVideoFinished: (_, _) => _earned = true,
      // The reward is granted on CLOSE, not on finish: `onRewardedVideoFinished`
      // fires while the ad is still on screen, and granting there would let
      // a lifeline appear underneath an ad the player is still watching.
      onRewardedVideoClosed: (isFinished) => _finish(_earned || isFinished),
    );
  }

  static void _setLoaded(bool value) {
    _loaded = value;
    available.value = isReady;
    if (!value) loadAd();
  }

  static void _finish(bool earned) {
    _isShowing = false;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete(earned);
    loadAd();
  }

  /// Ask for the next rewarded video. Auto-cache normally handles this;
  /// calling it explicitly after a miss brings the retry forward.
  static void loadAd() {
    if (!AdsService.canRequestAds) return;
    try {
      Appodeal.cache(AppodealAdType.RewardedVideo);
    } catch (e) {
      debugPrint('Rewarded cache failed: $e');
    }
  }

  /// Ask the SDK directly whether a rewarded ad is cached.
  static Future<void> refresh() async {
    if (!AdsService.canRequestAds) {
      _setLoaded(false);
      return;
    }
    try {
      _loaded = await Appodeal.isLoaded(AppodealAdType.RewardedVideo);
      available.value = isReady;
      if (!_loaded) loadAd();
    } catch (e) {
      debugPrint('RewardedAdManager.refresh failed: $e');
    }
  }

  /// A subscription just started (or the SDK was suspended).
  static void markUnavailable() {
    _loaded = false;
    _isShowing = false;
    available.value = false;
    _finish(false);
  }

  /// Show the rewarded ad. Returns true only if the user EARNED the reward
  /// (watched enough). Returns false if no ad was ready or it was dismissed
  /// early — the caller grants the bonus only on true.
  static Future<bool> showForReward() async {
    if (_isShowing || !isReady) return false;
    _isShowing = true;
    _earned = false;
    final done = Completer<bool>();
    _pending = done;
    try {
      final shown = await Appodeal.show(AppodealAdType.RewardedVideo);
      if (!shown) {
        // Nothing was presented, so no close callback is coming. Resolving
        // here is what stops the caller's "watching…" state hanging forever.
        _finish(false);
        return false;
      }
    } catch (e) {
      debugPrint('Rewarded show failed: $e');
      _finish(false);
      return false;
    }
    return done.future;
  }

  @visibleForTesting
  static void debugSetLoaded(bool value) {
    _loaded = value;
    _isShowing = false;
    _pending = null;
    available.value = isReady;
  }
}
