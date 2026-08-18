import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'messaging_service.dart';

/// Who is typing to you right now, across every conversation.
///
/// The chat screen has had a typing indicator since the redesign, but it
/// only worked *inside* an open chat: the ping went to
/// `chat:<conversationId>:typing`, which nobody is subscribed to unless
/// they are already looking at that thread. So the inbox — the screen
/// where "someone is typing to me" is actually useful — never showed it.
///
/// This is the other half. Every signed-in user subscribes to ONE channel
/// of their own ([MessagingService.inboxTypingChannelName]) and senders
/// ping that, carrying the conversation id. One subscription per user
/// instead of one per row, and it keeps working as the inbox scrolls.
///
/// Entries expire on their own. A sender re-pings every ~1.8s while they
/// are active, so 4s of silence means they stopped — or their app died,
/// which must look the same. Nothing here is persisted: typing state is
/// ephemeral by definition and a stale "typing…" is worse than none.
class TypingSignal {
  TypingSignal._();

  static final SupabaseClient _client = Supabase.instance.client;

  static RealtimeChannel? _channel;
  static String? _userId;

  /// conversationId → kind ('typing' | 'recording').
  static final ValueNotifier<Map<String, String>> active =
      ValueNotifier<Map<String, String>>(const {});

  static final Map<String, Timer> _expiry = {};

  /// How long an entry survives without a follow-up ping. Senders debounce
  /// at 1.8s, so this must be comfortably above that or the indicator
  /// flickers between pings.
  static const Duration _staleAfter = Duration(seconds: 4);

  /// Subscribe for [userId]. Safe to call repeatedly — a call for the user
  /// who is already subscribed is a no-op, and a call for a different user
  /// tears the old subscription down first (sign-out → sign-in as someone
  /// else must not leave the previous member's channel live).
  static Future<void> start(String userId) async {
    if (userId.isEmpty) return;
    if (_userId == userId && _channel != null) return;
    await stop();
    _userId = userId;
    final channel = _client.channel(
      MessagingService.inboxTypingChannelName(userId),
    );
    channel
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            // Guard on identity: a channel we have since replaced can
            // still deliver a trailing event, and it must not write into
            // the roster the new one owns. Same rule PresenceService
            // learned the hard way.
            if (!identical(_channel, channel)) return;
            final from = (payload['user_id'] ?? '').toString();
            final convo = (payload['conversation_id'] ?? '').toString();
            if (convo.isEmpty || from.isEmpty || from == _userId) return;
            final kind = (payload['kind'] ?? 'typing').toString();
            _mark(convo, kind);
          },
        )
        .subscribe();
    _channel = channel;
  }

  static void _mark(String conversationId, String kind) {
    final next = Map<String, String>.from(active.value);
    if (next[conversationId] != kind) {
      next[conversationId] = kind;
      active.value = next;
    }
    _expiry[conversationId]?.cancel();
    _expiry[conversationId] = Timer(_staleAfter, () => clear(conversationId));
  }

  /// Drop [conversationId] immediately.
  ///
  /// Called on expiry, and by the inbox when a real message lands in that
  /// thread — their message IS the end of them typing, and waiting out the
  /// 4s timer leaves "typing…" sitting under the message they just sent.
  static void clear(String conversationId) {
    _expiry.remove(conversationId)?.cancel();
    if (!active.value.containsKey(conversationId)) return;
    final next = Map<String, String>.from(active.value)
      ..remove(conversationId);
    active.value = next;
  }

  /// Tear down on sign-out. Statics outlive a sign-out, so leaving this
  /// running would leak one member's typing state into the next session
  /// on a shared phone.
  static Future<void> stop() async {
    for (final t in _expiry.values) {
      t.cancel();
    }
    _expiry.clear();
    if (active.value.isNotEmpty) active.value = const {};
    final channel = _channel;
    _channel = null;
    _userId = null;
    if (channel != null) {
      try {
        await _client.removeChannel(channel);
      } catch (_) {
        // Socket already gone — nothing to unsubscribe from.
      }
    }
  }
}
