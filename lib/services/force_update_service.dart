import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_version.dart';
import 'cache_service.dart';
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

  /// Whether the LAST definitive answer blocked this device.
  ///
  /// `pref:` so it survives sign-out — the required build is a property of
  /// the server, not of whoever is signed in. See
  /// [CacheService.clearUserData]: an unprefixed key would be wiped on
  /// sign-out and the stickiness below would silently stop working.
  static const _kWasBlocked = 'pref:force_update_blocked_v1';

  static bool get _wasBlocked => CacheService.readPref(_kWasBlocked) == '1';

  /// How long to wait for `app_config` before giving up.
  ///
  /// THE BUG THIS FIXES (founder, 19 Aug 2026): "if you cold start again it
  /// removes the force update." The gate is not sticky — it is a race. A
  /// flat 1200 ms budget that fails open means the block only appears on
  /// launches where the network happens to answer in time; the next cold
  /// start times out, fails open, and the user walks straight in.
  ///
  /// Same adaptive shape as [MaintenanceService.splashTimeout], for the
  /// same reason: a device whose last real answer was "blocked" waits
  /// longer for a definitive one. Everyone else keeps the fast path,
  /// because that is virtually every launch and the splash must stay
  /// quick.
  static Duration get _timeout => _wasBlocked
      ? const Duration(milliseconds: 5000)
      : const Duration(milliseconds: 1200);

  /// Full update check.
  ///
  /// Fails open on error ONLY for devices that were not already blocked —
  /// a flaky network must never lock out someone who is up to date. A
  /// device whose last definitive answer was "you must update" stays
  /// blocked when the check fails, because the alternative is a gate that
  /// any offline relaunch walks through.
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
          .timeout(_timeout);

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
        return last = _remember(const UpdateCheck(UpdateLevel.required));
      }

      // A newer build is out → grace window applies.
      if (kAppBuildNumber < latestBuild) {
        final daysLeft = await _graceDaysLeft(latestBuild, graceDays);
        return last = _remember(
          daysLeft <= 0
              ? const UpdateCheck(UpdateLevel.required)
              : UpdateCheck(UpdateLevel.recommended, daysLeft: daysLeft),
        );
      }

      return last = _remember(UpdateCheck.none);
    } catch (_) {
      // No answer. Hold the last DEFINITIVE verdict rather than defaulting
      // to "fine": a device we previously told to update stays told. Only
      // a device that was never blocked is let through on a failure, which
      // is the case the fail-open rule was written for.
      return last = _wasBlocked
          ? const UpdateCheck(UpdateLevel.required)
          : UpdateCheck.none;
    }
  }

  /// Records whether this device is currently shut out, so the next launch
  /// knows to wait for a real answer instead of failing open.
  ///
  /// Only a DEFINITIVE result reaches here — never the catch branch — so a
  /// network failure can neither set nor clear the flag. `unawaited` because
  /// the verdict must not wait on a disk write during the splash.
  static UpdateCheck _remember(UpdateCheck result) {
    unawaited(
      CacheService.writePref(
        _kWasBlocked,
        result.level == UpdateLevel.required ? '1' : '0',
      ),
    );
    return result;
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
