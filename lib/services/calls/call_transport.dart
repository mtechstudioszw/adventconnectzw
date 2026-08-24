import 'dart:async';

import 'call_api.dart' show IceConfig;
import 'call_signaling.dart';

/// How one peer's media connection is doing.
enum PeerMediaState {
  /// Negotiating. No audio yet.
  connecting,

  /// Audio is flowing.
  connected,

  /// Was connected, lost the path, ICE is trying to recover. The call
  /// screen shows "Reconnecting…" and does NOT hang up — a tunnel or a
  /// Wi-Fi-to-mobile handover lands here and usually recovers.
  reconnecting,

  /// Gave up.
  failed,

  /// Torn down cleanly.
  closed,
}

/// Something the media stack wants the call service to know.
sealed class TransportEvent {
  const TransportEvent();
}

class PeerStateChanged extends TransportEvent {
  const PeerStateChanged(this.peerId, this.state);
  final String peerId;
  final PeerMediaState state;
}

/// A signal this transport needs delivered to a peer. The transport
/// never touches the network itself — [CallService] owns the channel,
/// so there is exactly one place that decides what leaves this device.
class TransportSignal extends TransportEvent {
  const TransportSignal(this.peerId, this.type, this.data);
  final String peerId;
  final CallSignalType type;
  final Map<String, dynamic> data;
}

/// Local audio level, for the "you are talking" indicator and the
/// speaking ring in the group grid.
class LocalAudioLevel extends TransportEvent {
  const LocalAudioLevel(this.level);

  /// 0..1.
  final double level;
}

/// What the media actually cost and how it connected.
class CallMediaStats {
  const CallMediaStats({
    required this.relayed,
    required this.bytesSent,
    required this.bytesReceived,
    this.roundTripMs,
    this.packetsLost,
  });

  /// True when the selected ICE candidate pair goes through TURN.
  ///
  /// The only field here that maps to a bill: a relayed leg is
  /// bandwidth we pay for, a direct one is free. Reported to the server
  /// on the heartbeat so relay minutes can be attributed rather than
  /// guessed at — and treated there as telemetry, never as anything
  /// authorisation depends on.
  final bool relayed;

  final int bytesSent;
  final int bytesReceived;
  final double? roundTripMs;
  final int? packetsLost;

  static const empty = CallMediaStats(
    relayed: false,
    bytesSent: 0,
    bytesReceived: 0,
  );
}

/// The media engine, behind an interface.
///
/// ## Why this seam exists
///
/// The shipped implementation is [MeshCallTransport] — full-mesh
/// WebRTC, which is the right answer for 1:1 (the audio never touches a
/// server we pay for) and a defensible one for the small group calls
/// this app's participant cap allows.
///
/// It is NOT the right answer at fifteen people, and the point of this
/// interface is that finding that out should cost one new class rather
/// than a rewrite. An SFU implementation would implement exactly these
/// seven methods; [CallService] and every screen above it would not
/// change, because nothing above this line knows how many peer
/// connections exist or whether there are any.
///
/// The bandwidth arithmetic, the threshold at which mesh stops being
/// defensible, and what an SFU swap would involve are in
/// docs/CALLING_SETUP.md.
abstract class CallTransport {
  /// Open the microphone and get ready to connect.
  ///
  /// Throws if the microphone cannot be opened — a call that cannot
  /// hear must fail loudly rather than connect silently, which is the
  /// difference between a bug report and a mystery.
  Future<void> start({required IceConfig ice, bool startMuted = false});

  /// Reconcile the live peer set against [peerIds].
  ///
  /// Idempotent and diff-based: new ids get a connection, missing ids
  /// get torn down, unchanged ids are left completely alone. The call
  /// service drives this straight off the server's participant roster,
  /// which is what stops a peer connection outliving the participant it
  /// belonged to.
  Future<void> setPeers(List<String> peerIds);

  /// Feed in a signal that arrived for this device.
  Future<void> handleSignal(CallSignal signal);

  /// Microphone on/off. Mutes at the track level, so nothing is
  /// captured or transmitted while muted.
  Future<void> setMuted(bool muted);

  /// Renegotiate after a network change (Wi-Fi to mobile and back).
  /// Cheaper and far faster than tearing the call down and redialling.
  Future<void> restartIce();

  /// Aggregate stats across peers.
  Future<CallMediaStats> stats();

  /// Release everything: peer connections, tracks, the microphone.
  ///
  /// Must be safe to call twice, and must leave no microphone open —
  /// a call that ends with the mic still hot is the worst bug this
  /// feature can have.
  Future<void> dispose();

  Stream<TransportEvent> get events;

  /// The worst state across all peers, which is what the call screen
  /// shows: one peer reconnecting in a group call means the call is
  /// reconnecting, not connected.
  PeerMediaState get aggregateState;
}
