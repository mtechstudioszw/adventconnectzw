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

  static RealtimeChannel? _channel;
  static Timer? _heartbeatTimer;
  static final Set<String> _onlineUserIds = <String>{};
  static final ValueNotifier<Set<String>> _notifier =
      ValueNotifier<Set<String>>(const <String>{});

  /// True when the given user id is currently subscribed to the
  /// presence channel — i.e. has the app open in the foreground.
  static bool isOnline(String userId) => _onlineUserIds.contains(userId);

  /// Read-only view of who is currently online. Listen to [onChange]
  /// for updates.
  static Set<String> get onlineUsers => Set.unmodifiable(_onlineUserIds);

  /// Rebuilds whenever the online roster changes. Tile widgets in the
  /// inbox and the chat-screen header listen on this.
  static ValueListenable<Set<String>> get onChange => _notifier;

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

    final channel = _client.channel(
      _channelName,
      opts: const RealtimeChannelConfig(self: true),
    );

    channel.onPresenceSync((payload, [ref]) {
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
      _notifier.value = Set.unmodifiable(_onlineUserIds);
    });

    channel.subscribe((status, _) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await channel.track({'user_id': me.id});
      }
    });
    _channel = channel;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      _heartbeatInterval,
      (_) => unawaited(_touchLastActive()),
    );
  }

  /// Leaves the presence channel and stops the heartbeat. Called on
  /// sign-out so a stale "online" row doesn't linger for other
  /// clients after the user has actually left.
  static Future<void> stop({bool clearRoster = true}) async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
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
    }
  }

  /// Returns the `profiles.last_active_at` timestamp for [userId], or
  /// null if the user has hidden their last seen via the chat
  /// privacy settings (show_last_seen = false) or on lookup failure.
  static Future<DateTime?> fetchLastSeen(String userId) async {
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
