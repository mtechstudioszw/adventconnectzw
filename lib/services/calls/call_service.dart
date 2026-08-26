import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/call_model.dart';
import 'call_api.dart';
import 'call_audio.dart';
import 'call_config.dart';
import 'call_signaling.dart';
import 'call_state.dart';
import 'call_tones.dart';
import 'call_transport.dart';
import 'callkit_bridge.dart';
import 'missed_call_badge.dart';
import 'mesh_call_transport.dart';

/// Raised when the microphone is not available. Carries whether the
/// member can still fix it in-app or has to go to Settings, because
/// those are two different screens with two different buttons.
class MicrophoneDenied implements Exception {
  const MicrophoneDenied({required this.permanently});
  final bool permanently;
}

/// The one live call, and everything that keeps it honest.
///
/// ## The rule this file exists to enforce
///
/// **The server owns the call; this device owns its own media.** Every
/// question about who is in the call, whether it has ended, and how
/// long it ran is answered by a snapshot from the database. Every
/// question about microphones, peer connections and audio routing is
/// answered here. When the two disagree, the server wins — which is why
/// [_applySnapshot] can end a call this device still thinks is running,
/// and why nothing here ever asserts a call state upward.
///
/// ## Why it is a singleton
///
/// Because a phone has one microphone. Two call objects would each
/// think they owned it, and the loser leaves a capture session open —
/// the "the mic stayed on after the call" bug, which is the worst one
/// this feature can have. `call.max_concurrent_calls` enforces the same
/// thing server-side so a second device cannot do it either.
class CallService {
  CallService._();

  static SupabaseClient get _client => Supabase.instance.client;
  static String? get _myId => _client.auth.currentUser?.id;

  /// What the UI paints. Never mutated in place — a rebuild must never
  /// be able to see half an update.
  static final ValueNotifier<CallUiState> state =
      ValueNotifier<CallUiState>(CallUiState.idle);

  static CallUiState get value => state.value;
  static bool get isBusy => state.value.phase.isLive;

  /// Fires when a call needs to be put on screen. `main.dart` listens
  /// and pushes the call route — navigation does not belong in a
  /// service, but knowing that a call started does.
  static final _screenRequests = StreamController<String>.broadcast();
  static Stream<String> get onShowCallScreen => _screenRequests.stream;

  static CallTransport? _transport;
  static CallSignaling? _signaling;
  static StreamSubscription<TransportEvent>? _transportSub;
  static StreamSubscription<CallKitEvent>? _callKitSub;
  static StreamSubscription<List<ConnectivityResult>>? _networkSub;

  static Timer? _heartbeatTimer;
  static Timer? _tickTimer;
  static Timer? _ringTimeout;
  static Timer? _ringPoll;
  static Timer? _connectTimeout;

  static bool _initialized = false;
  static bool _leaving = false;

  /// Bumped every time a call ends. Async continuations capture it and
  /// re-check after awaiting, so a slow round trip belonging to a
  /// finished call cannot write into the next one.
  static int _generation = 0;

  /// Last network class we told the server about, so the heartbeat only
  /// carries it when it changes.
  static ConnectivityResult? _lastNetwork;

  // =======================================================================
  //  Lifecycle
  // =======================================================================

  /// Wire up the parts that must exist before a call can arrive. Called
  /// from `main.dart` after the session is restored. Idempotent.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await CallKitBridge.initialize();
    _callKitSub?.cancel();
    _callKitSub = CallKitBridge.events.listen(_onCallKitEvent);

    unawaited(CallConfig.refresh());
    unawaited(CallKitBridge.registerDevice());

