import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:stack_appodeal_flutter/stack_appodeal_flutter.dart';

import '../premium_service.dart';
import 'ad_config.dart';
import 'ad_impression_counter.dart';
import 'interstitial_ad_manager.dart';
import 'resume_ad_manager.dart';
import 'rewarded_ad_manager.dart';

/// One-time Appodeal setup. Call [init] once from main().
///
/// Everything here is best-effort — if any of it fails we simply don't show
/// ads rather than blocking the app.
///
/// ## What changed when AdMob left (18 Aug 2026)
///
/// * **No consent round-trip of our own.** Appodeal 3.0+ bundles the Stack
///   Consent Manager (built on Google UMP) and requests consent during SDK
///   initialisation, showing the form only where GDPR/CCPA require it. The
///   old `_gatherConsent()` UMP dance is gone; running both would ask the
///   same user twice.
/// * **No ad-unit ids.** [AdConfig.appKey] plus an ad TYPE is the whole
///   request. See [AdConfig].
/// * **No App-Open format.** Appodeal doesn't have one, so the resume ad is
///   now a capped interstitial — see [ResumeAdManager].
class AdsService {
  AdsService._();

  /// `Appodeal.initialize` has been invoked. Guards against a second init.
  static bool _initStarted = false;

  /// Initialisation came back and the SDK is usable.
  static bool _sdkReady = false;

  /// Set by [discardCachedAds] when a subscription starts mid-session.
  /// Cleared by [init] if the subscription later lapses.
  static bool _suspended = false;

  /// True once the Appodeal SDK is initialised. This is SDK state only — it
  /// says nothing about whether we're allowed to show this user an ad. Use
  /// [canRequestAds] for that.
  static bool get isReady => _sdkReady;

  /// The gate every ad surface must check.
  ///
  /// Premium subscribers never even *request* an ad. Hiding a loaded ad
  /// would still have cost them the fetch, the impression call and the
  /// battery — which is most of what a user is paying to be rid of.
  static bool get canRequestAds =>
      _sdkReady && !_suspended && !PremiumService.isActive;

  /// Whether a 320x50 banner is currently cached and worth mounting.
  ///
  /// Appodeal's banner callbacks are global (one handler per process), so
  /// availability lives here rather than in each [AdBanner]. Widgets watch
  /// this instead of guessing: an `AppodealBanner` widget always occupies
  /// its 320x50 box once mounted, so mounting one with nothing to show
  /// would reserve empty space — the exact thing the layout contract
  /// forbids.
  static final ValueNotifier<bool> bannerAvailable = ValueNotifier<bool>(false);

  /// Same, for the 300x250 in-feed rectangle.
  static final ValueNotifier<bool> mrecAvailable = ValueNotifier<bool>(false);

