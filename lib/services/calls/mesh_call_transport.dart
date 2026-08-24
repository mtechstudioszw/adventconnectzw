import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_api.dart' show IceConfig;
import 'call_signaling.dart';
import 'call_transport.dart';

/// Full-mesh WebRTC audio: one peer connection per other participant.
///
/// ## Why mesh, and where it stops
///
/// For a 1:1 call this is simply correct — the audio goes phone to
/// phone (or through TURN when the network forces it) and never touches
/// a server we pay for or could be asked to hand over.
///
/// For groups it is a deliberate trade sized against the participant
/// cap. Each phone sends its own Opus stream to every other phone, so
/// at N people the uplink is (N-1) x ~24 kbps:
///
///     3 people   ~48 kbps up    fine anywhere
///     5 people   ~96 kbps up    the configured ceiling
///     8 people  ~168 kbps up    starts failing on a busy 3G cell
///    12 people  ~264 kbps up    plus 11 encoders on a mid-range phone
///
/// So the cap is 5 (`call.max_group_participants`), and it is enforced
/// server-side in patch_261 rather than by this class, because a cap
/// the client owns is not a cap. Raising it past ~6 means adding an SFU
/// implementation of [CallTransport] — the interface exists precisely
/// so that is one new class rather than a rewrite. See
/// docs/CALLING_SETUP.md.
///
/// ## Two things this class deliberately does not do
///
///   * **It does not touch the network.** Every signal it needs sent
///     comes out as a [TransportSignal] event and [CallService] puts it
///     on the wire. One place decides what leaves the device.
///   * **It does not decide who the peers are.** [setPeers] is driven
///     from the server's roster. A peer connection can therefore never
///     outlive the participant row it belongs to.
class MeshCallTransport implements CallTransport {
  MeshCallTransport({required this.selfUserId});

  final String selfUserId;

  final _events = StreamController<TransportEvent>.broadcast();
  @override
  Stream<TransportEvent> get events => _events.stream;

  MediaStream? _localStream;
  IceConfig _ice = IceConfig.stunOnly;
  bool _muted = false;
  bool _disposed = false;

  final Map<String, _Peer> _peers = {};

  // ---- lifecycle ---------------------------------------------------------

