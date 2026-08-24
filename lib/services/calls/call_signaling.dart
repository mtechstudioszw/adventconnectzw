import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The kinds of message that cross a call's signalling channel.
///
/// Note what is NOT here: audio. The media is a direct WebRTC stream
/// between phones (relayed by TURN when it has to be) and never touches
/// Supabase. What travels this channel is a few kilobytes per call —
/// the descriptions two devices need to find each other.
enum CallSignalType {
  /// SDP offer. Sent by the peer with the lower user id (see
  /// [CallSignaling.shouldOffer]) so both sides never offer at once.
  offer,

  /// SDP answer to an offer.
  answer,

  /// One ICE candidate, or a batch of them.
  ice,

  /// Renegotiation after a network change — a fresh offer for a
  /// connection that already exists.
  renegotiate,

  /// "I am hanging up." An optimisation, not a source of truth: the
  /// server ends calls, and a client that misses this still finds out
  /// from the next heartbeat.
  bye,

  /// Mute state, so the participant grid updates immediately instead of
  /// waiting for the next heartbeat round trip.
  mute,

  /// "I am talking right now" — drives the speaking ring in the grid.
  speaking,
}

CallSignalType? _signalType(String? raw) => switch (raw) {
  'offer' => CallSignalType.offer,
  'answer' => CallSignalType.answer,
  'ice' => CallSignalType.ice,
  'renegotiate' => CallSignalType.renegotiate,
  'bye' => CallSignalType.bye,
  'mute' => CallSignalType.mute,
  'speaking' => CallSignalType.speaking,
  _ => null,
};

String _signalName(CallSignalType t) => switch (t) {
  CallSignalType.offer => 'offer',
  CallSignalType.answer => 'answer',
  CallSignalType.ice => 'ice',
  CallSignalType.renegotiate => 'renegotiate',
  CallSignalType.bye => 'bye',
  CallSignalType.mute => 'mute',
  CallSignalType.speaking => 'speaking',
};

/// One signalling message.
class CallSignal {
  const CallSignal({
    required this.type,
    required this.from,
    this.to,
    this.data = const {},
  });

  final CallSignalType type;

  /// Who sent it. See the class docs on [CallSignaling] for why this is
  /// checked against the server's roster rather than believed.
  final String from;

  /// Who it is for. Null means everyone else on the call.
  final String? to;

  final Map<String, dynamic> data;

  Map<String, dynamic> toPayload() => {
    'type': _signalName(type),
    'from': from,
    if (to != null) 'to': to,
    'data': data,
  };

  static CallSignal? fromPayload(Map<String, dynamic> payload) {
    final type = _signalType(payload['type'] as String?);
    final from = (payload['from'] ?? '').toString();
    if (type == null || from.isEmpty) return null;
    final data = payload['data'];
    return CallSignal(
      type: type,
      from: from,
      to: payload['to']?.toString(),
      data: data is Map ? data.cast<String, dynamic>() : const {},
    );
  }
}

/// The signalling channel for ONE call.
///
/// ## What carries this
///
/// A Supabase Realtime **private** broadcast channel named
/// `call:<room_token>`. Private means the join is authorised against
/// the RLS policies patch_262 puts on `realtime.messages`, which ask
/// the database whether this member is a live participant of the call
/// that owns that token — re-checked on every message, so a member who
/// is removed mid-call stops being able to read or write immediately.
///
/// The token itself is a random UUID handed out only by the server
/// (patch_260), and only while the member's participant row is live. It
/// is a capability: never log it, never put it in a push payload.
///
/// ## Why not a table
///
/// SDP and ICE are worthless five seconds after they are sent. Writing
/// them to Postgres would mean a few hundred rows, WAL records and
/// realtime fan-outs per call for data nobody ever reads again. The
/// authority — who is in the call, what state it is in — is in tables;
/// the chatter is not.
///
/// ## The one thing this layer cannot prove
///
/// Realtime broadcast does not attach a verified sender identity, so
/// `from` is a claim by whoever sent the message. RLS proves the sender
/// is *a* live participant of this call; it does not prove they are
/// *the* participant they say they are.
///
/// The blast radius is therefore bounded to people already inside the
/// call: nobody can reach this channel without the server having put
/// them in the room, so this cannot leak audio to an outsider. What it
/// could do is let one participant disrupt another's connection by
/// impersonating a third. Two defences, both in [CallService] rather
/// than here because both need the server's roster:
///
///   * every inbound signal is dropped unless `from` is a participant
///     the SERVER has reported as joined;
///   * an `offer` for a peer whose connection is already established is
///     ignored unless it arrives as an explicit [CallSignalType.renegotiate].
///
/// Closing the gap properly needs signed signalling payloads, which is
/// a real change and is written up in docs/CALLING_SETUP.md rather than
/// half-done here.
class CallSignaling {
  CallSignaling({required this.selfUserId});

  final String selfUserId;

  static SupabaseClient get _client => Supabase.instance.client;

  RealtimeChannel? _channel;
  String? _topic;

  /// Bumped by [disconnect]. Every async continuation captures it and
  /// re-checks after awaiting, so a channel built for a call the member
  /// has already left is torn down instead of being published into a
  /// field the next call is about to use.
  ///
  /// This is the same publish/dispose race that silenced the quiz's
  /// sound for a session — here it would cross two calls' wires.
  int _generation = 0;

