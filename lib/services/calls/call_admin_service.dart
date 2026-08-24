import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Read-only window onto the calling system for the super-admin console
/// (patch_264).
///
/// ## The RPC is the control. This file is not.
///
/// `call_admin_metrics()` and `call_admin_end()` are SECURITY DEFINER and
/// both `PERFORM public.assert_super_admin()` as their first statement.
/// That guard — not a route the app happens not to link to, not a check
/// in Dart — is what stops a non-admin reading these numbers. The anon
/// key ships inside the APK, so anyone who unzips it can call these RPCs
/// directly; a client-side `if (isSuperAdmin)` would be advice, not
/// security. Deliberately there is NO such check anywhere in this file:
/// adding one would imply the server does not have it, and the next
/// person would move the guard here.
///
/// ## No content, by construction
///
/// Nothing this service can return describes what was SAID. No call is
/// recorded, transcribed or proxied (patch_260 §"No audio, ever"), and
/// the RPC returns counts, durations and — in `top_users` only —
/// display names. There is no `room_token`, no SDP and no ICE in the
/// payload, and none may be added: `room_token` is the Realtime
/// capability itself, so leaking it into an admin screen would hand a
/// reader the ability to join the channel.
///
/// ## Failure never throws at the UI
///
/// Same posture as `CallApi`: the transport's problems come back as data
/// so a caller can render an error state instead of wrapping every call
/// site in try/catch. [CallAdminMetrics.error] carries the reason.
class CallAdminService {
  CallAdminService._();

  static SupabaseClient get _client => Supabase.instance.client;

  /// Longer than CallApi's 15s on purpose. Nobody is waiting for a phone
  /// to ring here — this is a dozen aggregates over the whole `calls`
  /// table, and on a cold buffer cache after a quiet night the first run
  /// of the day is the slow one. Timing out and showing "could not
  /// reach" when the answer was 2s away is the worse failure.
  static const _timeout = Duration(seconds: 20);

  /// Every number the console shows, in one round trip.
  ///
  /// One RPC rather than a query per tile because each tile would
  /// otherwise be an RLS-checked round trip from Harare, and because
  /// `calls`/`call_events` are not readable by a client at all —
  /// patch_260 gives `call_events` a `USING (FALSE)` policy and revokes
  /// the table. Aggregating in Postgres is the only path that exists.
  static Future<CallAdminMetrics> metrics() async {
    try {
      final raw = await _client.rpc('call_admin_metrics').timeout(_timeout);
      if (raw is! Map) {
        // A non-map here means the RPC shape changed under us. Say so
        // rather than rendering an all-zeros screen, which an operator
        // would read as "calling is dead" and escalate at 2am.
        return const CallAdminMetrics(error: 'Call metrics came back in an unexpected shape.');
      }
      return CallAdminMetrics.fromJson(raw.cast<String, dynamic>());
    } on PostgrestException catch (e) {
      // assert_super_admin() raises 42501 (patch_040). NOTE: CallApi maps
      // 42501 to "rate limited" because on the member-facing RPCs that
      // code comes from patch_191's write-rate-limit triggers. Here there
      // are no such triggers, so 42501 means exactly one thing — not a
      // super admin — and telling an operator "slow down" would send them
      // hunting for a limit that is not there.
      if (e.code == '42501') {
        debugPrint('CallAdminService.metrics denied: not a super admin');
        return const CallAdminMetrics(
          error: 'This account is not a super admin, so call metrics are not available.',
        );
      }
      debugPrint('CallAdminService.metrics postgrest ${e.code}: ${e.message}');
      return const CallAdminMetrics(error: 'Could not load call metrics.');
    } catch (e) {
      // Catches TimeoutException and every socket failure alike: from the
      // screen's point of view "no answer" and "slow answer" need the
      // same retry button.
      debugPrint('CallAdminService.metrics failed: $e');
      return const CallAdminMetrics(
        error: 'Could not reach the call service. Check the connection and try again.',
      );
    }
  }

  /// Hang up one call, for everyone in it.
  ///
  /// patch_264's kill switch, kept here so the console has a lever and
  /// not just a scoreboard — it exists for "someone is being harassed
  /// while I am looking at this". It ends a call; there is no code path
  /// in this project, server or client, that could LISTEN to one.
  ///
  /// Nothing calls this yet: patch_264 exposes no "list the live calls"
  /// RPC, so the console has no way to name a call id. Wiring a UI to it
  /// needs that RPC first — do not solve it by querying `calls` from the
  /// client, which RLS correctly refuses for anyone not in the call.
  static Future<bool> endCall(String callId) async {
    try {
      final raw = await _client
          .rpc('call_admin_end', params: {'p_call': callId})
          .timeout(_timeout);
      return raw is Map && raw['ok'] == true;
    } catch (e) {
      debugPrint('CallAdminService.endCall failed: $e');
      return false;
    }
  }
}

