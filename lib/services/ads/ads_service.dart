import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// One-time AdMob setup: gather EU consent (UMP) then initialise the SDK.
/// Everything is best-effort — if any of it fails we simply don't show
/// ads rather than blocking the app. Call [init] once from main().
class AdsService {
  AdsService._();

  static bool _initialized = false;
  static bool _ready = false;

  /// True once MobileAds is initialised and we're allowed to request ads.
  /// Widgets/managers check this before building an ad.
  static bool get isReady => _ready;

  /// Kick off consent + SDK init. Safe to call multiple times.
  static Future<void> init() async {
    if (_initialized) return;
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
