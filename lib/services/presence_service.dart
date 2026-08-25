import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Realtime presence + last-seen tracking, WhatsApp-style.
///
/// - **Online**: each signed-in user joins the shared "online_users"
///   realtime channel and broadcasts a presence row keyed by their
///   user id. Other clients receive presence sync events whenever
///   someone joins or leaves, and read [isOnline] / [onlineUsers] /
///   [onChange] to render online indicators.
/// - **Last seen**: a heartbeat updates `profiles.last_active_at`
///   every 30s while the app is in the foreground. When a user is
///   offline, callers display `last seen X ago` derived from this
///   column via [fetchLastSeen].
///
/// Lifecycle: [start] is called from `main.dart` after a successful
/// sign-in (and on auth-state SIGNED_IN events). [stop] is called on
/// sign-out to clear the presence row and stop the heartbeat.
class PresenceService {
  PresenceService._();

  static final SupabaseClient _client = Supabase.instance.client;
  static const _channelName = 'online_users';
  static const _heartbeatInterval = Duration(seconds: 30);
  // How often we check that the realtime socket is still actually up.
  // Presence only pushes events on join/leave, so a socket that dies
  // without emitting a close leaves the last roster frozen and every
  // contact showing green. Polling the socket's own connection state is
  // the signal that survives that — the realtime client's internal
  // heartbeat flips it within ~30s of a silent drop, and we surface that
  // to the UI one watchdog tick later.
  static const _watchdogInterval = Duration(seconds: 10);

  static RealtimeChannel? _channel;
  static Timer? _heartbeatTimer;
  static Timer? _watchdogTimer;
  static final Set<String> _onlineUserIds = <String>{};
  static final ValueNotifier<Set<String>> _notifier =
      ValueNotifier<Set<String>>(const <String>{});
  // Tracks whether we currently announce ourselves on the presence
  // channel. False when the user has flipped "Hide online" in the
  // chat privacy screen — we still subscribe so we can see others'
  // dots, we just don't broadcast our own. refreshVisibility() flips
  // this in either direction without tearing the channel down.
  static bool _isTracked = false;

  /// Everyone in a block relationship with the signed-in user, either
  /// direction (patch_210). Treated as permanently offline.
  ///
  /// Presence is a realtime channel, not a table, so no RLS policy can
  /// reach it — blocking someone took away their access to your profile,
  /// photo, about, cover and last seen, and left them your live green
  /// dot. This is the only place that hole can be closed, and closing it
  /// HERE rather than at each call site means the inbox, the chat header,
  /// the contact sheet, church cards and anything added later all get it
  /// without having to remember.
  static final Set<String> _hidden = <String>{};

  /// True when the given user id is currently subscribed to the
  /// presence channel — i.e. has the app open in the foreground.
  static bool isOnline(String userId) =>
      !_hidden.contains(userId) && _onlineUserIds.contains(userId);

  /// Read-only view of who is currently online. Listen to [onChange]
  /// for updates.
  static Set<String> get onlineUsers =>
      Set.unmodifiable(_onlineUserIds.difference(_hidden));

  /// Reloads the block set. Called on [start], and again whenever the
  /// viewer blocks or unblocks someone so the dot goes immediately
  /// instead of at the next launch.
  static Future<void> refreshHidden() async {
    try {
      final rows = await _client.rpc('presence_hidden_ids');
      if (rows is! List) return;
      final next = rows
          .map((r) => r is Map ? (r['id'] ?? '').toString() : r.toString())
          .where((id) => id.isNotEmpty)
          .toSet();
      _hidden
        ..clear()
        ..addAll(next);
      // Republish so anything already listening drops the dots now.
      _notifier.value = Set.unmodifiable(_onlineUserIds.difference(_hidden));
    } catch (_) {
      // Best-effort. Failing open here shows a dot that should be
      // hidden, which is the pre-patch behaviour, not a regression.
    }
  }

  /// Rebuilds whenever the online roster changes. Tile widgets in the
  /// inbox and the chat-screen header listen on this.
  static ValueListenable<Set<String>> get onChange => _notifier;

  /// Test seam: set the online roster without a realtime socket, so the
  /// widgets that render "who is around" can be tested at all. They could
  /// not be before, and the count they showed was wrong in three ways.
  @visibleForTesting
  static void debugSetRoster(Set<String> ids) {
    _onlineUserIds
      ..clear()
      ..addAll(ids);
    _notifier.value = Set.unmodifiable(_onlineUserIds);
  }

