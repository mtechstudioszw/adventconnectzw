/// Wire models for audio calling.
///
/// Everything here mirrors what `call_snapshot` / `call_history` /
/// `call_my_usage` return (database/patch_261_calls_rpcs.sql). The
/// server is the authority on every one of these fields — the client
/// never invents a status, a duration or a participant list, it renders
/// what it was told. If a field here disagrees with the RPC, the RPC is
/// right and this file is the bug.
library;

/// Where a call is, as far as the SERVER is concerned.
///
/// Deliberately smaller than [CallPhase]: `connecting` and
/// `reconnecting` are properties of one device's media stack, not facts
/// about the call, and pushing them to the server would make every
/// participant's row churn every time somebody walked past a lift.
enum CallStatus { ringing, active, ended, unknown }

/// One member's part in a call.
enum ParticipantStatus {
  invited,
  ringing,
  joined,
  left,
  rejected,
  missed,
  busy,
  failed,
  removed,
  unknown,
}

/// Why a call stopped. Drives the wording in history and on the
/// end-of-call screen, so every value here needs a human sentence.
enum CallEndReason {
  completed,
  rejected,
  cancelled,
  missed,
  busy,
  unreachable,
  failed,
  maxDuration,
  quota,
  stale,
  admin,
  unknown,
}

CallStatus _callStatus(String? raw) => switch (raw) {
  'ringing' => CallStatus.ringing,
  'active' => CallStatus.active,
  'ended' => CallStatus.ended,
  _ => CallStatus.unknown,
};

ParticipantStatus _participantStatus(String? raw) => switch (raw) {
  'invited' => ParticipantStatus.invited,
  'ringing' => ParticipantStatus.ringing,
  'joined' => ParticipantStatus.joined,
  'left' => ParticipantStatus.left,
  'rejected' => ParticipantStatus.rejected,
  'missed' => ParticipantStatus.missed,
  'busy' => ParticipantStatus.busy,
  'failed' => ParticipantStatus.failed,
  'removed' => ParticipantStatus.removed,
  _ => ParticipantStatus.unknown,
};

CallEndReason _endReason(String? raw) => switch (raw) {
  'completed' => CallEndReason.completed,
  'rejected' => CallEndReason.rejected,
  'cancelled' => CallEndReason.cancelled,
  'missed' => CallEndReason.missed,
  'busy' => CallEndReason.busy,
  'unreachable' => CallEndReason.unreachable,
  'failed' => CallEndReason.failed,
  'max_duration' => CallEndReason.maxDuration,
  'quota' => CallEndReason.quota,
  'stale' => CallEndReason.stale,
  'admin' => CallEndReason.admin,
  _ => CallEndReason.unknown,
};

DateTime? _parseTime(Object? raw) {
  if (raw == null) return null;
  return DateTime.tryParse(raw.toString())?.toUtc();
}

/// A refusal from one of the call RPCs.
///
/// The RPCs return `{"error": CODE, "message": TEXT}` instead of
/// raising, because several refusals have to leave a row behind — a
/// call to someone who is busy still belongs in both people's history,
/// and an exception would roll that away with it. See the header of
/// patch_261.
class CallFailure implements Exception {
  const CallFailure(this.code, this.message);

  final String code;

  /// Already written for a member to read. Server-side on purpose: the
  /// refusal for "they blocked you", "their privacy setting says no"
  /// and "that account is gone" is deliberately one identical sentence,
  /// and deciding that here would leak the difference.
  final String message;

  /// Ceilings the member will get past by waiting.
  bool get isTransient =>
      code == 'RATE_LIMITED' ||
      code == 'RECIPIENT_BUSY' ||
      code == 'ALREADY_IN_CALL' ||
      code == 'CALL_FULL';

  /// Out of minutes. Distinct from [isTransient] because the fix is
  /// different — waiting for tomorrow, or Premium.
  bool get isQuota => code == 'QUOTA_EXCEEDED' || code == 'QUOTA_REACHED';

  @override
  String toString() => 'CallFailure($code): $message';
}

/// One member in a call.
class CallParticipant {
  const CallParticipant({
    required this.userId,
    required this.name,
    required this.status,
    required this.isCaller,
    this.photoUrl,
    this.muted = false,
    this.joinedAt,
  });

  final String userId;
  final String name;
  final String? photoUrl;
  final ParticipantStatus status;
  final bool isCaller;

  /// Muted state as the SERVER last heard it (from `call_heartbeat`), so
  /// it can lag a second or two. The local member's own microphone
  /// state is read from [CallService], never from here.
  final bool muted;

