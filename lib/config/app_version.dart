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
const int kAppBuildNumber = 12;

/// The version string shown to members, in ONE place.
///
/// Keep in lockstep with `pubspec.yaml`'s `version:` (currently
/// `1.3.2+1034`). Bump both together, right here next to
/// [kAppBuildNumber], which already has to move every release.
///
/// ## Why this constant exists
///
/// Settings and About each carried their own hardcoded `'v1.0.0'`. The app
/// shipped 1.1, 1.2 and 1.3 without either of them changing, so for three
/// releases the About screen confidently told every member they were
/// running a version that had not existed for months — and the one place a
/// person looks to answer "am I up to date?" was the one place guaranteed
/// to be wrong.
///
/// Two copies of a number nobody remembers to update is how that happens.
/// Now there is one, and it sits beside the other release-time constant so
/// they get bumped in the same edit.
///
/// (Reading it from `package_info_plus` at runtime would remove the manual
/// step entirely and is the better long-term answer — deliberately not done
/// here, because adding a native plugin immediately before a release build
/// is not a change to make unannounced.)
const String kAppVersionName = '1.3.2';

/// Play Store listing id (Android applicationId) — used to deep-link to
/// the store from the "Update required" screen.
const String kAndroidPackageId =
    'io.supabase.adventconnectzw.advent_connect_zw';
