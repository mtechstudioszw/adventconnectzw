import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../premium_service.dart';
import 'app_open_ad_manager.dart';
import 'interstitial_ad_manager.dart';
import 'rewarded_ad_manager.dart';

/// One-time AdMob setup: gather EU consent (UMP) then initialise the SDK.
/// Everything is best-effort — if any of it fails we simply don't show
/// ads rather than blocking the app. Call [init] once from main().
class AdsService {
  AdsService._();

  static bool _initialized = false;
  static bool _ready = false;

  /// True once MobileAds is initialised. This is SDK state only — it says
  /// nothing about whether we're allowed to show this user an ad. Use
  /// [canRequestAds] for that.
  static bool get isReady => _ready;

  /// The gate every ad surface must check.
  ///
  /// Premium subscribers never even *request* an ad. Hiding a loaded ad
  /// would still have cost them the fetch, the impression call and the
  /// battery — which is most of what a user is paying to be rid of.
  static bool get canRequestAds => _ready && !PremiumService.isActive;

  /// Kick off consent + SDK init. Safe to call multiple times.
  ///
  /// A premium user skips this entirely: no UMP consent round-trip, no
  /// MobileAds initialisation, no ad SDK in the process at all. If the
  /// subscription later lapses, main() calls this again and it runs for
  /// real then.
  static Future<void> init() async {
    if (_initialized) return;
    if (PremiumService.isActive) return;
    _initialized = true;
    try {
      await _gatherConsent();
      await MobileAds.instance.initialize();
      _ready = true;
    } catch (e) {
      debugPrint('AdsService init failed (ads disabled this session): $e');
      _ready = false;
    }
  }

  /// Test seam: pretend the SDK did (or didn't) initialise, so the
  /// premium gate can be tested without a real MobileAds instance.
  @visibleForTesting
  static void debugSetReady(bool value) {
    _ready = value;
    _initialized = value;
  }

  /// Throw away every preloaded full-screen ad. Called the instant a
  /// purchase completes — without this, an interstitial cached seconds
  /// before checkout would still fire in the face of someone who has
  /// just paid not to see it.
  static void discardCachedAds() {
    AppOpenAdManager.discardCache();
    InterstitialAdManager.discardCache();
    RewardedAdManager.discardCache();
  }

  /// Ask the UMP SDK whether consent is required (EEA/UK) and show the
  /// form if so. Outside those regions this resolves immediately as
  /// "not required". Failures are swallowed — we still init the SDK.
  static Future<void> _gatherConsent() async {
    final completer = Completer<void>();
    try {
      final params = ConsentRequestParameters();
      ConsentInformation.instance.requestConsentInfoUpdate(
        params,
        () async {
          try {
            await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
          } catch (_) {
            // Form load/show failed — proceed without it.
          }
          if (!completer.isCompleted) completer.complete();
        },
        (error) {
          // Consent info update failed — proceed (non-EU users hit this
          // path harmlessly too).
          if (!completer.isCompleted) completer.complete();
        },
      );
    } catch (_) {
      if (!completer.isCompleted) completer.complete();
    }
    // Don't let a hung consent flow block startup forever.
    return completer.future.timeout(
      const Duration(seconds: 6),
      onTimeout: () {},
    );
  }
}
