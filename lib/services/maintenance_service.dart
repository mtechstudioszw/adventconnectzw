import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  static Future<MaintenanceState> check() async {
    try {
      final rows = await _client
          .rpc('maintenance_status')
          .timeout(const Duration(milliseconds: 1500));
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
