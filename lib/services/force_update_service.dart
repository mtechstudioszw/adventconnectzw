import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_version.dart';
import 'secure_storage_service.dart';

/// How urgently the running build needs to update.
enum UpdateLevel {
  /// Up to date (or newer than the published build) — do nothing.
  none,

  /// A newer build exists but we're still inside the grace window. Show a
  /// dismissible "update available — N days left" nudge; the user may
  /// continue using the app.
  recommended,

  /// Either below the hard floor (`min_build_android`) or the grace window
  /// has expired — hard-block on the update screen until they update.
  required,
}

/// Outcome of a force-update check.
class UpdateCheck {
  final UpdateLevel level;

  /// Days remaining in the soft-warning window (only meaningful when
  /// [level] is [UpdateLevel.recommended]).
  final int daysLeft;

  const UpdateCheck(this.level, {this.daysLeft = 0});

  static const none = UpdateCheck(UpdateLevel.none);
}

/// Reads the remote update policy (app_config) and decides whether the
/// running build is up to date, should be softly nudged, or must be
/// hard-blocked.
///
/// Three `app_config` keys drive it:
///  - `min_build_android`    — hard floor. Builds below this are blocked
///                             immediately (emergency lever).
///  - `latest_build_android` — newest published build. Builds below this
///                             (but at/above the floor) enter the grace
///                             window.
///  - `update_grace_days`    — length of the grace window (default 5). After
///                             this many days from when THIS device first saw
///                             the new build, the nudge escalates to a hard
///                             block.
///
/// Bump [kAppBuildNumber] + `latest_build_android` on every release; only
/// raise `min_build_android` when you must force everyone off an old build.
class ForceUpdateService {
  ForceUpdateService._();
  static final SupabaseClient _client = Supabase.instance.client;

  /// Per-target-build "first seen" marker so each device gets the full
  /// grace window from when it first learned about the new build.
  static const _graceKeyPrefix = 'update_grace_first_seen_';

  /// Result of the most recent [check], so the home screen can surface the
  /// soft prompt after the splash has routed away.
  static UpdateCheck last = UpdateCheck.none;

  /// Whether the soft prompt has already been shown this app session, so we
  /// nudge once per launch instead of on every navigation back to home.
  static bool softPromptShownThisSession = false;

  /// Full update check. Fails open ([UpdateLevel.none]) on any error so a
  /// flaky network never locks users out.
  static Future<UpdateCheck> check() async {
    try {
      // Timeboxed so a slow/cold network can never stall the splash.
      final rows = await _client
          .from('app_config')
          .select('key, value')
          .inFilter('key', const [
            'min_build_android',
            'latest_build_android',
            'update_grace_days',
          ])
          .timeout(const Duration(milliseconds: 1200));

      final cfg = <String, String>{
        for (final r in (rows as List))
          (r['key'] as String): (r['value']?.toString() ?? ''),
      };

      final minBuild = int.tryParse(cfg['min_build_android'] ?? '') ?? 1;
      // Default latest to the floor so a half-configured table never nags.
      final latestBuild =
          int.tryParse(cfg['latest_build_android'] ?? '') ?? minBuild;
      final graceDays = int.tryParse(cfg['update_grace_days'] ?? '') ?? 5;

      // Below the hard floor → block now, no grace.
      if (kAppBuildNumber < minBuild) {
        return last = const UpdateCheck(UpdateLevel.required);
      }

      // A newer build is out → grace window applies.
      if (kAppBuildNumber < latestBuild) {
        final daysLeft = await _graceDaysLeft(latestBuild, graceDays);
        return last = daysLeft <= 0
            ? const UpdateCheck(UpdateLevel.required)
            : UpdateCheck(UpdateLevel.recommended, daysLeft: daysLeft);
      }

      return last = UpdateCheck.none;
    } catch (_) {
      return last = UpdateCheck.none;
    }
  }

  /// Days left in the soft-warning window for [targetBuild]. Anchored to the
  /// first time THIS device saw [targetBuild] (persisted locally), so the
  /// clock starts when the user could first have updated.
  static Future<int> _graceDaysLeft(int targetBuild, int graceDays) async {
    final key = '$_graceKeyPrefix$targetBuild';
    final saved = await SecureStorageService.read(key);
    final now = DateTime.now();
    final DateTime firstSeen;
    if (saved == null) {
      firstSeen = now;
      await SecureStorageService.write(key, now.toIso8601String());
    } else {
      firstSeen = DateTime.tryParse(saved) ?? now;
    }
    final left = graceDays - now.difference(firstSeen).inDays;
    return left < 0 ? 0 : left;
  }

  /// Back-compat: true when the running build must be hard-blocked.
  static Future<bool> updateRequired() async =>
      (await check()).level == UpdateLevel.required;
}
