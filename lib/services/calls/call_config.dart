import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Every tunable the calling stack reads, in one place.
///
/// ## Why these are not constants
///
/// The brief's rule was "do not scatter constants throughout the code",
/// and the stronger version of that is: do not put them in the code at
/// all. Each value below lives as an `app_config` row (patch_260) and
/// is fetched through the `call_client_config` RPC, so a ring timeout
/// or a participant cap can be changed from the dashboard and take
/// effect on the next call — no build, no Play review, no waiting for
/// members to update.
///
/// The numbers in this file are FALLBACKS for the first launch before
/// the config has been fetched, and for a device that is offline. They
/// are the same values patch_260 seeds, so the two agree by
/// construction.
///
/// ## What is deliberately not here
///
/// The rate limits. The client is not told what they are, because
/// telling a spammer the exact ceiling tells them exactly how to sit
/// under it — and because a limit the client knows is a limit someone
/// will try to enforce client-side, which protects nobody. The server
/// refuses and hands back a sentence to show; that is the whole client
/// contract.
///
/// Also not here: quotas. Those are per-member (free vs premium) and
/// come from `call_my_usage`, not from a shared config blob.
class CallConfig {
  CallConfig._();

  static SupabaseClient get _client => Supabase.instance.client;

  /// Master switch. When the server says calling is off, the buttons
  /// disappear and nothing dials — used to take the feature down
  /// without shipping a build if TURN costs spike or a bug lands.
  static bool enabled = true;

  /// How long a phone rings before the call is marked missed.
  ///
  /// A minute (founder's call, 25 Aug 2026 — it was 45s). It is the
  /// figure the phone networks and WhatsApp both settled on, and it is
  /// the difference between reaching somebody whose phone is in another
  /// room and not. The server has the same number in `app_config`
  /// (`call.ring_timeout_seconds`, patch_268) and its copy is the one
  /// that decides — this is the fallback for a client that has not
  /// fetched config yet.
  static Duration ringTimeout = const Duration(seconds: 60);

  /// How long to wait for MEDIA after the call is answered before
  /// giving up. Separate from [ringTimeout]: answering and then failing
  /// to hear anything is a different failure with a different message.
  static Duration connectTimeout = const Duration(seconds: 45);

  /// How often the CALLER asks the server what happened, while the
  /// other phone is still ringing.
  ///
  /// Deliberately far faster than [heartbeat], and it is the fix for a
  /// real bug (founder, 25 Aug 2026): "when u decline a call it dosent
  /// say to the other user declined, it keeps saying ringing then says
  /// no answer".
  ///
  /// Nothing pushes a decline to the caller. The callee's `call_reject`
  /// finalizes the call server-side straight away and correctly, but
  /// the caller only ever found out through the 15-second heartbeat —
  /// and that heartbeat is started at the END of `_goLive`, after the
  /// signalling join, the ICE fetch and the microphone open. On a slow
  /// connection its first tick could land 25 seconds in, past the point
  /// the member had given up watching, and the ring timeout got there
  /// first with "No answer" — which is not merely late, it is WRONG.
  /// They were declined.
  ///
  /// Two seconds against a ring window of at most sixty is thirty extra
  /// snapshot reads per outgoing call, and only while it rings. That is
  /// nothing at this app's volume, and it is what turns "no answer"
  /// back into the truth.
  static Duration ringPoll = const Duration(seconds: 2);

  /// The mesh ceiling. See docs/CALLING_SETUP.md for the bandwidth
  /// arithmetic behind 5, and why raising it needs an SFU rather than
  /// just a bigger number.
  static int maxGroupParticipants = 5;

  static Duration maxDirectDuration = const Duration(minutes: 120);
  static Duration maxGroupDuration = const Duration(minutes: 90);

  /// How often a live call tells the server it is still alive. The
  /// server's stale sweeper (patch_263) uses roughly five times this as
  /// its grace window.
  static Duration heartbeat = const Duration(seconds: 15);

  static bool _loaded = false;
  static Future<void>? _inFlight;

  /// True once the server's values have been read at least once this
  /// session. Screens can show a call button before this resolves —
  /// the fallbacks are correct — but [refresh] should have completed
  /// before a call is actually placed.
  static bool get isLoaded => _loaded;

