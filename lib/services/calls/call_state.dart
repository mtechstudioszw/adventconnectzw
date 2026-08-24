import '../../models/call_model.dart';

/// Where this device thinks the call is.
///
/// Richer than the server's three states on purpose. `connecting` and
/// `reconnecting` are facts about ONE device's media stack, not about
/// the call — pushing them to the server would make every participant's
/// row churn every time somebody walked past a lift, and would let a
/// client assert something about a call it does not own.
enum CallPhase {
  /// No call. The only state from which a new one can start.
  idle,

  /// Outgoing: the start RPC is in flight. Nothing is ringing yet, and
  /// the call may still be refused (busy, blocked, rate-limited).
  initiating,

  /// Outgoing: their phone is ringing.
  ringing,

  /// Incoming: our phone is ringing.
  incoming,

  /// Answered, media negotiating. No audio yet.
  connecting,

  /// Audio is flowing.
  connected,

  /// Was connected, lost the path, trying to recover. NOT a failure —
  /// a tunnel or a Wi-Fi handover lands here and usually comes back.
  reconnecting,

  // ---- terminal ---------------------------------------------------------
  /// Finished normally, or was ended by someone.
  ended,

  /// Declined — by them if outgoing, by us if incoming.
  rejected,

  /// Rang out.
  missed,

  /// Could not be set up, or the media never came up.
  failed,

  /// They were already on another call.
  busy,
}

extension CallPhaseX on CallPhase {
  bool get isTerminal =>
      this == CallPhase.ended ||
      this == CallPhase.rejected ||
      this == CallPhase.missed ||
      this == CallPhase.failed ||
      this == CallPhase.busy;

  /// A call is "live" when it owns the microphone and the screen.
  bool get isLive =>
      this == CallPhase.initiating ||
      this == CallPhase.ringing ||
      this == CallPhase.incoming ||
      this == CallPhase.connecting ||
      this == CallPhase.connected ||
      this == CallPhase.reconnecting;

  /// Whether the call timer should be running.
  bool get countsTime =>
      this == CallPhase.connected || this == CallPhase.reconnecting;

  /// The line under the caller's name. Every state has one — the brief's
  /// rule was that nobody should ever be left looking at an indefinite
  /// loading screen, and an unlabelled spinner is exactly that.
  String get label => switch (this) {
    CallPhase.idle => '',
    CallPhase.initiating => 'Preparing…',
    CallPhase.ringing => 'Ringing…',
    CallPhase.incoming => 'Incoming call',
    CallPhase.connecting => 'Connecting…',
    CallPhase.connected => 'Connected',
    CallPhase.reconnecting => 'Reconnecting…',
    CallPhase.ended => 'Call ended',
    CallPhase.rejected => 'Call declined',
    CallPhase.missed => 'No answer',
    CallPhase.failed => 'Call failed',
    CallPhase.busy => 'On another call',
  };
}

