import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Central registry for every AdMob identifier the app uses.
///
/// HOW TO GO LIVE (earn real money):
///   1. In android/app/src/main/AndroidManifest.xml replace the
///      `com.google.android.gms.ads.APPLICATION_ID` test value with your
///      real AdMob App ID (the one with a "~").
///   2. Paste your real ad-unit IDs into the `_realAndroid*` constants
///      below (and `_realIos*` if/when you ship iOS).
///   3. Leave [forceTestAds] alone — debug builds always use Google's
///      test units so you never click your own live ads (an AdMob ban
///      risk). Release builds use your real IDs automatically.
///
/// If a real ID is left blank we fall back to Google's public TEST unit
/// for that format, so the app always has *something* to show.
class AdConfig {
  AdConfig._();

  /// Debug builds (and the emulator) must never request live ads —
  /// AdMob bans accounts for self-clicks. Flip to true to also force
  /// test ads in a release build while QA-ing.
  static const bool forceTestAds = false;

  static bool get _useTest => forceTestAds || kDebugMode;

  // ----- YOUR REAL AD-UNIT IDS — paste between the quotes -------------
  // Android
  static const String _realAndroidBanner =
      'ca-app-pub-9393348961586729/1133541271';
  static const String _realAndroidNative =
      'ca-app-pub-9393348961586729/3244699296';
  static const String _realAndroidAppOpen =
      'ca-app-pub-9393348961586729/1250191425';
  static const String _realAndroidInterstitial =
      'ca-app-pub-9393348961586729/5924923285';
  // iOS (only needed once you publish an iOS build)
  static const String _realIosBanner = '';
  static const String _realIosNative = '';
  static const String _realIosAppOpen = '';
  static const String _realIosInterstitial = '';

  // ----- Google's public TEST unit IDs (safe to ship in debug) -------
  static const String _testAndroidBanner =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _testAndroidNative =
      'ca-app-pub-3940256099942544/2247696110';
  static const String _testAndroidAppOpen =
      'ca-app-pub-3940256099942544/9257395921';
  static const String _testAndroidInterstitial =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _testIosBanner =
      'ca-app-pub-3940256099942544/2934735716';
  static const String _testIosNative =
      'ca-app-pub-3940256099942544/3986624511';
  static const String _testIosAppOpen =
      'ca-app-pub-3940256099942544/5575463023';
  static const String _testIosInterstitial =
      'ca-app-pub-3940256099942544/4411468910';

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  /// Picks the real id if set (and not forced to test), else the test id.
  static String _pick({
    required String realAndroid,
    required String realIos,
    required String testAndroid,
    required String testIos,
  }) {
    if (_useTest) return _isAndroid ? testAndroid : testIos;
    final real = _isAndroid ? realAndroid : realIos;
    if (real.isNotEmpty) return real;
    return _isAndroid ? testAndroid : testIos;
  }

  static String get bannerUnitId => _pick(
        realAndroid: _realAndroidBanner,
        realIos: _realIosBanner,
        testAndroid: _testAndroidBanner,
        testIos: _testIosBanner,
      );

  static String get nativeUnitId => _pick(
        realAndroid: _realAndroidNative,
        realIos: _realIosNative,
        testAndroid: _testAndroidNative,
        testIos: _testIosNative,
      );

  static String get appOpenUnitId => _pick(
        realAndroid: _realAndroidAppOpen,
        realIos: _realIosAppOpen,
        testAndroid: _testAndroidAppOpen,
        testIos: _testIosAppOpen,
      );

  static String get interstitialUnitId => _pick(
        realAndroid: _realAndroidInterstitial,
        realIos: _realIosInterstitial,
        testAndroid: _testAndroidInterstitial,
        testIos: _testIosInterstitial,
      );

  /// True when we're still on a placeholder/test id for the current
  /// platform — handy for a debug banner / logging.
  static bool get usingTestAds =>
      _useTest ||
      (_isAndroid ? _realAndroidBanner.isEmpty : _realIosBanner.isEmpty);
}