/// Postgres `numeric` (every `ROUND(...)` in patch_264 returns one) reaches
/// Dart as an int, a double or — depending on driver and magnitude — a
/// string. Parsing all three keeps one stray `"0"` from blanking a tile.
int _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse('$v') ?? double.tryParse('$v')?.round() ?? 0;
}

/// One day of patch_264's 30-day trend series.
class CallAdminDay {
  const CallAdminDay({
    required this.day,
    required this.calls,
    required this.minutes,
  });

  /// The DB's own day boundary, not the phone's. `started_at::date` and
  /// `date_trunc('day', now())` are both evaluated in the database's
  /// timezone (UTC on Supabase), so a call placed at 01:00 in Harare
  /// lands on the previous day here. Two hours of drift on a daily
  /// count, and the alternative — re-bucketing client-side — would make
  /// this series disagree with `calls_today`, which is worse.
  final DateTime day;
  final int calls;
  final int minutes;

  /// Returns null for a row whose date will not parse: a bar with no
  /// place on the axis is worse than a missing bar.
  static CallAdminDay? fromJson(Map<String, dynamic> json) {
    final day = DateTime.tryParse('${json['day']}');
    if (day == null) return null;
    return CallAdminDay(
      day: day,
      calls: _asInt(json['calls']),
      minutes: _asInt(json['minutes']),
    );
  }
}

/// A member in the "heaviest users, last 30 days" list.
class CallAdminTopUser {
  const CallAdminTopUser({
    required this.name,
    required this.minutes,
    required this.relayedMinutes,
  });

  /// Display name only. patch_264 also returns `user_id` on each row and
  /// this model DELIBERATELY DROPS IT. An id in the model is an id a
  /// screen can tap through to a profile, and from there the list stops
  /// being "who is spending our bandwidth" and starts being a directory
  /// of who has been calling. Nothing in the console needs the id: there
  /// is no admin action here that takes a user.
  final String name;

  /// Total call minutes in the window. An aggregate — never a call, never
  /// a counterparty, never a time of day.
  final int minutes;

  /// Of [minutes], how many went through TURN. This is the per-member
  /// share of the only line item calling can put on a bill.
  final int relayedMinutes;

  factory CallAdminTopUser.fromJson(Map<String, dynamic> json) {
    final name = '${json['name'] ?? ''}'.trim();
    return CallAdminTopUser(
      // The RPC already coalesces a blank name to 'Member'; repeated here
      // because a blank row would otherwise render as an empty gap that
      // reads like a rendering bug.
      name: name.isEmpty ? 'Member' : name,
      minutes: _asInt(json['minutes']),
      relayedMinutes: _asInt(json['relayed_minutes']),
    );
  }
}

/// Everything `call_admin_metrics()` answers with — or [error] explaining
/// why it did not.
class CallAdminMetrics {
  const CallAdminMetrics({
    this.totalCalls = 0,
    this.callsToday = 0,
    this.calls7d = 0,
    this.activeNow = 0,
    this.ringingNow = 0,
    this.directCalls = 0,
    this.groupCalls = 0,
    this.answered = 0,
    this.missed = 0,
    this.rejected = 0,
    this.busy = 0,
    this.failed = 0,
    this.swept = 0,
    this.totalMinutes = 0,
    this.avgSeconds = 0,
    this.peakParticipants = 0,
    this.relayedMinutes30d = 0,
    this.minutes30d = 0,
    this.rateLimitEvents24h = 0,
    this.pushFailures24h = 0,
    this.daily = const [],
    this.topUsers = const [],
    this.error,
  });

  // ---- volumes ----------------------------------------------------------
  final int totalCalls;
  final int callsToday;
  final int calls7d;

  /// Calls whose status is not yet 'ended' — so this INCLUDES the ones
  /// still ringing, which is why [ringingNow] is reported beside it
  /// rather than instead of it.
  final int activeNow;
  final int ringingNow;
  final int directCalls;
  final int groupCalls;