  @override
  Future<void> start({required IceConfig ice, bool startMuted = false}) async {
    _ice = ice;
    _muted = startMuted;

    // Audio-only, tuned for speech. These three are the difference
    // between a usable call and one where everyone hears themselves a
    // beat later: without echo cancellation a speakerphone call
    // feeds back into itself immediately.
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });

    _localStream = stream;
    _applyMuteToTracks();
  }

  @override
  Future<void> setPeers(List<String> peerIds) async {
    if (_disposed) return;
    final wanted = peerIds.where((id) => id != selfUserId).toSet();

    // Gone: tear down. Doing this first frees encoders before new ones
    // are created, which matters on the low-end handsets this app runs
    // on.
    for (final id in _peers.keys.toList()) {
      if (!wanted.contains(id)) await _removePeer(id);
    }

    // New: connect.
    for (final id in wanted) {
      if (_peers.containsKey(id)) continue;
      await _addPeer(id);
    }
  }

  Future<void> _addPeer(String peerId) async {
    if (_disposed) return;
    final local = _localStream;
    if (local == null) {
      throw StateError('MeshCallTransport.setPeers called before start()');
    }

    final pc = await createPeerConnection({
      'iceServers': _ice.servers,
      'sdpSemantics': 'unified-plan',
      // A small pre-gathered pool shaves a beat off connection setup;
      // larger values just hold ports open for nothing on a call that
      // has exactly one audio stream.
      'iceCandidatePoolSize': 2,
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    });

    final peer = _Peer(id: peerId, pc: pc);
    _peers[peerId] = peer;

    for (final track in local.getAudioTracks()) {
      await pc.addTrack(track, local);
    }

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      peer.queueCandidate({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      }, _flushCandidates);
    };

    pc.onConnectionState = (state) => _onPeerConnectionState(peer, state);

    pc.onTrack = (event) {
      // Unified-plan hands the remote audio over here. Nothing to do
      // but let it play: flutter_webrtc routes remote audio to the
      // active output device automatically, and there is no renderer
      // for an audio-only call.
      if (event.track.kind == 'audio') {
        peer.hasRemoteAudio = true;
      }
    };

    _emit(PeerStateChanged(peerId, PeerMediaState.connecting));

    // Deterministic offerer, so two phones never offer at once (glare).
    // Comparing user ids gives both sides the same answer with no round
    // trip; the peer with the lower id offers.
    if (selfUserId.compareTo(peerId) < 0) {
      await _makeOffer(peer, renegotiate: false);
    }
    // Otherwise we wait for theirs. If it never comes the call service's
    // connect timeout catches it.
  }

  Future<void> _removePeer(String peerId) async {
    final peer = _peers.remove(peerId);
    if (peer == null) return;
    peer.dispose();
    try {
      await peer.pc.close();
    } catch (_) {}
    try {
      await peer.pc.dispose();
    } catch (_) {}
    _emit(PeerStateChanged(peerId, PeerMediaState.closed));
  }

  // ---- negotiation -------------------------------------------------------

  Future<void> _makeOffer(_Peer peer, {required bool renegotiate}) async {
    try {
      final offer = await peer.pc.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      final tuned = RTCSessionDescription(_tuneOpus(offer.sdp ?? ''), offer.type);
      await peer.pc.setLocalDescription(tuned);
      _emit(
        TransportSignal(
          peer.id,
          renegotiate ? CallSignalType.renegotiate : CallSignalType.offer,
          {'sdp': tuned.sdp, 'type': tuned.type},
        ),
      );
    } catch (e) {
      debugPrint('MeshCallTransport: offer to ${peer.id} failed: $e');
      _emit(PeerStateChanged(peer.id, PeerMediaState.failed));
    }
  }

  @override
  Future<void> handleSignal(CallSignal signal) async {
    if (_disposed) return;
    final peer = _peers[signal.from];

    switch (signal.type) {
      case CallSignalType.offer:
      case CallSignalType.renegotiate:
        if (peer == null) return;
        await _handleOffer(peer, signal);
        break;

      case CallSignalType.answer:
        if (peer == null) return;
        await _handleAnswer(peer, signal);
        break;

      case CallSignalType.ice:
        if (peer == null) return;
        await _handleIce(peer, signal);
        break;

      case CallSignalType.bye:
        await _removePeer(signal.from);
        break;

      // Mute and speaking are participant-grid concerns, not media
      // ones. CallService handles them.
      case CallSignalType.mute:
      case CallSignalType.speaking:
        break;
    }
  }

  Future<void> _handleOffer(_Peer peer, CallSignal signal) async {
    final sdp = signal.data['sdp'];
    if (sdp is! String || sdp.isEmpty) return;

    // Glare guard. An `offer` (as opposed to an explicit
    // `renegotiate`) for a connection that is already up is either a
    // duplicate or a peer that has lost track of state; applying it
    // would tear down a working call. Renegotiation has its own signal
    // type precisely so the two are distinguishable.
    final state = peer.pc.signalingState;
    if (signal.type == CallSignalType.offer &&
        state != null &&
        state != RTCSignalingState.RTCSignalingStateStable) {
      debugPrint(
        'MeshCallTransport: ignoring duplicate offer from ${peer.id} '
        'in state $state',
      );
      return;
    }

    try {
      await peer.pc.setRemoteDescription(
        RTCSessionDescription(sdp, (signal.data['type'] ?? 'offer').toString()),
      );
      await peer.drainPendingCandidates();

      final answer = await peer.pc.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      final tuned = RTCSessionDescription(
        _tuneOpus(answer.sdp ?? ''),
        answer.type,
      );
      await peer.pc.setLocalDescription(tuned);
      _emit(
        TransportSignal(peer.id, CallSignalType.answer, {
          'sdp': tuned.sdp,
          'type': tuned.type,
        }),
      );
    } catch (e) {
      // A malformed SDP from a peer must fail THAT peer, not the call.
      // In a group that is one participant nobody can hear; in a 1:1
      // the connect timeout turns it into an honest failure.
      debugPrint('MeshCallTransport: bad offer from ${peer.id}: $e');
      _emit(PeerStateChanged(peer.id, PeerMediaState.failed));
    }
  }

  Future<void> _handleAnswer(_Peer peer, CallSignal signal) async {
    final sdp = signal.data['sdp'];
    if (sdp is! String || sdp.isEmpty) return;
    try {
      // An answer is only meaningful while we are waiting for one.
      // Applying a late duplicate throws and, worse, can reset a
      // connection that has already settled.
      final state = peer.pc.signalingState;
      if (state != RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
        debugPrint(
          'MeshCallTransport: ignoring answer from ${peer.id} in state $state',
        );
        return;
      }
      await peer.pc.setRemoteDescription(
        RTCSessionDescription(sdp, (signal.data['type'] ?? 'answer').toString()),
      );
      await peer.drainPendingCandidates();
    } catch (e) {
      debugPrint('MeshCallTransport: bad answer from ${peer.id}: $e');
      _emit(PeerStateChanged(peer.id, PeerMediaState.failed));
    }
  }

  Future<void> _handleIce(_Peer peer, CallSignal signal) async {
    final raw = signal.data['candidates'];
    final list = raw is List ? raw : const [];
    for (final entry in list) {
      if (entry is! Map) continue;
      final candidate = entry['candidate'];
      if (candidate is! String || candidate.isEmpty) continue;
      final ice = RTCIceCandidate(
        candidate,
        entry['sdpMid'] as String?,
        (entry['sdpMLineIndex'] as num?)?.toInt(),
      );
      try {
        // Candidates routinely arrive before the remote description.
        // Adding one then throws, so they are held and drained after
        // setRemoteDescription instead of being dropped — dropping them
        // is a call that connects only on the easiest networks.
        if (await peer.hasRemoteDescription) {
          await peer.pc.addCandidate(ice);
        } else {
          peer.pending.add(ice);
        }
      } catch (e) {
        debugPrint('MeshCallTransport: addCandidate(${peer.id}) failed: $e');
      }
    }
  }

  void _flushCandidates(String peerId, List<Map<String, dynamic>> batch) {
    if (batch.isEmpty) return;
    _emit(TransportSignal(peerId, CallSignalType.ice, {'candidates': batch}));
  }

  void _onPeerConnectionState(_Peer peer, RTCPeerConnectionState state) {
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        peer.everConnected = true;
        _emit(PeerStateChanged(peer.id, PeerMediaState.connected));
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        // NOT a failure. This is what a lift, a tunnel or a Wi-Fi
        // handover looks like, and ICE usually recovers on its own
        // within a few seconds. Hanging up here is the single most
        // common way a calling app feels broken.
        _emit(PeerStateChanged(peer.id, PeerMediaState.reconnecting));
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        _emit(PeerStateChanged(peer.id, PeerMediaState.failed));
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        _emit(PeerStateChanged(peer.id, PeerMediaState.closed));
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateNew:
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        _emit(
          PeerStateChanged(
            peer.id,
            peer.everConnected
                ? PeerMediaState.reconnecting
                : PeerMediaState.connecting,
          ),
        );
        break;
    }
  }

  // ---- controls ----------------------------------------------------------

  @override
  Future<void> setMuted(bool muted) async {
    _muted = muted;
    _applyMuteToTracks();
  }

  void _applyMuteToTracks() {
    final stream = _localStream;
    if (stream == null) return;
    for (final track in stream.getAudioTracks()) {
      // `enabled = false` stops frames being captured AND sent — the
      // track goes to silence at the source. Nothing is transmitted
      // while muted, which is the property that makes a mute button
      // trustworthy rather than cosmetic.
      track.enabled = !_muted;
    }
  }

  @override
  Future<void> restartIce() async {
    for (final peer in _peers.values) {
      try {
        // Only the offering side may restart, or both ends restart at
        // once and collide.
        if (selfUserId.compareTo(peer.id) < 0) {
          await peer.pc.restartIce();
          await _makeOffer(peer, renegotiate: true);
        }
      } catch (e) {
        debugPrint('MeshCallTransport: ICE restart for ${peer.id} failed: $e');
      }
    }
  }

  @override
  Future<CallMediaStats> stats() async {
    var relayed = false;
    var sent = 0;
    var received = 0;
    double? rtt;
    int? lost;

    for (final peer in _peers.values) {
      try {
        final reports = await peer.pc.getStats();
        for (final report in reports) {
          final values = report.values;
          if (report.type == 'candidate-pair' &&
              (values['state'] == 'succeeded' || values['nominated'] == true)) {
            final bytesSent = values['bytesSent'];
            final bytesRecv = values['bytesReceived'];
            if (bytesSent is num) sent += bytesSent.toInt();
            if (bytesRecv is num) received += bytesRecv.toInt();
            final trip = values['currentRoundTripTime'];
            if (trip is num) rtt = trip.toDouble() * 1000;
          }
          // `relay` on either end of the selected pair means the media
          // is going through TURN, i.e. through bandwidth we pay for.
          if (report.type == 'local-candidate' ||
              report.type == 'remote-candidate') {
            if (values['candidateType'] == 'relay') relayed = true;
          }
          if (report.type == 'inbound-rtp') {
            final packetsLost = values['packetsLost'];
            if (packetsLost is num) lost = (lost ?? 0) + packetsLost.toInt();
          }
        }
      } catch (e) {
        debugPrint('MeshCallTransport: getStats(${peer.id}) failed: $e');
      }
    }

    return CallMediaStats(
      relayed: relayed,
      bytesSent: sent,
      bytesReceived: received,
      roundTripMs: rtt,
      packetsLost: lost,
    );
  }

  @override
  PeerMediaState get aggregateState {
    if (_peers.isEmpty) return PeerMediaState.connecting;
    var sawConnected = false;
    var sawReconnecting = false;
    var sawConnecting = false;
    for (final peer in _peers.values) {
      switch (peer.state) {
        case PeerMediaState.connected:
          sawConnected = true;
          break;
        case PeerMediaState.reconnecting:
          sawReconnecting = true;
          break;
        case PeerMediaState.connecting:
          sawConnecting = true;
          break;
        case PeerMediaState.failed:
        case PeerMediaState.closed:
          break;
      }
    }
    // Worst-wins, except that one peer being up is enough to call the
    // call connected in a group — in a 1:1 there is only one peer, so
    // the two rules agree.
    if (sawReconnecting) return PeerMediaState.reconnecting;
    if (sawConnected) return PeerMediaState.connected;
    if (sawConnecting) return PeerMediaState.connecting;
    return PeerMediaState.failed;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    for (final id in _peers.keys.toList()) {
      await _removePeer(id);
    }
    _peers.clear();

    // The microphone, in the order that actually releases it: stop each
    // track, THEN dispose the stream. Disposing without stopping leaves
    // the capture session open on Android, which is the "the mic stayed
    // on after the call" bug.
    final stream = _localStream;
    _localStream = null;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      try {
        await stream.dispose();
      } catch (_) {}
    }

    if (!_events.isClosed) await _events.close();
  }

  void _emit(TransportEvent event) {
    if (event is PeerStateChanged) {
      _peers[event.peerId]?.state = event.state;
    }
    if (!_events.isClosed) _events.add(event);
  }

  /// Nudge Opus towards "voice call" rather than "music stream".
  ///
  /// Three settings, all of which matter on a Zimbabwean mobile
  /// connection:
  ///
  ///   maxaveragebitrate  24 kbit/s. Speech is fully intelligible well
  ///                      below this; the default lets Opus climb far
  ///                      higher for no gain on a voice call, and in a
  ///                      mesh that overspend is multiplied by the
  ///                      number of peers.
  ///   useinbandfec       forward error correction, so a lost packet is
  ///                      reconstructed instead of heard as a gap.
  ///   usedtx             stop transmitting during silence. In a group
  ///                      call most participants are silent most of the
  ///                      time, which is where most of the saving is.
  ///
  /// Editing SDP by hand is unlovely, and it is how this is done —
  /// there is no cross-platform API for these. Written defensively: any
  /// SDP it does not recognise is returned untouched, so a WebRTC
  /// upgrade that changes the format degrades to default Opus rather
  /// than producing a description nothing can parse.
  static String _tuneOpus(String sdp) {
    if (sdp.isEmpty) return sdp;
    try {
      final opusPayload = RegExp(
        r'^a=rtpmap:(\d+)\s+opus/48000',
        multiLine: true,
        caseSensitive: false,
      ).firstMatch(sdp)?.group(1);
      if (opusPayload == null) return sdp;

      const wanted =
          'maxaveragebitrate=24000;stereo=0;sprop-stereo=0;'
          'useinbandfec=1;usedtx=1';

      final fmtpPattern = RegExp(
        '^a=fmtp:$opusPayload (.*)\$',
        multiLine: true,
      );
      final existing = fmtpPattern.firstMatch(sdp);
      if (existing != null) {
        final params = existing.group(1) ?? '';
        if (params.contains('maxaveragebitrate')) return sdp;
        return sdp.replaceFirst(
          existing.group(0)!,
          'a=fmtp:$opusPayload $params;$wanted',
        );
      }

      // No fmtp line yet — add one directly after the rtpmap.
      final rtpmapLine = RegExp(
        '^a=rtpmap:$opusPayload opus/48000.*\$',
        multiLine: true,
        caseSensitive: false,
      ).firstMatch(sdp);
      if (rtpmapLine == null) return sdp;
      return sdp.replaceFirst(
        rtpmapLine.group(0)!,
        '${rtpmapLine.group(0)}\r\na=fmtp:$opusPayload $wanted',
      );
    } catch (e) {
      debugPrint('MeshCallTransport: SDP tuning skipped: $e');
      return sdp;
    }
  }

  @visibleForTesting
  static String debugTuneOpus(String sdp) => _tuneOpus(sdp);

  @visibleForTesting
  int get debugPeerCount => _peers.length;
}

