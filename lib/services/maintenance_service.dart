import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cache_service.dart';

/// The current maintenance state, as the server describes it.
class MaintenanceState {
  const MaintenanceState({
    required this.active,
    bool? blocked,
    this.message = 'Advent Connect is down for maintenance.',
    this.endsAt,
  }) : _blocked = blocked;

  /// Whether maintenance is switched on at all.
  final bool active;

  /// Whether *this* caller is shut out by it.
  ///
  /// Not the same question as [active], and gating on the wrong one is a real
  /// bug rather than a nicety: patch_187 exempts super admins so that whoever
  /// has to fix the outage can still use the app. Before patch_198 the client
  /// only had the raw flag, so turning maintenance on locked the founder out
  /// of their own app.
  ///
  /// Falls back to [active] when the server is older than patch_198 — the
  /// pre-existing behaviour, rather than failing open on a field that is
  /// simply absent.
  final bool? _blocked;
  bool get blocked => _blocked ?? active;

  final String message;
  final DateTime? endsAt;

  static const off = MaintenanceState(active: false, blocked: false);
}

/// Maintenance mode (#22).
///
/// The client half of `patch_187`. It is the polite half: it shows a
/// blocking screen so members see an explanation instead of a wall of
/// failing requests.
///
/// It is deliberately **not** the enforcement. The founder's requirement
/// was that maintenance cannot be bypassed, and no client check can promise
/// that — an old build, a killed check, or simply staying inside the app
/// all defeat it. Enforcement is a database trigger on every content table
/// (`block_during_maintenance`), so a write is refused whatever the client
/// believes. This just means nobody has to discover that the hard way.
///
/// Mirrors [ForceUpdateService] rather than inventing a second remote
/// config: same `app_config` table, same timeboxed read, same
/// fail-open-on-error rule — a flaky network must never lock anyone out of
/// an app that is working perfectly well.
class MaintenanceService {
  MaintenanceService._();

  static SupabaseClient get _client => Supabase.instance.client;

  /// Result of the most recent [check], for anything that needs it after
  /// the splash has routed away.
  static MaintenanceState last = MaintenanceState.off;

  /// Notifies listeners when maintenance starts or ends while the app is
  /// open, so the shell can put the blocking screen up (or take it down)
  /// without waiting for a relaunch.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// What the LAST successful check said about this device.
  ///
  /// `pref:` so it survives sign-out — maintenance is a property of the
  /// server, not of whoever happens to be signed in. See
  /// [CacheService.clearUserData]; an unprefixed key here would be wiped and
  /// the adaptive budget below would silently stop working for anyone who
  /// signed out.
  static const _kWasBlocked = 'pref:maintenance_blocked_v1';

  static bool get _wasBlocked => CacheService.readPref(_kWasBlocked) == '1';

  /// How long the splash should wait for an answer.
  ///
  /// THE BUG THIS FIXES (founder, Aug 2026): "if you open the app it loads
  /// normally, after a while it locks". A 1500 ms budget that fails open
  /// treats a SLOW answer exactly like NO answer — so on the mobile data
  /// this app is actually used on, the splash gave up, let the member in,
  /// and the 15 s poll in main.dart then threw the blocking screen up on
  /// top of them. Being let in and then kicked out reads as a broken app.
  ///
  /// Fail-open is still right and is untouched: nobody should be locked out
  /// by a dropped packet. What changes is only the BUDGET, and only when we
  /// have reason to expect a block — if the last successful check said this
  /// device was shut out, maintenance is probably still on, so it is worth
  /// waiting for a definitive answer instead of guessing wrong twice.
  /// Everyone else keeps the fast splash.
  static Duration get splashTimeout => _wasBlocked
      ? const Duration(milliseconds: 5000)
      : const Duration(milliseconds: 1500);

  /// How long the splash's GATE waits before giving up and routing on.
  ///
  /// The splash caps the maintenance answer at 400 ms so the loader never
  /// stalls — that cap, not the RPC timeout, is the budget that actually
  /// decides, and raising only [splashTimeout] would have changed nothing.
  ///
  /// Deliberately still 400 ms for everyone whose last known answer was
  /// "not blocked", which is virtually every launch: the splash must stay
  /// fast. Only a device that was genuinely shut out last time spends
  /// longer, and only to avoid showing it the app and then snatching it
  /// away. Kept below [splashTimeout] so the RPC is never the thing that
  /// gives up first.
  static Duration get splashGateTimeout => _wasBlocked
      ? const Duration(milliseconds: 4500)
      : const Duration(milliseconds: 400);

  static Future<MaintenanceState> check({Duration? timeout}) async {
    try {
      final rows = await _client
          .rpc('maintenance_status')
          .timeout(timeout ?? const Duration(milliseconds: 1500));
      final list = rows as List;
      if (list.isEmpty) return last = MaintenanceState.off;
      final row = list.first as Map<String, dynamic>;
      final next = MaintenanceState(
        active: row['active'] == true,
        // Absent on a server older than patch_198; `blocked` then falls back
        // to `active` rather than guessing.
        blocked: row.containsKey('blocked') ? row['blocked'] == true : null,
        message: (row['message'] ?? 'Advent Connect is down for maintenance.')
            .toString(),
        endsAt: DateTime.tryParse(row['ends_at']?.toString() ?? ''),
      );
      // Notify on a change in what the app must DO, not in the raw flag — a
      // super admin toggling maintenance is exempt, and waking every listener
      // to route them somewhere they are not going is churn.
      final changed = next.blocked != last.blocked;
      last = next;
      // Remember the ANSWER, not the attempt — only a successful check
      // reaches here, so a flaky network can never leave a stale "blocked"
      // behind. This is what [splashTimeout] reads on the next cold start.
      unawaited(CacheService.writePref(_kWasBlocked, next.blocked ? '1' : '0'));
      if (changed) revision.value++;
      return next;
    } catch (e) {
      // Fails OPEN, exactly like the update check. A member with no signal
      // must not be told the app is under maintenance when it is not — and
      // if the server really is down, their writes are refused anyway.
      debugPrint('MaintenanceService.check failed: $e');
      return last = MaintenanceState.off;
    }
  }

  /// True when a caught error is the server refusing a write because
  /// maintenance is on, so a screen can say so instead of showing its
  /// generic failure message.
  static bool isMaintenanceError(Object error) =>
      error is PostgrestException &&
      (error.message.contains('MAINTENANCE_MODE') ||
          (error.hint?.contains('maintenance') ?? false));
}
