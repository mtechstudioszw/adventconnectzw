import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Wraps Google Mobile Ads init + provides the right banner unit ID for
/// the current platform. Test IDs are used in debug builds, real IDs in
/// release — flip the production constants below once you've created
/// your AdMob app + ad units.
class AdsService {
  AdsService._();

  static bool _initialized = false;

  // Google's official test IDs. Safe to ship in debug — they always
  // return a fill so the layout never collapses while you're developing.
  // Replace before the first release build.
  static const _testAndroidBanner = 'ca-app-pub-3940256099942544/6300978111';
  static const _testIosBanner = 'ca-app-pub-3940256099942544/2934735716';

  // TODO: replace with the real banner unit IDs from AdMob console.
  static const _prodAndroidBanner = 'ca-app-pub-0000000000000000/0000000000';
  static const _prodIosBanner = 'ca-app-pub-0000000000000000/0000000000';

  /// One-shot init. Safe to call multiple times.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await MobileAds.instance.initialize();
    } catch (e, st) {
      debugPrint('AdsService: init failed: $e\n$st');
    }
  }

  /// Banner unit ID for the current platform. Returns null on
  /// unsupported platforms (desktop/web) so callers can skip rendering.
  static String? bannerUnitId() {
    final useTest = kDebugMode;
    if (Platform.isAndroid) {
      return useTest ? _testAndroidBanner : _prodAndroidBanner;
    }
    if (Platform.isIOS) {
      return useTest ? _testIosBanner : _prodIosBanner;
    }
    return null;
  }
}
