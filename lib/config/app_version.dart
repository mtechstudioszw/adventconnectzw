/// The installed app's Android versionCode. MUST be kept in sync with the
/// `+N` build number in pubspec.yaml (currently 1.0.6+7). Bump this every
/// time you bump pubspec's build number so the force-update gate
/// (ForceUpdateService) compares the running build correctly.
const int kAppBuildNumber = 7;

/// Play Store listing id (Android applicationId) — used to deep-link to
/// the store from the "Update required" screen.
const String kAndroidPackageId =
    'io.supabase.adventconnectzw.advent_connect_zw';
