/// The app's LOGICAL build number for the force-update gate
/// (ForceUpdateService). Kept in sync with the `+N` in pubspec.yaml
/// (currently 1.1.0+8). Bump this every release.
///
/// NOTE: this is intentionally DECOUPLED from the Play Store `versionCode`.
/// The AAB CI workflow overrides the Play Store versionCode to
/// `1000 + run_number` so uploads never collide — but the force-update logic
/// compares THIS constant against `app_config.latest_build_android` /
/// `min_build_android`. So when you want to nudge older installs after a
/// release, set `latest_build_android` to THIS value (8), NOT the Play Store
/// versionCode.
const int kAppBuildNumber = 8;

/// Play Store listing id (Android applicationId) — used to deep-link to
/// the store from the "Update required" screen.
const String kAndroidPackageId =
    'io.supabase.adventconnectzw.advent_connect_zw';