  /// Kick off SDK init. Safe to call multiple times.
  ///
  /// A premium user skips this entirely: no consent form, no Appodeal
  /// initialisation, no ad SDK in the process at all. If the subscription
  /// later lapses, main() calls this again and it re-arms.
  static Future<void> init() async {
    if (PremiumService.isActive) return;

    // Already initialised once and then suspended by a purchase that has
    // since lapsed — re-arm rather than initialising the SDK twice.
    if (_initStarted) {
      if (_suspended) _resume();
      return;
    }
    _initStarted = true;

    try {
      // Configuration must happen BEFORE initialize().
      Appodeal.setTesting(AdConfig.useTestAds);
      Appodeal.setLogLevel(
        kDebugMode ? Appodeal.LogLevelDebug : Appodeal.LogLevelNone,
      );
      // Belt and braces. We deliberately ship no AdMob adapter (see
      // android/app/build.gradle.kts), but the AdMob ACCOUNT is disapproved
      // and under appeal — if an adapter ever arrives transitively, serving
      // AdMob through it would be the one thing we must not do.
      Appodeal.disableNetwork('admob');

      // Each ad type has its own method channel, so the managers can each
      // own their own callbacks without fighting. Within a type there is
      // only ONE handler, which is why each of these is called exactly once
      // and only from here.
      _attachBannerCallbacks();
      _attachMrecCallbacks();
      InterstitialAdManager.attachCallbacks();
      RewardedAdManager.attachCallbacks();

      final done = Completer<void>();
      Appodeal.initialize(
        appKey: AdConfig.appKey,
        adTypes: const [
          AppodealAdType.Interstitial,
          AppodealAdType.RewardedVideo,
          AppodealAdType.Banner,
          AppodealAdType.MREC,
        ],
        onInitializationFinished: (errors) {
          if (errors != null && errors.isNotEmpty) {
            // Per-network failures are normal — most networks stay locked
            // until the app has live store traffic. The SDK still serves
            // from whichever ones did come up.
            for (final error in errors) {
              debugPrint('Appodeal init warning: ${error.description}');
            }
          }
          if (!done.isCompleted) done.complete();
        },
      );

      // Never let a hung initialisation stall the caller's `.then`.
      await done.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {},
      );
      _sdkReady = true;
      _suspended = false;
      unawaited(refreshAvailability());
    } catch (e) {
      debugPrint('AdsService init failed (ads disabled this session): $e');
      _sdkReady = false;
    }
  }

  /// Ask the SDK directly what is cached right now.
  ///
  /// The load callbacks only fire on a change, so a surface that mounts
  /// long after a banner was cached would otherwise sit blank waiting for
  /// an event that already happened.
  static Future<void> refreshAvailability() async {
    if (!canRequestAds) {
      bannerAvailable.value = false;
      mrecAvailable.value = false;
      return;
    }
    try {
      final results = await Future.wait([
        Appodeal.isLoaded(AppodealAdType.Banner),
        Appodeal.isLoaded(AppodealAdType.MREC),
      ]);
      bannerAvailable.value = results[0];
      mrecAvailable.value = results[1];
    } catch (e) {
      debugPrint('AdsService.refreshAvailability failed: $e');
    }
    await RewardedAdManager.refresh();
  }

  /// Test seam: pretend the SDK did (or didn't) initialise, so the premium
  /// gate can be tested without a real Appodeal instance.
  @visibleForTesting
  static void debugSetReady(bool value) {
    _sdkReady = value;
    _initStarted = value;
    _suspended = false;
    if (!value) {
      bannerAvailable.value = false;
      mrecAvailable.value = false;
    }
  }

  /// Stop serving, immediately — a purchase just completed.
  ///
  /// Appodeal has no "throw away the cached interstitial" call, so this is
  /// the honest equivalent of the old `dispose()`-everything:
  ///
  ///   1. turn OFF auto-caching, so nothing new is fetched;
  ///   2. hide and destroy the on-screen banner / MREC views;
  ///   3. drop [canRequestAds] to false, which is what actually stops every
  ///      `show()` call in the app.
  ///
  /// Without step 3 an interstitial cached seconds before checkout would
  /// still fire in the face of someone who has just paid not to see it.
  static void discardCachedAds() {
    _suspended = true;
    bannerAvailable.value = false;
    mrecAvailable.value = false;
    RewardedAdManager.markUnavailable();
    InterstitialAdManager.markUnavailable();
    if (!_sdkReady) return;
    try {
      for (final type in const [
        AppodealAdType.Interstitial,
        AppodealAdType.RewardedVideo,
        AppodealAdType.Banner,
        AppodealAdType.MREC,
      ]) {
        Appodeal.setAutoCache(type, false);
      }
      Appodeal.hide(AppodealAdType.Banner);
      Appodeal.hide(AppodealAdType.MREC);
      Appodeal.destroy(AppodealAdType.Banner);
      Appodeal.destroy(AppodealAdType.MREC);
    } catch (e) {
      debugPrint('AdsService.discardCachedAds failed: $e');
    }
  }

  /// The subscription lapsed. Turn caching back on and start asking again.
  static void _resume() {
    _suspended = false;
    if (!_sdkReady) return;
    try {
      for (final type in const [
        AppodealAdType.Interstitial,
        AppodealAdType.RewardedVideo,
        AppodealAdType.Banner,
        AppodealAdType.MREC,
      ]) {
        Appodeal.setAutoCache(type, true);
        Appodeal.cache(type);
      }
    } catch (e) {
      debugPrint('AdsService resume failed: $e');
    }
    unawaited(refreshAvailability());
  }

  static void _attachBannerCallbacks() {
    Appodeal.setBannerCallbacks(
      onBannerLoaded: (_) => bannerAvailable.value = canRequestAds,
      onBannerFailedToLoad: () => bannerAvailable.value = false,
      onBannerExpired: () => bannerAvailable.value = false,
      onBannerShowFailed: () => bannerAvailable.value = false,
      // Counted when the ad actually RENDERS, not when it fills — the
      // Premium screen quotes this number back to the user, so it has to
      // stay true.
      onBannerShown: () => unawaited(AdImpressionCounter.record()),
    );
  }

  static void _attachMrecCallbacks() {
    Appodeal.setMrecCallbacks(
      onMrecLoaded: (_) => mrecAvailable.value = canRequestAds,
      onMrecFailedToLoad: () => mrecAvailable.value = false,
      onMrecExpired: () => mrecAvailable.value = false,
      onMrecShowFailed: () => mrecAvailable.value = false,
      onMrecShown: () => unawaited(AdImpressionCounter.record()),
    );
  }
}