    // Reconcile with the server on start: a call the app was in when it
    // was force-quit either still exists (rejoin it) or does not (clear
    // the system UI that is still showing it).
    unawaited(recoverActiveCall());
  }

  /// Ask the server what call, if any, this member is in.
  ///
  /// Called on cold start and on every resume. This is what stops a
  /// ghost call surviving a force-quit — the app asks rather than
  /// trusting whatever was in memory.
  static Future<void> recoverActiveCall() async {
    if (_myId == null) return;
    try {
      final session = await CallApi.current();

      if (session == null) {
        // Nothing live. Any system call UI still on screen is a ghost.
        final stale = await CallKitBridge.activeCallIds();
        for (final id in stale) {
          await CallKitBridge.reportEnded(id);
        }
        if (value.phase.isLive) {
          await _finish(CallPhase.ended, message: null);
        }
        return;
      }

      // Already tracking this call — nothing to recover.
      if (value.session?.id == session.id && value.phase.isLive) return;

      if (session.myStatus == ParticipantStatus.joined) {
        // We were in the room. Rejoin the media rather than dropping
        // the member out of a call that is still running for everyone
        // else.
        await _resumeJoinedCall(session);
      } else if (session.myStatus == ParticipantStatus.invited ||
          session.myStatus == ParticipantStatus.ringing) {
        await _presentIncoming(session);
      }
    } catch (e) {
      debugPrint('CallService.recoverActiveCall failed: $e');
    }
  }

  // =======================================================================
  //  Placing a call
  // =======================================================================

  /// Ring one person.
  ///
  /// Throws [CallFailure] when the server refuses (blocked, not
  /// connected, busy, rate-limited, out of minutes) and
  /// [MicrophoneDenied] when the member will not grant the microphone.
  /// Both carry a sentence that is safe to show.
  static Future<void> startDirect({
    required String userId,
    required String displayName,
    String? photoUrl,
    String? conversationId,
  }) async {
    await _startCall(
      outgoing: true,
      peerName: displayName,
      peerPhotoUrl: photoUrl,
      place: () =>
          CallApi.startDirect(userId: userId, conversationId: conversationId),
    );
  }

  /// Start — or join, if one is already running — the call for a group.
  static Future<void> startGroup({
    required String conversationId,
    required String groupName,
    String? photoUrl,
    List<String>? inviteUserIds,
  }) async {
    await _startCall(
      outgoing: true,
      peerName: groupName,
      peerPhotoUrl: photoUrl,
      place: () => CallApi.startGroup(
        conversationId: conversationId,
        inviteUserIds: inviteUserIds,
      ),
    );
  }

  static Future<void> _startCall({
    required bool outgoing,
    required String peerName,
    String? peerPhotoUrl,
    required Future<CallSession> Function() place,
  }) async {
    if (_myId == null) {
      throw const CallFailure('NOT_AUTHENTICATED', 'Please sign in.');
    }
    if (!CallConfig.enabled) {
      throw const CallFailure(
        'DISABLED',
        'Calling is temporarily unavailable. Please try again later.',
      );
    }
    if (isBusy) {
      throw const CallFailure('ALREADY_IN_CALL', 'You are already on a call.');
    }

    // The microphone is asked for HERE — at the moment the member taps
    // call — and never on launch. A permissions prompt on first open,
    // for a feature nobody has touched yet, is how apps get denied
    // permanently.
    await _ensureMicrophone();

    _generation++;
    _leaving = false;
    _set(
      CallUiState(
        phase: CallPhase.initiating,
        outgoing: outgoing,
        peerName: peerName,
        peerPhotoUrl: peerPhotoUrl,
      ),
    );
    // Explicit, because this phase arrives through _set rather than
    // _transition — an outgoing call has no previous phase to move from,
    // so _syncRingback never sees it otherwise.
    //
    // Started HERE and not on `ringing`: `place()` below is a network
    // round trip, and on a slow connection it is seconds of silence
    // during which the member has no evidence their tap did anything.
    // That silence is what the founder heard.
    _syncRingback(CallPhase.initiating);
    _screenRequests.add('');

    final generation = _generation;
    CallSession session;
    try {
      session = await place();
    } catch (e) {
      if (generation != _generation) return;
      // A refusal is a terminal state with a sentence, not a silent
      // return to idle — the member tapped a button and is owed an
      // answer.
      final message = e is CallFailure ? e.message : 'Could not start the call.';
      final phase = switch (e) {
        CallFailure(code: 'RECIPIENT_BUSY') => CallPhase.busy,
        _ => CallPhase.failed,
      };
      await _finish(phase, message: message);
      rethrow;
    }

    if (generation != _generation) return;

    // The server may already have ended it — an unreachable group, or a
    // callee who was busy (which still creates the row so both people
    // get honest history).
    if (session.isOver) {
      _set(value.copyWith(session: session));
      await _finish(_phaseForEndReason(session.endReason), message: null);
      return;
    }

    _set(value.copyWith(session: session, phase: CallPhase.ringing));
    _syncRingback(CallPhase.ringing);

    // BEFORE _goLive, deliberately. This is the only thing that will
    // tell us the callee declined, and _goLive is three network round
    // trips and a microphone away. See CallConfig.ringPoll.
    _startRingPoll();

    await CallKitBridge.reportOutgoing(
      callId: session.id,
      peerName: peerName,
      peerPhoto: peerPhotoUrl,
      isGroup: session.isGroup,
    );

    await _goLive(session, startMuted: false);
    _armRingTimeout(session);
  }

  // =======================================================================
  //  Receiving a call
  // =======================================================================

  /// An incoming call arrived — from a push, from CallKit, or from the
  /// recovery sweep. Idempotent for the same call id, because a push
  /// and a Realtime event routinely both land.
  static Future<void> presentIncoming(String callId) async {
    if (value.session?.id == callId && value.phase.isLive) return;
    if (isBusy) {
      // Already on another call. `call.max_concurrent_calls` means the
      // server has already answered this one with 'busy' — nothing to
      // show, and showing it would put a second call screen over a live
      // call.
      await CallKitBridge.reportEnded(callId);
      return;
    }
    final session = await CallApi.current();
    if (session == null || session.id != callId) {
      // Rang out, was cancelled, or belongs to a different account on
      // this handset. Clear the system UI rather than leaving a call
      // screen for a call that does not exist.
      await CallKitBridge.reportEnded(callId);
      return;
    }
    await _presentIncoming(session);
  }

  static Future<void> _presentIncoming(CallSession session) async {
    final caller = session.caller;
    _generation++;
    _leaving = false;
    _set(
      CallUiState(
        phase: CallPhase.incoming,
        session: session,
        outgoing: false,
        peerName: session.isGroup ? 'Group call' : (caller?.name ?? 'Member'),
        peerPhotoUrl: caller?.photoUrl,
      ),
    );

    await CallKitBridge.showIncoming(
      callId: session.id,
      callerName: session.isGroup
          ? '${caller?.name ?? 'Someone'} · Group call'
          : (caller?.name ?? 'Member'),
      callerPhoto: caller?.photoUrl,
      isGroup: session.isGroup,
    );

    _screenRequests.add(session.id);

    // Tell the caller the phone is genuinely alerting. Dispatching a
    // push proves nothing — FCM queues for offline devices — so their
    // screen only says "Ringing" once this lands.
    unawaited(_safe(() => CallApi.ringAck(session.id)));

    _armRingTimeout(session);
  }

  /// Answer. Opens the microphone, then joins the media.
  static Future<void> accept() async {
    final session = value.session;
    if (session == null || value.phase != CallPhase.incoming) return;

    try {
      await _ensureMicrophone();
    } catch (e) {
      // Cannot answer without a microphone. Decline honestly rather
      // than joining a call the member cannot speak on.
      await _safe(() => CallApi.reject(session.id));
      await _finish(
        CallPhase.failed,
        message: 'Adventist Super App needs microphone access to take calls.',
      );
      rethrow;
    }

    final generation = _generation;
    _transition(CallPhase.connecting);

    try {
      final updated = await CallApi.accept(session.id);
      if (generation != _generation) return;
      if (updated.isOver) {
        await _finish(_phaseForEndReason(updated.endReason), message: null);
        return;
      }
      _set(value.copyWith(session: updated));

      // Tell the system call UI this was answered NOW, not once WebRTC
      // media happens to connect. flutter_callkit_incoming decides
      // whether to fire its own "Missed call" system notification based
      // on whether IT was ever told the call was answered — and
      // setCallConnected() is the only thing that tells it. Members can
      // (and do) accept from the in-app screen rather than the native
      // CallKit sheet, so if this waited for ICE to connect there was a
      // real window where a normal hang-up right after answering would
      // race ahead of that signal and the callee's phone would show a
      // native "Missed call" notification for a call that connected and
      // ran fine. This is deliberately in addition to, not instead of,
      // the later reportConnected() call in _reconcileMediaState — that
      // one drives the system call TIMER, which should still start when
      // audio actually comes up.
      final callId = updated.id;
      unawaited(CallKitBridge.reportConnected(callId));

      await _goLive(updated, startMuted: false);
      _armConnectTimeout();
    } on CallFailure catch (e) {
      if (generation != _generation) return;
      await _finish(
        e.code == 'CALL_OVER' ? CallPhase.missed : CallPhase.failed,
        message: e.message,
      );
    }
  }

  /// Decline an incoming call.
  static Future<void> reject() async {
    final session = value.session;
    if (session == null) {
      await _finish(CallPhase.rejected, message: null);
      return;
    }
    await _safe(() => CallApi.reject(session.id));
    await _finish(CallPhase.rejected, message: null);
  }

  // =======================================================================
  //  Ending
  // =======================================================================

  /// Hang up. In a 1:1 this ends the call; in a group it leaves without
  /// ending it for everyone else.
  static Future<void> hangUp() async {
    final session = value.session;
    if (session == null) {
      await _finish(CallPhase.ended, message: null);
      return;
    }
    if (_leaving) return;
    _leaving = true;

    // Tell the peers directly as well as the server. The signal is an
    // optimisation — their screens drop instantly instead of waiting
    // for a heartbeat — and never the source of truth.
    await _safe(() => _signaling?.broadcast(CallSignalType.bye, const {}));

    if (value.phase == CallPhase.ringing && session.connectedAt == null) {
      await _safe(() => CallApi.cancel(session.id));
    } else {
      await _safe(() => CallApi.leave(session.id));
    }
    await _finish(CallPhase.ended, message: null);
  }

  /// End the call for EVERY participant. The server re-checks that this
  /// member is allowed to; hiding the button is a courtesy, not the
  /// control.
  static Future<void> endForAll() async {
    final session = value.session;
    if (session == null) return;
    if (_leaving) return;
    _leaving = true;
    await _safe(() => CallApi.endForAll(session.id));
    await _finish(CallPhase.ended, message: null);
  }

  /// Host removes someone from a group call.
  static Future<void> removeParticipant(String userId) async {
    final session = value.session;
    if (session == null) return;
    final updated = await _safe(
      () => CallApi.removeParticipant(session.id, userId),
    );
    if (updated != null) await _applySnapshot(updated);
  }

  /// Clear a finished call so the UI can dismiss and the next one can
  /// start. The ONLY exit from a terminal phase.
  static void dismiss() {
    if (!value.phase.isTerminal) return;
    _set(CallUiState.idle);
  }

  // =======================================================================
  //  Controls
  // =======================================================================

  static Future<void> setMuted(bool muted) async {
    final transport = _transport;
    if (transport == null) return;
    await transport.setMuted(muted);
    _set(value.copyWith(muted: muted));
    // Peers first (instant), server second (durable).
    await _safe(
      () => _signaling?.broadcast(CallSignalType.mute, {'muted': muted}),
    );
    final session = value.session;
    if (session != null) {
      unawaited(_safe(() => CallApi.heartbeat(session.id, muted: muted)));
    }
  }

  static Future<void> toggleMute() => setMuted(!value.muted);

  static Future<void> setAudioRoute(AudioRoute route) =>
      CallAudio.setRoute(route);

  static Future<void> toggleSpeaker() => CallAudio.toggleSpeaker();

  // =======================================================================
  //  Going live: media + signalling
  // =======================================================================

  static Future<void> _goLive(
    CallSession session, {
    required bool startMuted,
  }) async {
    final myId = _myId;
    final token = session.roomToken;
    if (myId == null || token == null || token.isEmpty) {
      await _finish(
        CallPhase.failed,
        message: 'Could not join the call. Please try again.',
      );
      return;
    }

    final generation = _generation;

    // Audio session first: on both platforms the session has to be in
    // communication mode BEFORE the microphone is opened, or the
    // earpiece is unavailable and echo cancellation does not engage.
    await CallAudio.begin(preferSpeaker: session.isGroup);

    final signaling = CallSignaling(selfUserId: myId);
    _signaling = signaling;

    try {
      await signaling.connect(
        roomToken: token,
        onSignal: _onSignal,
        onPresence: _onPresence,
        onChannelState: _onChannelState,
      );
    } catch (e) {
      if (generation != _generation) return;
      // A private channel that will not join almost always means
      // patch_262 is not applied. Failing loudly here is right: the
      // alternative is a call that connects and carries no audio.
      debugPrint('CallService: signalling channel failed: $e');
      await _safe(() => CallApi.leave(session.id));
      await _finish(
        CallPhase.failed,
        message: 'Could not reach the call service. Please try again.',
      );
      return;
    }

    if (generation != _generation) {
      await signaling.disconnect();
      return;
    }

    final ice = await CallApi.iceServers(session.id);
    if (generation != _generation) return;

    final transport = MeshCallTransport(selfUserId: myId);
    _transport = transport;
    _transportSub = transport.events.listen(_onTransportEvent);

    try {
      await transport.start(ice: ice, startMuted: startMuted);
    } catch (e) {
      if (generation != _generation) return;
      debugPrint('CallService: microphone failed to open: $e');
      await _safe(() => CallApi.leave(session.id));
      await _finish(
        CallPhase.failed,
        message: 'Could not open the microphone. Please try again.',
      );
      return;
    }

    if (generation != _generation) return;

    await transport.setPeers(session.peerIdsFor(myId));

    _startHeartbeat();
    _startTicker();
    _watchNetwork();
  }

  /// Rejoin a call the server says we are already in — after a
  /// force-quit, or a crash mid-call.
  static Future<void> _resumeJoinedCall(CallSession session) async {
    _generation++;
    _leaving = false;
    final caller = session.caller;
    _set(
      CallUiState(
        phase: CallPhase.connecting,
        session: session,
        outgoing: session.createdBy == _myId,
        peerName: session.isGroup ? 'Group call' : (caller?.name ?? 'Member'),
        peerPhotoUrl: caller?.photoUrl,
      ),
    );
    _screenRequests.add(session.id);
    await _goLive(session, startMuted: false);
    _armConnectTimeout();
  }

  // =======================================================================
  //  Inbound events
  // =======================================================================

  static void _onSignal(CallSignal signal) {
    final session = value.session;
    if (session == null) return;

    // The identity check the signalling layer cannot do.
    //
    // Realtime broadcast carries no verified sender, so `from` is a
    // claim. RLS proves the sender is *a* live participant of this
    // call; it does not prove they are *the* one they say they are. So
    // every signal is checked against the SERVER's roster, and anything
    // from an id that is not a joined participant is dropped. See the
    // class docs on CallSignaling.
    final known = session.participants.any(
      (p) => p.userId == signal.from && !p.isGone,
    );
    if (!known) {
      debugPrint('CallService: dropped signal from unknown ${signal.from}');
      return;
    }

    switch (signal.type) {
      case CallSignalType.mute:
        // Cosmetic only — the authoritative value arrives on the next
        // snapshot. Applied immediately so the grid does not lag.
        break;
      case CallSignalType.speaking:
        final speaking = Set<String>.from(value.speakingPeers);
        if (signal.data['speaking'] == true) {
          speaking.add(signal.from);
        } else {
          speaking.remove(signal.from);
        }
        _set(value.copyWith(speakingPeers: speaking));
        break;
      default:
        unawaited(_safe(() => _transport?.handleSignal(signal)));
        break;
    }
  }

  static void _onPresence(Set<String> present) {
    // Somebody joined or left the room. Presence is faster than the
    // heartbeat, so use it as a trigger to re-read the authoritative
    // roster rather than as the roster itself.
    final session = value.session;
    if (session == null || !value.phase.isLive) return;
    unawaited(_refreshSnapshot());
  }

  static void _onChannelState(bool connected) {
    if (connected || !value.phase.isLive) return;
    // The signalling socket dropped. Media may well still be fine —
    // WebRTC does not need the channel once connected — so this is not
    // a reason to end the call. The heartbeat is the backstop.
    debugPrint('CallService: signalling channel lost; media continues');
  }

  static void _onTransportEvent(TransportEvent event) {
    switch (event) {
      case TransportSignal(:final peerId, :final type, :final data):
        unawaited(_safe(() => _signaling?.sendTo(peerId, type, data)));
        break;

      case PeerStateChanged():
        _reconcileMediaState();
        break;

      case LocalAudioLevel(:final level):
        final speaking = level > 0.12;
        final myId = _myId;
        if (myId == null) break;
        final current = value.speakingPeers.contains(myId);
        if (speaking != current) {
          unawaited(
            _safe(
              () => _signaling?.broadcast(CallSignalType.speaking, {
                'speaking': speaking,
              }),
            ),
          );
        }
        break;
    }
  }

  /// Fold the media stack's aggregate state into the call phase.
  static void _reconcileMediaState() {
    final transport = _transport;
    if (transport == null || !value.phase.isLive) return;

    switch (transport.aggregateState) {
      case PeerMediaState.connected:
        if (value.phase != CallPhase.connected) {
          _transition(CallPhase.connected);
          _connectTimeout?.cancel();
          final id = value.session?.id;
          if (id != null) unawaited(CallKitBridge.reportConnected(id));
        }
        break;
      case PeerMediaState.reconnecting:
        _transition(CallPhase.reconnecting);
        break;
      case PeerMediaState.failed:
        // Only fatal if we never got audio at all. A group call where
        // one leg fails carries on with the rest, and the failed peer
        // is dropped by the roster.
        if (value.phase == CallPhase.connecting) {
          unawaited(
            _finish(
              CallPhase.failed,
              message: 'Could not connect the call. Please try again.',
            ),
          );
        }
        break;
      case PeerMediaState.connecting:
      case PeerMediaState.closed:
        break;
    }
  }

  static void _onCallKitEvent(CallKitEvent event) {
    switch (event.action) {
      case CallKitAction.accept:
        if (value.session?.id == event.callId &&
            value.phase == CallPhase.incoming) {
          unawaited(accept());
        } else {
          // Accepted from the lock screen before the app had state.
          unawaited(() async {
            await presentIncoming(event.callId);
            if (value.session?.id == event.callId) await accept();
          }());
        }
        break;
      case CallKitAction.decline:
        if (value.session?.id == event.callId) {
          unawaited(reject());
        } else {
          unawaited(_safe(() => CallApi.reject(event.callId)));
          unawaited(CallKitBridge.reportEnded(event.callId));
        }
        break;
      case CallKitAction.ended:
        if (value.session?.id == event.callId && value.phase.isLive) {
          unawaited(hangUp());
        }
        break;
      case CallKitAction.timeout:
        if (value.session?.id == event.callId) {
          unawaited(_finish(CallPhase.missed, message: null));
        }
        break;
      case CallKitAction.toggleMute:
        final muted = event.muted;
        if (muted != null && value.session?.id == event.callId) {
          unawaited(setMuted(muted));
        }
        break;
      case CallKitAction.callback:
        // "Call back" on a missed-call notification. Surfaced to the UI
        // layer, which knows how to route.
        _screenRequests.add('callback:${event.callId}');
        break;
    }
  }

  // =======================================================================
  //  Timers
  // =======================================================================

  static void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      CallConfig.heartbeat,
      (_) => unawaited(_refreshSnapshot()),
    );
  }

  /// One round trip that does three jobs: proves this device is alive,
  /// carries the relay telemetry that makes TURN cost measurable, and
  /// brings back the authoritative snapshot.
  ///
  /// The third is why this is also the backstop for the whole
  /// signalling layer — a device whose Realtime socket has been down
  /// for a minute still learns, within one heartbeat, that three people
  /// joined and one left.
  static Future<void> _refreshSnapshot() async {
    final session = value.session;
    if (session == null || !value.phase.isLive) return;
    final generation = _generation;

    CallMediaStats stats = CallMediaStats.empty;
    try {
      stats = await _transport?.stats() ?? CallMediaStats.empty;
    } catch (_) {}

    final updated = await _safe(
      () => CallApi.heartbeat(
        session.id,
        muted: value.muted,
        network: _networkLabel(),
        relayed: stats.relayed,
      ),
    );
    if (updated == null || generation != _generation) return;
    await _applySnapshot(updated);
  }

  /// The server's word, applied over ours.
  static Future<void> _applySnapshot(CallSession session) async {
    if (!value.phase.isLive) return;
    _set(value.copyWith(session: session));

    if (session.isOver) {
      await _finish(_phaseForEndReason(session.endReason), message: null);
      return;
    }

    // Someone removed us mid-call.
    if (session.myStatus == ParticipantStatus.removed) {
      await _finish(
        CallPhase.ended,
        message: 'You were removed from this call.',
      );
      return;
    }

    // The peer set is driven straight off the roster, which is what
    // stops a peer connection outliving the participant it belongs to.
    final myId = _myId;
    if (myId != null) {
      await _safe(() => _transport?.setPeers(session.peerIdsFor(myId)));
    }

    // Outgoing call that has been answered: the ring window is over.
    // _transition below stops the ringback.
    if (value.phase == CallPhase.ringing && session.connectedAt != null) {
      _ringTimeout?.cancel();
      _stopRingPoll();
      _transition(CallPhase.connecting);
      _armConnectTimeout();
    }

    // The hard per-call ceiling. Enforced server-side too (the sweeper
    // ends it), but leaving cleanly here means the member sees a proper
    // end-of-call screen rather than the call simply vanishing.
    final hardExpiry = session.hardExpiresAt;
    if (hardExpiry != null && DateTime.now().toUtc().isAfter(hardExpiry)) {
      await _safe(() => CallApi.leave(session.id));
      await _finish(
        CallPhase.ended,
        message: 'This call reached the maximum length.',
      );
    }
  }

  /// Ask the server, every couple of seconds, what has become of the
  /// call we are ringing.
  ///
  /// Outgoing only, and only while it rings. Stops itself the moment
  /// the phase moves on, so the normal heartbeat owns a connected call
  /// and the two never both run.
  static void _startRingPoll() {
    _ringPoll?.cancel();
    _ringPoll = Timer.periodic(
      CallConfig.ringPoll,
      (_) => unawaited(_pollWhileRinging()),
    );
  }

  static void _stopRingPoll() {
    _ringPoll?.cancel();
    _ringPoll = null;
  }

  static Future<void> _pollWhileRinging() async {
    final phase = value.phase;
    if (phase != CallPhase.ringing && phase != CallPhase.initiating) {
      _stopRingPoll();
      return;
    }
    final session = value.session;
    if (session == null) return;

    final generation = _generation;
    // The heartbeat RPC rather than call_current(): it takes the call id
    // explicitly and returns the snapshot even once the call is over,
    // which is exactly the case being watched for. `call_current()`
    // answers "what am I in NOW" and comes back null for a call that
    // has just ended — the one answer this poll cannot use.
    //
    // No media stats: the transport may not exist yet. That is fine,
    // they are telemetry and the connected heartbeat carries them.
    final updated = await _safe(
      () => CallApi.heartbeat(
        session.id,
        muted: value.muted,
        network: _networkLabel(),
      ),
    );
    if (updated == null || generation != _generation) return;
    if (updated.id != session.id) return;
    await _applySnapshot(updated);
  }

  /// The caller's own give-up clock, and the callee's rang-out clock.
  static void _armRingTimeout(CallSession session) {
    _ringTimeout?.cancel();
    final expiry = session.ringExpiresAt;
    final remaining = expiry == null
        ? CallConfig.ringTimeout
        : expiry.difference(DateTime.now().toUtc());
    if (remaining.isNegative) {
      unawaited(_onRingTimeout());
      return;
    }
    _ringTimeout = Timer(remaining, () => unawaited(_onRingTimeout()));
  }

  static Future<void> _onRingTimeout() async {
    final session = value.session;
    if (session == null) return;
    if (value.phase == CallPhase.ringing) {
      // Nobody answered. Cancel so the callee's phone stops immediately
      // rather than waiting for the server's sweeper.
      //
      // NOT counted as a missed call for US — this is the outgoing side.
      // A call I placed that went unanswered is an unanswered call, and
      // badging my own call log for it would leave a permanent red dot
      // nobody can act on. Same rule as CallHistoryEntry.missed.
      await _safe(() => CallApi.cancel(session.id));
      await _finish(CallPhase.missed, message: null);
    } else if (value.phase == CallPhase.incoming) {
      // This one IS ours: somebody rang and we did not pick up. Count it
      // now so the dot appears as the ringing stops, rather than on the
      // next inbox open.
      MissedCallBadge.noteMissed();
      await _finish(CallPhase.missed, message: null);
    }
  }

  /// Answered but silent. A call that never produces audio has to end
  /// with an explanation rather than a spinner that never resolves.
  static void _armConnectTimeout() {
    _connectTimeout?.cancel();
    _connectTimeout = Timer(CallConfig.connectTimeout, () {
      if (value.phase == CallPhase.connecting) {
        unawaited(
          () async {
            final id = value.session?.id;
            if (id != null) await _safe(() => CallApi.leave(id));
            await _finish(
              CallPhase.failed,
              message:
                  'Could not connect the audio. Check your connection and '
                  'try again.',
            );
          }(),
        );
      }
    });
  }

  /// Repaints the call timer once a second. Reads [CallSession.elapsed]
  /// rather than counting locally, so the duration comes from the
  /// server's `connected_at` and cannot drift with the device clock.
  static void _startTicker() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!value.phase.countsTime) return;
      final session = value.session;
      if (session == null) return;
      _set(value.copyWith(elapsed: session.elapsed));
    });
  }

  // =======================================================================
  //  Network changes
  // =======================================================================

  /// Watch for Wi-Fi <-> mobile handovers.
  ///
  /// Subscribes to connectivity_plus directly rather than through
  /// ConnectivityService, which only reports online/offline — and a
  /// handover between two working networks is exactly the case that
  /// breaks a call while never once being offline.
  static void _watchNetwork() {
    _networkSub?.cancel();
    _networkSub = Connectivity().onConnectivityChanged.listen((results) {
      final next = results.isEmpty ? ConnectivityResult.none : results.first;
      final previous = _lastNetwork;
      _lastNetwork = next;

      if (!value.phase.isLive) return;
      if (next == ConnectivityResult.none) {
        // Offline. Do NOT hang up — this is usually seconds long, and
        // ICE will recover. The server's stale sweeper is the backstop
        // if it does not.
        _transition(CallPhase.reconnecting);
        return;
      }
      if (previous != null && previous != next) {
        // The interface changed under a live call. An ICE restart
        // renegotiates over the new path in a second or two; tearing
        // the call down and redialling would take far longer and lose
        // the conversation.
        unawaited(_safe(() => _transport?.restartIce()));
        unawaited(_refreshSnapshot());
      }
    });
  }

  static String? _networkLabel() => switch (_lastNetwork) {
    ConnectivityResult.wifi => 'wifi',
    ConnectivityResult.mobile => 'mobile',
    null => null,
    _ => 'other',
  };

  // =======================================================================
  //  Teardown
  // =======================================================================

  /// The single exit. Every terminal path goes through here, which is
  /// what makes "the microphone is always released" one property to
  /// check rather than nine.
  static Future<void> _finish(CallPhase phase, {required String? message}) async {
    _generation++;
    final callId = value.session?.id;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _tickTimer?.cancel();
    _tickTimer = null;
    _ringTimeout?.cancel();
    _ringTimeout = null;
    _stopRingPoll();
    _connectTimeout?.cancel();
    _connectTimeout = null;
    _networkSub?.cancel();
    _networkSub = null;

    // Before anything else that can await: the tone must not outlive the
    // call by the length of a media teardown. This is also the path a
    // REFUSED call takes (busy, blocked, rate-limited), which never
    // reaches a phase transition of its own.
    await _safe(() => CallTones.stopRingback());

    await _transportSub?.cancel();
    _transportSub = null;

    // Order matters: media down (releases the microphone), then the
    // signalling channel, then the audio session (gives focus back so
    // the member's music resumes), then the system call UI.
    final transport = _transport;
    _transport = null;
    if (transport != null) await _safe(() => transport.dispose());

    final signaling = _signaling;
    _signaling = null;
    if (signaling != null) await _safe(() => signaling.disconnect());

    await _safe(() => CallAudio.end());

    if (callId != null) await CallKitBridge.reportEnded(callId);

    _leaving = false;

    final elapsed = value.session?.elapsed ?? value.elapsed;
    _set(
      value.copyWith(
        phase: value.phase.isTerminal ? value.phase : phase,
        elapsed: elapsed,
        failureMessage: message,
        speakingPeers: const {},
      ),
    );
  }

  /// Sign-out, and the app-wide reset. Leaves nothing behind: no
  /// microphone, no channel, no system call UI, no cached config.
  static Future<void> clearOnSignOut() async {
    await _safe(() => CallApi.forgetDevice());
    if (value.phase.isLive) {
      final id = value.session?.id;
      if (id != null) await _safe(() => CallApi.leave(id));
    }
    await _finish(CallPhase.ended, message: null);
    await CallKitBridge.endAll();
    _set(CallUiState.idle);
    CallConfig.reset();
    _lastNetwork = null;
  }

  // =======================================================================
  //  Internals
  // =======================================================================

  static void _set(CallUiState next) {
    state.value = next;
  }

  /// Move to [next] if the state machine allows it. Returns whether it
  /// moved.
  ///
  /// Rejections are logged rather than thrown: a late event trying an
  /// illegal move is EXPECTED — that is what this guards — and throwing
  /// would turn a handled race into a crash.
  static bool _transition(CallPhase next) {
    final current = value.phase;
    if (!canTransition(current, next)) {
      debugPrint('CallService: refused transition $current -> $next');
      return false;
    }
    if (current == next) return true;
    _set(value.copyWith(phase: next));
    _syncRingback(next);
    return true;
  }

  /// The caller's ringback follows the phase, and nothing else.
  ///
  /// Driven from here rather than from the call screen on purpose: the
  /// tone has to stop the instant the call is answered, refused or
  /// cancelled, and a widget can be disposed, rebuilt or backgrounded
  /// at any of those moments. The phase is the one thing that is always
  /// correct, so the sound hangs off it.
  ///
  /// Outgoing only. `incoming` is absent deliberately — the OS rings
  /// for an inbound call through CallKit / the telecom stack, and it
  /// does so even when the app is not running. Ringing again here would
  /// double it.
  static void _syncRingback(CallPhase phase) {
    if (phase == CallPhase.initiating || phase == CallPhase.ringing) {
      unawaited(CallTones.startRingback());
    } else {
      unawaited(CallTones.stopRingback());
    }
  }

  static CallPhase _phaseForEndReason(CallEndReason reason) => switch (reason) {
    CallEndReason.rejected => CallPhase.rejected,
    CallEndReason.busy => CallPhase.busy,
    CallEndReason.missed || CallEndReason.cancelled => CallPhase.missed,
    CallEndReason.failed || CallEndReason.unreachable => CallPhase.failed,
    _ => CallPhase.ended,
  };

  /// Microphone, requested at the moment of use.
  static Future<void> _ensureMicrophone() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return;
    if (status.isPermanentlyDenied || status.isRestricted) {
      throw const MicrophoneDenied(permanently: true);
    }
    final result = await Permission.microphone.request();
    if (result.isGranted) {
      // Only now — after the member has agreed to be in calls at all —
      // is it reasonable to ask about notifications and full-screen
      // intents.
      unawaited(CallKitBridge.ensurePermissions());
      return;
    }
    throw MicrophoneDenied(
      permanently: result.isPermanentlyDenied || result.isRestricted,
    );
  }

  /// Run something whose failure must never take the call with it.
  ///
  /// Takes a nullable future so `_safe(() => _signaling?.disconnect())`
  /// reads naturally at the ~fifteen call sites that touch a component
  /// which may already have been torn down. A null future is simply a
  /// no-op — that component is gone, which is the situation the null
  /// was reporting.
  static Future<T?> _safe<T>(Future<T>? Function() body) async {
    try {
      final future = body();
      if (future == null) return null;
      return await future;
    } catch (e) {
      debugPrint('CallService: suppressed error: $e');
      return null;
    }
  }

  @visibleForTesting
  static void debugSetState(CallUiState next) => _set(next);

  @visibleForTesting
  static bool debugTransition(CallPhase next) => _transition(next);

  @visibleForTesting
  static void debugReset() {
    _generation++;
    _heartbeatTimer?.cancel();
    _tickTimer?.cancel();
    _ringTimeout?.cancel();
    _ringPoll?.cancel();
    _connectTimeout?.cancel();
    _set(CallUiState.idle);
  }
}