  final DateTime? joinedAt;

  /// In the room right now.
  bool get isActive => status == ParticipantStatus.joined;

  /// Still being alerted — the caller's screen shows these as "Ringing…".
  bool get isPending =>
      status == ParticipantStatus.invited || status == ParticipantStatus.ringing;

  /// Gone, one way or another. Terminal.
  bool get isGone => !isActive && !isPending;

  factory CallParticipant.fromJson(Map<String, dynamic> json) {
    return CallParticipant(
      userId: (json['user_id'] ?? '').toString(),
      name: ((json['name'] as String?)?.trim().isNotEmpty ?? false)
          ? (json['name'] as String).trim()
          : 'Member',
      photoUrl: json['photo_url'] as String?,
      status: _participantStatus(json['status'] as String?),
      isCaller: json['role'] == 'caller',
      muted: json['muted'] == true,
      joinedAt: _parseTime(json['joined_at']),
    );
  }
}

/// A live call, exactly as the server describes it.
class CallSession {
  const CallSession({
    required this.id,
    required this.isGroup,
    required this.status,
    required this.createdBy,
    required this.startedAt,
    required this.maxParticipants,
    required this.myStatus,
    required this.participants,
    this.roomToken,
    this.conversationId,
    this.connectedAt,
    this.endedAt,
    this.ringExpiresAt,
    this.hardExpiresAt,
    this.endReason = CallEndReason.unknown,
  });

  final String id;
  final bool isGroup;
  final CallStatus status;
  final String createdBy;
  final String? conversationId;

  /// The Realtime signalling topic is `call:$roomToken`.
  ///
  /// **This is a capability, not a name.** The server withholds it the
  /// moment this member stops being a live participant, so a client
  /// that captured it earlier cannot rejoin the channel. Never log it,
  /// never put it in a notification, never derive it from [id].
  final String? roomToken;

  final DateTime startedAt;
  final DateTime? connectedAt;
  final DateTime? endedAt;
  final DateTime? ringExpiresAt;
  final DateTime? hardExpiresAt;
  final int maxParticipants;
  final ParticipantStatus myStatus;
  final CallEndReason endReason;
  final List<CallParticipant> participants;

  bool get isOver => status == CallStatus.ended;

  /// The billing clock. Starts at [connectedAt] — the first moment two
  /// people were actually in the room — and never at invite or ring.
  Duration get elapsed {
    final start = connectedAt;
    if (start == null) return Duration.zero;
    final end = endedAt ?? DateTime.now().toUtc();
    final d = end.difference(start);
    return d.isNegative ? Duration.zero : d;
  }

  List<CallParticipant> get active =>
      participants.where((p) => p.isActive).toList();

  List<CallParticipant> get pending =>
      participants.where((p) => p.isPending).toList();

  CallParticipant? get caller {
    for (final p in participants) {
      if (p.isCaller) return p;
    }
    return null;
  }

  /// Everyone but me. What the call screen actually renders.
  List<CallParticipant> othersFor(String myUserId) =>
      participants.where((p) => p.userId != myUserId).toList();

  /// The peers this device should hold a media connection to.
  ///
  /// Joined participants only. A member who is still ringing has no
  /// media stack to talk to yet, and one who has left must be torn
  /// down — driving the mesh off this list is what stops a peer
  /// connection outliving the participant it belonged to.
  List<String> peerIdsFor(String myUserId) => participants
      .where((p) => p.isActive && p.userId != myUserId)
      .map((p) => p.userId)
      .toList();

  factory CallSession.fromJson(Map<String, dynamic> json) {
    final rawParticipants = json['participants'];
    return CallSession(
      id: (json['id'] ?? '').toString(),
      isGroup: json['kind'] == 'group',
      status: _callStatus(json['status'] as String?),
      createdBy: (json['created_by'] ?? '').toString(),
      conversationId: json['conversation_id']?.toString(),
      roomToken: json['room_token'] as String?,
      startedAt: _parseTime(json['started_at']) ?? DateTime.now().toUtc(),
      connectedAt: _parseTime(json['connected_at']),
      endedAt: _parseTime(json['ended_at']),
      ringExpiresAt: _parseTime(json['ring_expires_at']),
      hardExpiresAt: _parseTime(json['hard_expires_at']),
      maxParticipants: (json['max_participants'] as num?)?.toInt() ?? 2,
      myStatus: _participantStatus(json['my_status'] as String?),
      endReason: _endReason(json['end_reason'] as String?),
      participants: rawParticipants is List
          ? rawParticipants
                .whereType<Map>()
                .map((p) => CallParticipant.fromJson(p.cast<String, dynamic>()))
                .toList()
          : const [],
    );
  }
}