  // ---- outcomes ---------------------------------------------------------
  /// Calls that reached `connected_at`. patch_264 has no 'completed'
  /// counter and does not need one: a call that never connected did not
  /// happen, whatever its end_reason says, so answered/total is the
  /// health signal.
  final int answered;
  final int missed;
  final int rejected;
  final int busy;

  /// 'failed' and 'unreachable' summed by the RPC — media never came up,
  /// or no device could be rung. Both mean the same thing to whoever has
  /// to fix it: the phone never got a usable path.
  final int failed;

  /// Swept by the janitor: 'stale' or 'max_duration'.
  final int swept;

  // ---- duration ---------------------------------------------------------
  final int totalMinutes;

  /// Mean duration of CONNECTED calls only — ringing time is not billed
  /// and averaging it in would drag the number toward zero every time
  /// somebody's phone was in a bag.
  final int avgSeconds;
  final int peakParticipants;

  // ---- cost -------------------------------------------------------------
  /// TURN-relayed minutes in the last 30 days. The only figure on this
  /// screen that maps to money.
  final int relayedMinutes30d;
  final int minutes30d;

  // ---- pressure ---------------------------------------------------------
  final int rateLimitEvents24h;
  final int pushFailures24h;

  // ---- series -----------------------------------------------------------
  /// Oldest first — patch_264 orders by day ascending, and the chart
  /// draws left to right in that order without re-sorting.
  final List<CallAdminDay> daily;
  final List<CallAdminTopUser> topUsers;

  /// Human-readable reason the metrics are missing, or null on success.
  /// Present so the screen can distinguish "no calls yet" from "we could
  /// not ask" — an empty state and a broken state look identical if the
  /// service swallows the difference, and only one of them needs a
  /// human.
  final String? error;

  static const empty = CallAdminMetrics();

  bool get hasError => error != null;

  /// True only for a genuinely fresh system: asked successfully, nothing
  /// there.
  bool get isEmpty => error == null && totalCalls == 0 && daily.isEmpty;

  /// Share of calls that reached audio. 0 when nothing has been placed,
  /// so the tile shows 0% rather than NaN%.
  double get answerRate => totalCalls == 0 ? 0 : answered / totalCalls;

  /// Share of billed minutes that went through TURN.
  double get relayShare =>
      minutes30d == 0 ? 0 : (relayedMinutes30d / minutes30d).clamp(0.0, 1.0);

  /// Minutes so far today, read out of [daily] because patch_264 exposes
  /// `calls_today` but no `minutes_today`. Matched on the UTC date to
  /// agree with the series it came from (see [CallAdminDay.day]); a day
  /// with no calls has no row at all, which is the 0 case.
  int get minutesToday {
    final now = DateTime.now().toUtc();
    for (final d in daily) {
      final day = d.day.toUtc();
      if (day.year == now.year && day.month == now.month && day.day == now.day) {
        return d.minutes;
      }
    }
    return 0;
  }

  factory CallAdminMetrics.fromJson(Map<String, dynamic> json) {
    return CallAdminMetrics(
      totalCalls: _asInt(json['total_calls']),
      callsToday: _asInt(json['calls_today']),
      calls7d: _asInt(json['calls_7d']),
      activeNow: _asInt(json['active_now']),
      ringingNow: _asInt(json['ringing_now']),
      directCalls: _asInt(json['direct_calls']),
      groupCalls: _asInt(json['group_calls']),
      answered: _asInt(json['answered']),
      missed: _asInt(json['missed']),
      rejected: _asInt(json['rejected']),
      busy: _asInt(json['busy']),
      failed: _asInt(json['failed']),
      swept: _asInt(json['swept']),
      totalMinutes: _asInt(json['total_minutes']),
      avgSeconds: _asInt(json['avg_seconds']),
      peakParticipants: _asInt(json['peak_participants']),
      relayedMinutes30d: _asInt(json['relayed_minutes_30d']),
      minutes30d: _asInt(json['minutes_30d']),
      rateLimitEvents24h: _asInt(json['rate_limit_events_24h']),
      pushFailures24h: _asInt(json['push_failures_24h']),
      daily: (json['daily'] is List)
          ? (json['daily'] as List)
              .whereType<Map>()
              .map((e) => CallAdminDay.fromJson(e.cast<String, dynamic>()))
              .whereType<CallAdminDay>()
              .toList()
          : const [],
      topUsers: (json['top_users'] is List)
          ? (json['top_users'] as List)
              .whereType<Map>()
              .map((e) => CallAdminTopUser.fromJson(e.cast<String, dynamic>()))
              .toList()
          : const [],
    );
  }
}
