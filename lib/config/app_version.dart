/// The app's LOGICAL build number for the force-update gate
/// (ForceUpdateService). This is a monotonic counter bumped once per
/// release — it is deliberately NOT the pubspec `+N` (which CI rewrites to
/// 1000+run_number). Older installs that shipped before this release all
/// report 9, so setting `app_config.latest_build_android = 10` AFTER the
/// 1.3.0 build is live on Play nudges them to update. Bump this every release.
///
/// NOTE: this is intentionally DECOUPLED from the Play Store `versionCode`.
/// The AAB CI workflow overrides the Play Store versionCode to
/// `1000 + run_number` so uploads never collide — but the force-update logic
/// compares THIS constant against `app_config.latest_build_android` /
/// `min_build_android`. So when you want to nudge older installs after a
/// release, set `latest_build_android` to THIS value (10), NOT the Play Store
/// versionCode.
const int kAppBuildNumber = 10;

/// Play Store listing id (Android applicationId) — used to deep-link to
/// the store from the "Update required" screen.
const String kAndroidPackageId =
    'io.supabase.adventconnectzw.advent_connect_zw';
