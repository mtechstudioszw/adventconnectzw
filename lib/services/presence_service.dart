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
  /// null on lookup failure. Used by the chat header to render
  /// "last seen 3 hours ago" when the user isn't currently online.
  static Future<DateTime?> fetchLastSeen(String userId) async {
    try {
      final row = await _client
          .from('profiles')
          .select('last_active_at')
          .eq('id', userId)
          .maybeSingle();
      if (row == null) return null;
      return DateTime.tryParse(row['last_active_at']?.toString() ?? '');
    } catch (_) {
      return null;
    }
  }

  /// Human-readable "last seen" string. Returns "just now" for under
  /// a minute, "Nm ago" / "Nh ago" / "Nd ago" for short ranges, and
  /// "MMM d" (e.g. "May 25") for older timestamps. The input is
  /// expected in UTC; conversion to local happens here.
  static String formatLastSeen(DateTime t) {
    final local = t.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.isNegative || diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[local.month - 1]} ${local.day}';
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