  /// Fetch the server's values. Safe to call repeatedly; concurrent
  /// callers share one request.
  ///
  /// Never throws and never clears what it already has: a config fetch
  /// that fails on a bad network must not disable calling, it must
  /// leave the last-known-good values in place. That is the same
  /// fail-open posture ForceUpdateService and MaintenanceService take,
  /// and for the same reason — a flaky connection is not a policy
  /// change.
  static Future<void> refresh() {
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = _refresh();
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  static Future<void> _refresh() async {
    if (_client.auth.currentUser == null) return;
    try {
      final raw = await _client
          .rpc('call_client_config')
          .timeout(const Duration(seconds: 8));
      if (raw is! Map) return;
      final json = raw.cast<String, dynamic>();

      enabled = json['enabled'] != false;
      ringTimeout = _seconds(json['ring_timeout_seconds'], ringTimeout, 10, 180);
      connectTimeout = _seconds(
        json['connect_timeout_seconds'],
        connectTimeout,
        10,
        180,
      );
      maxDirectDuration = _minutes(
        json['max_direct_minutes'],
        maxDirectDuration,
        1,
        480,
      );
      maxGroupDuration = _minutes(
        json['max_group_minutes'],
        maxGroupDuration,
        1,
        480,
      );
      heartbeat = _seconds(json['heartbeat_seconds'], heartbeat, 5, 120);

      final cap = (json['max_group_participants'] as num?)?.toInt();
      // Clamped, not trusted. A config typo that set this to 400 would
      // otherwise ask a mid-range Android to run 399 Opus encoders and
      // take the whole app down with it. 16 is the ceiling the `calls`
      // table's CHECK constraint allows anyway.
      if (cap != null) maxGroupParticipants = cap.clamp(2, 16);

      _loaded = true;
    } catch (e) {
      // Offline, signed out mid-flight, or the patch is not applied to
      // this deployment. Fallbacks stand.
      debugPrint('CallConfig.refresh failed (keeping defaults): $e');
    }
  }

  static Duration _seconds(Object? raw, Duration fallback, int min, int max) {
    final v = (raw as num?)?.toInt();
    if (v == null) return fallback;
    return Duration(seconds: v.clamp(min, max));
  }

  static Duration _minutes(Object? raw, Duration fallback, int min, int max) {
    final v = (raw as num?)?.toInt();
    if (v == null) return fallback;
    return Duration(minutes: v.clamp(min, max));
  }

  /// The hard ceiling for a call of this shape — what the countdown to
  /// an automatic hang-up is measured against.
  static Duration maxDurationFor({required bool isGroup}) =>
      isGroup ? maxGroupDuration : maxDirectDuration;

  /// Test seam. Screens and the service read these as plain statics, so
  /// a widget test that needs a two-second ring timeout has no other
  /// way in.
  @visibleForTesting
  static void debugOverride({
    bool? enabled,
    Duration? ringTimeout,
    Duration? connectTimeout,
    int? maxGroupParticipants,
    Duration? heartbeat,
    Duration? maxDirectDuration,
    Duration? maxGroupDuration,
  }) {
    if (enabled != null) CallConfig.enabled = enabled;
    if (ringTimeout != null) CallConfig.ringTimeout = ringTimeout;
    if (connectTimeout != null) CallConfig.connectTimeout = connectTimeout;
    if (maxGroupParticipants != null) {
      CallConfig.maxGroupParticipants = maxGroupParticipants;
    }
    if (heartbeat != null) CallConfig.heartbeat = heartbeat;
    if (maxDirectDuration != null) {
      CallConfig.maxDirectDuration = maxDirectDuration;
    }
    if (maxGroupDuration != null) CallConfig.maxGroupDuration = maxGroupDuration;
  }

  /// Put every value back to the shipped fallback. Called from
  /// [SessionReset] so the next member on this handset does not inherit
  /// the previous one's fetched config.
  static void reset() {
    enabled = true;
    ringTimeout = const Duration(seconds: 60);
    connectTimeout = const Duration(seconds: 45);
    ringPoll = const Duration(seconds: 2);
    maxGroupParticipants = 5;
    maxDirectDuration = const Duration(minutes: 120);
    maxGroupDuration = const Duration(minutes: 90);
    heartbeat = const Duration(seconds: 15);
    _loaded = false;
  }
}
