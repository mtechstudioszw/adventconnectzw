import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Wraps Google Mobile Ads init + provides the right banner unit ID for
/// the current platform. Production IDs come from `--dart-define`
/// arguments at build time (see `scripts/build_release.*`). Anything
/// not supplied falls back to Google's official test IDs, which are
/// safe to ship in debug builds — they always return a fill so the
/// layout never collapses while you're developing.
class AdsService {
  AdsService._();

  static bool _initialized = false;

  // Google's official test unit IDs — used in debug, and as the default
  // when --dart-define isn't supplied.
  static const _testAndroidBanner = 'ca-app-pub-3940256099942544/6300978111';
  static const _testIosBanner = 'ca-app-pub-3940256099942544/2934735716';

  // Production unit IDs — supplied at build time via:
  //   --dart-define=ADMOB_ANDROID_BANNER=ca-app-pub-XXXX/YYYY
  //   --dart-define=ADMOB_IOS_BANNER=ca-app-pub-XXXX/YYYY
  // If a release build forgets to pass these, we fall back to the test
  // ID so we don't crash — but `bannerUnitId()` will still return the
  // test ID for that release (visible in the console).
  static const _prodAndroidBanner = String.fromEnvironment(
    'ADMOB_ANDROID_BANNER',
    defaultValue: _testAndroidBanner,
  );
  static const _prodIosBanner = String.fromEnvironment(
    'ADMOB_IOS_BANNER',
    defaultValue: _testIosBanner,
  );

  // Always use the test ID for debug builds. For release builds, use
  // the production ID — which defaults to the test ID if --dart-define
  // wasn't passed, so a malformed release build still gets a fill.
  static bool get _useTest => kDebugMode;

  /// One-shot init. Safe to call multiple times. Gates initialisation
  /// of the Mobile Ads SDK behind UMP consent so we comply with
  /// GDPR / Play Store ad policy. Failures here never propagate —
  /// ads are decorative; nothing else should block on them.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await _requestConsentIfRequired();
      await MobileAds.instance.initialize();
    } catch (e, st) {
      debugPrint('AdsService: init failed: $e\n$st');
    }
  }

  /// Asks the UMP SDK whether GDPR consent is required for the current
  /// user, and shows the consent form if so. Resolves once consent is
  /// either obtained, not required, or the request errors. Errors are
  /// swallowed — we'd rather show ads with a worst-case fallback than
  /// block the whole app behind a flaky consent flow.
  static Future<void> _requestConsentIfRequired() async {
    final params = ConsentRequestParameters();
    final completer = Completer<void>();
    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        params,
        () async {
          try {
            await ConsentForm.loadAndShowConsentFormIfRequired();
          } catch (e, st) {
            debugPrint('AdsService: consent form failed: $e\n$st');
          } finally {
            if (!completer.isCompleted) completer.complete();
          }
        },
        (FormError error) {
          debugPrint(
            'AdsService: consent info update failed: ${error.message}',
          );
          if (!completer.isCompleted) completer.complete();
        },
      );
      await completer.future;
    } catch (e, st) {
      debugPrint('AdsService: consent flow crashed: $e\n$st');
    }
  }

  /// Banner unit ID for the current platform. Returns null on
  /// unsupported platforms (desktop/web) so callers can skip rendering.
  static String? bannerUnitId() {
    if (Platform.isAndroid) {
      return _useTest ? _testAndroidBanner : _prodAndroidBanner;
    }
    if (Platform.isIOS) {
      return _useTest ? _testIosBanner : _prodIosBanner;
    }
    return null;
  }
}