  void Function(CallSignal signal)? _onSignal;
  void Function(Set<String> present)? _onPresence;
  void Function(bool connected)? _onChannelState;

  bool _joined = false;
  bool get isConnected => _joined;

  /// Deterministic tie-break for who sends the offer, so two phones
  /// never offer to each other simultaneously (glare). Comparing user
  /// ids gives both sides the same answer without a round trip.
  bool shouldOffer(String peerId) => selfUserId.compareTo(peerId) < 0;

  /// Join the channel for [roomToken].
  ///
  /// Completes once the channel is subscribed, or throws if it cannot
  /// subscribe — a private channel that fails to join almost always
  /// means patch_262 is not applied, and silently degrading would turn
  /// that into "calls connect but nobody can hear anything".
  Future<void> connect({
    required String roomToken,
    required void Function(CallSignal signal) onSignal,
    void Function(Set<String> present)? onPresence,
    void Function(bool connected)? onChannelState,
  }) async {
    await disconnect();
    final generation = ++_generation;

    _onSignal = onSignal;
    _onPresence = onPresence;
    _onChannelState = onChannelState;

    final topic = 'call:$roomToken';
    _topic = topic;

    final completer = Completer<void>();
    final channel = _client.channel(
      topic,
      opts: const RealtimeChannelConfig(
        // RLS-checked join. Without this the channel would be public
        // and the room token would be the only thing standing between a
        // signed-in stranger and the call's signalling.
        private: true,
        // Presence needs a key to track members by. The user id is the
        // right one: it is what the roster is keyed on everywhere else.
        self: false,
      ),
    );

    channel.onBroadcast(
      event: 'signal',
      callback: (payload) {
        if (generation != _generation) return;
        final signal = CallSignal.fromPayload(payload);
        if (signal == null) return;
        // Never process our own echo, and never process a message
        // addressed to someone else. `self: false` above should already
        // prevent the first; belt and braces, because a duplicated
        // offer is a torn-down connection.
        if (signal.from == selfUserId) return;
        if (signal.to != null && signal.to != selfUserId) return;
        _onSignal?.call(signal);
      },
    );

    channel.onPresenceSync((_) {
      if (generation != _generation) return;
      _emitPresence(channel);
    });
    channel.onPresenceJoin((_) {
      if (generation != _generation) return;
      _emitPresence(channel);
    });
    channel.onPresenceLeave((_) {
      if (generation != _generation) return;
      _emitPresence(channel);
    });

    channel.subscribe((status, error) async {
      if (generation != _generation) return;
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          _joined = true;
          _onChannelState?.call(true);
          try {
            await channel.track({'user_id': selfUserId});
          } catch (_) {
            // Presence is a nicety — the participant grid falls back to
            // the server roster. Never fail a call over it.
          }
          if (!completer.isCompleted) completer.complete();
          break;
        case RealtimeSubscribeStatus.channelError:
        case RealtimeSubscribeStatus.timedOut:
          _joined = false;
          _onChannelState?.call(false);
          if (!completer.isCompleted) {
            completer.completeError(
              StateError('call signalling channel failed: $status $error'),
            );
          }
          break;
        case RealtimeSubscribeStatus.closed:
          _joined = false;
          _onChannelState?.call(false);
          break;
      }
    });

    _channel = channel;

    try {
      await completer.future.timeout(const Duration(seconds: 12));
    } catch (e) {
      // Leave nothing half-joined behind.
      if (generation == _generation) await disconnect();
      rethrow;
    }

    if (generation != _generation) {
      // Left while subscribing. Drop it rather than publish a channel
      // the call has already walked away from.
      try {
        await _client.removeChannel(channel);
      } catch (_) {}
    }
  }

  void _emitPresence(RealtimeChannel channel) {
    try {
      final ids = <String>{};
      for (final state in channel.presenceState()) {
        for (final presence in state.presences) {
          final id = presence.payload['user_id'];
          if (id is String && id.isNotEmpty) ids.add(id);
        }
      }
      _onPresence?.call(ids);
    } catch (_) {
      // Presence shape varies across realtime versions; a failure here
      // must not take the call with it.
    }
  }

  /// Send a signal. Fire-and-forget by design — a dropped ICE candidate
  /// is survivable (ICE retries), and awaiting each one would serialise
  /// candidate delivery behind the network.
  Future<void> send(CallSignal signal) async {
    final channel = _channel;
    if (channel == null || !_joined) return;
    try {
      await channel.sendBroadcastMessage(
        event: 'signal',
        payload: signal.toPayload(),
      );
    } catch (e) {
      debugPrint('CallSignaling.send(${_signalName(signal.type)}) failed: $e');
    }
  }

  Future<void> sendTo(
    String peerId,
    CallSignalType type,
    Map<String, dynamic> data,
  ) => send(CallSignal(type: type, from: selfUserId, to: peerId, data: data));

  Future<void> broadcast(CallSignalType type, Map<String, dynamic> data) =>
      send(CallSignal(type: type, from: selfUserId, data: data));

  Future<void> disconnect() async {
    _generation++;
    final channel = _channel;
    _channel = null;
    _topic = null;
    _joined = false;
    _onSignal = null;
    _onPresence = null;
    _onChannelState = null;
    if (channel == null) return;
    try {
      await _client.removeChannel(channel);
    } catch (_) {
      // Socket already gone. Nothing to do.
    }
  }

  @visibleForTesting
  String? get debugTopic => _topic;
}