/// The legal moves.
///
/// ## Why this is a table and not a pile of `if`s
///
/// The specific bug this prevents: a call that has already ended must
/// not become connected again because a delayed packet arrived. Media
/// and signalling are both asynchronous and both can deliver something
/// seconds late — an ICE state change from a peer connection that is
/// already being torn down, a heartbeat reply for a call the member has
/// hung up, a CallKit `accept` for a call that rang out while the phone
/// was in a pocket. Every one of those tries to move the state.
///
/// With the moves in a table, "terminal states are absorbing" is one
/// line of data rather than a rule every call site has to remember.
const Map<CallPhase, Set<CallPhase>> kCallTransitions = {
  CallPhase.idle: {
    CallPhase.initiating,
    CallPhase.incoming,
    // Recovery after a force-quit: the server says we are already in a
    // call, so the app rejoins one in progress.
    CallPhase.connecting,
    CallPhase.connected,
  },
  CallPhase.initiating: {
    CallPhase.ringing,
    // A call to somebody already in the room (rejoining a group call)
    // goes straight to negotiating.
    CallPhase.connecting,
    CallPhase.ended,
    CallPhase.rejected,
    CallPhase.busy,
    CallPhase.failed,
  },
  CallPhase.ringing: {
    CallPhase.connecting,
    CallPhase.connected,
    CallPhase.ended,
    CallPhase.rejected,
    CallPhase.missed,
    CallPhase.busy,
    CallPhase.failed,
  },
  CallPhase.incoming: {
    CallPhase.connecting,
    CallPhase.ended,
    CallPhase.rejected,
    CallPhase.missed,
    CallPhase.failed,
  },
  CallPhase.connecting: {
    CallPhase.connected,
    CallPhase.reconnecting,
    CallPhase.ended,
    CallPhase.failed,
  },
  CallPhase.connected: {
    CallPhase.reconnecting,
    CallPhase.ended,
    CallPhase.failed,
  },
  CallPhase.reconnecting: {
    CallPhase.connected,
    CallPhase.ended,
    CallPhase.failed,
  },
  // Terminal states are absorbing. The ONLY way out is [CallPhase.idle],
  // which the service reaches by explicitly clearing the call once the
  // member has seen the outcome — never by a late event.
  CallPhase.ended: {CallPhase.idle},
  CallPhase.rejected: {CallPhase.idle},
  CallPhase.missed: {CallPhase.idle},
  CallPhase.failed: {CallPhase.idle},
  CallPhase.busy: {CallPhase.idle},
};

bool canTransition(CallPhase from, CallPhase to) {
  if (from == to) return true; // idempotent re-entry is always fine
  return kCallTransitions[from]?.contains(to) ?? false;
}

/// Everything a call screen needs to paint itself, in one immutable
/// value so a rebuild can never see half an update.
class CallUiState {
  const CallUiState({
    required this.phase,
    this.session,
    this.outgoing = false,
    this.muted = false,
    this.elapsed = Duration.zero,
    this.failureMessage,
    this.peerName,
    this.peerPhotoUrl,
    this.speakingPeers = const {},
  });

  final CallPhase phase;

  /// The server's view. Null before the start RPC returns, and kept
  /// after the call ends so the outcome screen can name who it was with.
  final CallSession? session;

  final bool outgoing;
  final bool muted;

  /// Time since the call genuinely connected. Zero while ringing — the
  /// timer must never count time nobody could hear.
  final Duration elapsed;

  /// Set on a terminal phase when there is something to explain.
  /// Written server-side wherever a refusal is involved, so it never
  /// leaks WHY someone is unreachable.
  final String? failureMessage;

  /// Who this call is with, for the moments before (or after) a
  /// snapshot exists — the outgoing screen paints instantly instead of
  /// waiting a round trip for a name it already knows.
  final String? peerName;
  final String? peerPhotoUrl;

  /// Who is talking right now, for the speaking ring in the group grid.
  final Set<String> speakingPeers;

  bool get isGroup => session?.isGroup ?? false;

  static const idle = CallUiState(phase: CallPhase.idle);

  CallUiState copyWith({
    CallPhase? phase,
    CallSession? session,
    bool? outgoing,
    bool? muted,
    Duration? elapsed,
    String? failureMessage,
    String? peerName,
    String? peerPhotoUrl,
    Set<String>? speakingPeers,
    bool clearFailure = false,
  }) {
    return CallUiState(
      phase: phase ?? this.phase,
      session: session ?? this.session,
      outgoing: outgoing ?? this.outgoing,
      muted: muted ?? this.muted,
      elapsed: elapsed ?? this.elapsed,
      failureMessage: clearFailure
          ? null
          : (failureMessage ?? this.failureMessage),
      peerName: peerName ?? this.peerName,
      peerPhotoUrl: peerPhotoUrl ?? this.peerPhotoUrl,
      speakingPeers: speakingPeers ?? this.speakingPeers,
    );
  }
}