/// One peer connection plus the bookkeeping it needs.
class _Peer {
  _Peer({required this.id, required this.pc});

  final String id;
  final RTCPeerConnection pc;

  PeerMediaState state = PeerMediaState.connecting;

  /// Distinguishes "never came up" from "came up and dropped". Only the
  /// second one deserves "Reconnecting…".
  bool everConnected = false;
  bool hasRemoteAudio = false;

  /// Candidates that arrived before the remote description. Held rather
  /// than dropped — see [_handleIce].
  final List<RTCIceCandidate> pending = [];

  final List<Map<String, dynamic>> _outbound = [];
  Timer? _batchTimer;

  Future<bool> get hasRemoteDescription async {
    try {
      return (await pc.getRemoteDescription()) != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> drainPendingCandidates() async {
    if (pending.isEmpty) return;
    final queued = List<RTCIceCandidate>.from(pending);
    pending.clear();
    for (final candidate in queued) {
      try {
        await pc.addCandidate(candidate);
      } catch (e) {
        debugPrint('_Peer($id): queued candidate rejected: $e');
      }
    }
  }

  /// Batch outbound candidates over a short window.
  ///
  /// A phone on a dual-stack network emits twenty-odd candidates in a
  /// couple of hundred milliseconds. One broadcast each is twenty
  /// realtime messages per peer per call, and in a five-way mesh that
  /// is eighty — enough to matter for both the signalling ceiling and
  /// the socket. 150 ms collapses them into two or three messages and
  /// is far below anything a caller could perceive.
  void queueCandidate(
    Map<String, dynamic> candidate,
    void Function(String peerId, List<Map<String, dynamic>> batch) flush,
  ) {
    _outbound.add(candidate);
    _batchTimer?.cancel();
    _batchTimer = Timer(const Duration(milliseconds: 150), () {
      final batch = List<Map<String, dynamic>>.from(_outbound);
      _outbound.clear();
      flush(id, batch);
    });
  }

  void dispose() {
    _batchTimer?.cancel();
    _batchTimer = null;
    _outbound.clear();
    pending.clear();
    pc.onIceCandidate = null;
    pc.onConnectionState = null;
    pc.onTrack = null;
  }
}