/// One row in the Calls tab.
class CallHistoryEntry {
  const CallHistoryEntry({
    required this.id,
    required this.isGroup,
    required this.outgoing,
    required this.startedAt,
    required this.durationSeconds,
    required this.myStatus,
    required this.endReason,
    required this.others,
    this.groupName,
    this.conversationId,
    this.connectedAt,
  });

  final String id;
  final bool isGroup;
  final bool outgoing;
  final DateTime startedAt;
  final DateTime? connectedAt;
  final int durationSeconds;
  final ParticipantStatus myStatus;
  final CallEndReason endReason;
  final List<CallParticipant> others;
  final String? groupName;
  final String? conversationId;

  /// A call that never reached [connectedAt] did not happen, whatever
  /// its end reason says. This is the single question the row's icon
  /// and colour are decided by.
  bool get answered => connectedAt != null;

  /// Red in the list, and the only state that reads as needing action.
  /// A call *I* placed that nobody answered is not a missed call — it
  /// is an unanswered one, and colouring it red would put a permanent
  /// alarm on my own history.
  bool get missed =>
      !outgoing &&
      !answered &&
      (myStatus == ParticipantStatus.missed ||
          endReason == CallEndReason.missed ||
          endReason == CallEndReason.cancelled ||
          endReason == CallEndReason.stale);

  bool get declined =>
      myStatus == ParticipantStatus.rejected ||
      (outgoing && endReason == CallEndReason.rejected);

  /// Who this row is *about*. For a 1:1 that is the other person; for a
  /// group it is the group's name.
  String get title {
    if (isGroup) return groupName ?? 'Group call';
    if (others.isEmpty) return 'Unknown';
    return others.first.name;
  }

  /// The single other person, when there is exactly one — the tap
  /// target for "call back". Null for group calls.
  CallParticipant? get peer =>
      !isGroup && others.length == 1 ? others.first : null;

  factory CallHistoryEntry.fromJson(Map<String, dynamic> json) {
    final rawOthers = json['others'];
    return CallHistoryEntry(
      id: (json['id'] ?? '').toString(),
      isGroup: json['kind'] == 'group',
      outgoing: json['outgoing'] == true,
      startedAt: _parseTime(json['started_at']) ?? DateTime.now().toUtc(),
      connectedAt: _parseTime(json['connected_at']),
      durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
      myStatus: _participantStatus(json['my_status'] as String?),
      endReason: _endReason(json['end_reason'] as String?),
      groupName: json['group_name'] as String?,
      conversationId: json['conversation_id']?.toString(),
      others: rawOthers is List
          ? rawOthers
                .whereType<Map>()
                .map((p) => CallParticipant.fromJson(p.cast<String, dynamic>()))
                .toList()
          : const [],
    );
  }
}

/// Minutes used against the ceiling in force for this member.
class CallUsage {
  const CallUsage({
    required this.todaySeconds,
    required this.monthSeconds,
    required this.dailyLimitSeconds,
    required this.monthlyLimitSeconds,
    required this.premium,
  });

  final int todaySeconds;
  final int monthSeconds;
  final int dailyLimitSeconds;
  final int monthlyLimitSeconds;
  final bool premium;

  static const empty = CallUsage(
    todaySeconds: 0,
    monthSeconds: 0,
    dailyLimitSeconds: 7200,
    monthlyLimitSeconds: 90000,
    premium: false,
  );

  double get dailyFraction => dailyLimitSeconds <= 0
      ? 0
      : (todaySeconds / dailyLimitSeconds).clamp(0.0, 1.0);

  /// Deliberately 0.8, not 1.0. A ceiling that announces itself only at
  /// the moment it bites is a ceiling that reads as a bug.
  bool get nearDailyLimit => dailyFraction >= 0.8;

  bool get dailyExhausted => todaySeconds >= dailyLimitSeconds;
  bool get monthlyExhausted => monthSeconds >= monthlyLimitSeconds;

  factory CallUsage.fromJson(Map<String, dynamic> json) => CallUsage(
    todaySeconds: (json['today_seconds'] as num?)?.toInt() ?? 0,
    monthSeconds: (json['month_seconds'] as num?)?.toInt() ?? 0,
    dailyLimitSeconds: (json['daily_limit_seconds'] as num?)?.toInt() ?? 7200,
    monthlyLimitSeconds:
        (json['monthly_limit_seconds'] as num?)?.toInt() ?? 90000,
    premium: json['premium'] == true,
  );
}
