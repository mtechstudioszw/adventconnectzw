import 'package:flutter/foundation.dart';

/// Everything the Appodeal integration needs to identify itself.
///
/// This file used to be a registry of AdMob ad-unit IDs, one per format
/// per platform. **Appodeal has no ad-unit IDs at all** — you initialise
/// with the App Key and then request by TYPE (interstitial / banner / MREC
/// / rewarded), and Appodeal runs the waterfall server-side. So there is
/// nothing to paste in here when a new placement is added; the dashboard's
/// "Ad Units" page configures each type across networks and never mints an
/// id. If you came here looking for where to put an id, you don't need one.
class AdConfig {
  AdConfig._();

  /// The Appodeal App Key for Adventist Super App (Android + iOS share it).
  ///
  /// **This is not a secret.** It ships inside every APK by design — it
  /// identifies the app to the ad server the same way a bundle id does.
  /// Do not treat it like the Supabase PAT; it does not need rotating and
  /// it is fine in source control.
  static const String appKey =
      '1f6b42e57ed20ce3e9378dc3a59a46578c982215c968cca1';

  /// Debug builds request Appodeal's test inventory instead of live ads.
  ///
  /// Kept for the same reason the AdMob version had it: clicking your own
  /// live ads is fraud from the network's point of view, and every network
  /// in the waterfall has its own version of that rule. Flip to true to
  /// force test ads in a release build while QA-ing.
  static const bool forceTestAds = false;

  static bool get useTestAds => forceTestAds || kDebugMode;
}