  /// Joins the presence channel and starts the last-seen heartbeat.
  /// Safe to call multiple times — re-joining replaces any stale
  /// subscription.
  static Future<void> start() async {
    final me = _client.auth.currentUser;
    if (me == null) return;

    // Tear down any previous subscription first so re-sign-ins don't
    // leave a dangling channel.
    await stop(clearRoster: false);

    // Fire-and-forget initial heartbeat so the user shows online to
    // others within a second of sign-in, not 30s later.
    unawaited(_touchLastActive());
    // Load the block set alongside. Not awaited: a slow RPC must not
    // delay joining the channel, and the first sync republishes through
    // the same filter once it lands.
    unawaited(refreshHidden());

    final channel = _client.channel(
      _channelName,
      opts: const RealtimeChannelConfig(self: true),
    );

    channel.onPresenceSync((payload, [ref]) {
      // Only the live channel owns the roster — a replaced channel's
      // trailing sync must not resurrect an old view of who's online.
      if (_channel != null && !identical(_channel, channel)) return;
      final state = channel.presenceState();
      final ids = <String>{};
      for (final group in state) {
        for (final presence in group.presences) {
          final raw = presence.payload['user_id'];
          if (raw is String && raw.isNotEmpty) ids.add(raw);
        }
      }
      _onlineUserIds
        ..clear()
        ..addAll(ids);
      // Blocked either way never publishes as online — see _hidden.
      _notifier.value = Set.unmodifiable(_onlineUserIds.difference(_hidden));
    });

    // Decide whether to announce ourselves INSIDE the callback, never
    // outside it. subscribe() fires again on every socket reconnect, so a
    // preference read once here and captured in the closure goes stale the
    // moment the member flips "Hide online" — the next network blip would
    // re-track them with the old `true` and silently put their green dot
    // back. Someone who deliberately hid is the last person who should be
    // re-exposed without being told, so we pay a small select per subscribe
    // and always act on the current value.
    channel.subscribe((status, _) async {
      if (status != RealtimeSubscribeStatus.subscribed) {
        // channelError / closed / timedOut — we are no longer receiving
        // presence sync events, so the roster we hold is unverifiable.
        // Drop it rather than leave stale green dots on the inbox.
        // Ignore the death rattle of a channel we've already replaced:
        // start() tears the old one down first, and its `closed` event
        // lands after the new channel has synced.
        if (!identical(_channel, channel)) return;
        _isTracked = false;
        _clearRoster();
        return;
      }
      final wantsToBroadcast = await _wantsToBroadcastPresence();
      if (!wantsToBroadcast) {
        _isTracked = false;
        return;
      }
      // The channel can be torn down between the await above and here
      // (sign-out, a re-entrant start()); tracking a dead channel throws.
      if (!identical(_channel, channel)) return;
      try {
        await channel.track({'user_id': me.id});
        _isTracked = true;
      } catch (_) {
        _isTracked = false;
      }
    });
    _channel = channel;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      _heartbeatInterval,
      (_) => unawaited(_touchLastActive()),
    );

    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(_watchdogInterval, (_) {
      // A dropped socket stops delivering presence sync, and the last sync
      // we got said everyone was online. Without this the inbox keeps
      // showing contacts as available hours after they left — worse than
      // showing no dots at all, because members message expecting a reply.
      if (_onlineUserIds.isEmpty) return;
      if (_client.realtime.isConnected) return;
      _clearRoster();
    });
  }

  /// Drops the online roster and notifies listeners. Used whenever we
  /// lose the ability to observe presence — the alternative is leaving
  /// dots on screen that we can no longer verify.
  static void _clearRoster() {
    if (_onlineUserIds.isEmpty) return;
    _onlineUserIds.clear();
    _notifier.value = const <String>{};
  }

  /// Leaves the presence channel and stops the heartbeat. Called on
  /// sign-out so a stale "online" row doesn't linger for other
  /// clients after the user has actually left.
  static Future<void> stop({bool clearRoster = true}) async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _isTracked = false;
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      try {
        await ch.untrack();
      } catch (_) {}
      try {
        await ch.unsubscribe();
      } catch (_) {}
      try {
        await _client.removeChannel(ch);
      } catch (_) {}
    }
    if (clearRoster) {
      _onlineUserIds.clear();
      _notifier.value = const <String>{};
      // Statics outlive a sign-out. One member's block list must not
      // silently keep hiding people from the next member on the phone.
      _hidden.clear();
    }
  }

  /// Called by ChatPrivacyScreen after the user flips the "Show me
  /// as online" toggle. Reads the freshly-saved profiles row and
  /// either tracks (becomes visible) or untracks (becomes hidden)
  /// the live presence channel without tearing the subscription
  /// down. No-op if presence isn't running yet.
  static Future<void> refreshVisibility() async {
    final ch = _channel;
    if (ch == null) return;
    final wantsToBroadcast = await _wantsToBroadcastPresence();
    try {
      if (wantsToBroadcast && !_isTracked) {
        final me = _client.auth.currentUser;
        if (me == null) return;
        await ch.track({'user_id': me.id});
        _isTracked = true;
      } else if (!wantsToBroadcast && _isTracked) {
        await ch.untrack();
        _isTracked = false;
      }
    } catch (_) {
      // If the channel isn't ready yet the flip will be picked up by
      // the next start() — better to fail silently than crash the
      // privacy screen on a transient network blip.
    }
  }

  /// Reads `profiles.show_online_status` for the signed-in user.
  /// Defaults to `true` (visible) on any error / missing row — the
  /// historical behaviour before this column existed.
  static Future<bool> _wantsToBroadcastPresence() async {
    final me = _client.auth.currentUser;
    if (me == null) return false;
    try {
      final row = await _client
          .from('profiles')
          .select('show_online_status')
          .eq('id', me.id)
          .maybeSingle();
      if (row == null) return true;
      return row['show_online_status'] != false;
    } catch (_) {
      return true;
    }
  }

  /// Returns the `profiles.last_active_at` timestamp for [userId], or
  /// null if the user has hidden their last seen via the chat
  /// privacy settings (show_last_seen = false) or on lookup failure.
  static Future<DateTime?> fetchLastSeen(String userId) async {
    // Blocking takes last seen away too, in both directions.
    //
    // Reported 25 Aug 2026: after blocking someone the green dot goes
    // (patch_210 handles that via [_hidden]) but the header still read
    // "last seen 12:04" — so blocking removed the live signal and left
    // the historical one, which is the more precise of the two.
    //
    // [_hidden] is already the symmetric block set this service loads on
    // start and refreshes on every block/unblock, so the answer is in
    // memory and costs nothing. Checked BEFORE the query, so a blocked
    // pair does not even ask the server.
    if (_hidden.contains(userId)) return null;
    try {
      final row = await _client
          .from('profiles')
          .select('last_active_at, show_last_seen')
          .eq('id', userId)
          .maybeSingle();
      if (row == null) return null;
      // Respect the target user's privacy choice — hidden last seen
      // is reported as null so the chat header falls back to "Offline"
      // instead of pretending we have data.
      if (row['show_last_seen'] == false) return null;
      return DateTime.tryParse(row['last_active_at']?.toString() ?? '');
    } catch (_) {
      return null;
    }
  }

  /// Whether the given user opts into having their green online dot
  /// shown to others. Used by the chat header / inbox tile to gate
  /// the live presence indicator.
  static Future<bool> showsOnlineStatus(String userId) async {
    try {
      final row = await _client
          .from('profiles')
          .select('show_online_status')
          .eq('id', userId)
          .maybeSingle();
      if (row == null) return true;
      return row['show_online_status'] != false;
    } catch (_) {
      return true;
    }
  }

  /// WhatsApp-style "last seen" string with absolute time, not
  /// relative ("X mins ago"). Today: "today at 10:34", yesterday:
  /// "yesterday at 10:34", earlier this year: "Mar 12 at 10:34",
  /// other years: "Mar 12, 2025 at 10:34".
  static String formatLastSeen(DateTime t) {
    final local = t.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(local.year, local.month, local.day);
    final diffDays = today.difference(messageDay).inDays;
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final timeStr = '$hh:$mm';
    if (diffDays == 0) return 'today at $timeStr';
    if (diffDays == 1) return 'yesterday at $timeStr';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final monthDay = '${months[local.month - 1]} ${local.day}';
    if (local.year == now.year) return '$monthDay at $timeStr';
    return '$monthDay, ${local.year} at $timeStr';
  }

  static Future<void> _touchLastActive() async {
    final me = _client.auth.currentUser;
    if (me == null) return;
    try {
      await _client
          .from('profiles')
          .update({'last_active_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', me.id);
    } catch (_) {
      // best-effort — a missed heartbeat just means "last seen" lags
      // by 30s; not worth surfacing to the user.
    }
  }
}
