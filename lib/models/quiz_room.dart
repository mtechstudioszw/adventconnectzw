import 'quiz_question_model.dart';

/// A live quiz room for 2 to 5 players (patch_306, 3 Nov 2026).
///
/// Everything here comes from `quiz_room_view` on the server. The answer
/// key never reaches the phone: questions arrive with `correct_index` -1
/// and the right answer is sent as [revealedIndex] only once a question
/// has closed.
class QuizRoom {
  const QuizRoom({
    required this.id,
    required this.code,
    required this.status,
    required this.hostId,
    required this.questions,
    required this.questionCount,
    required this.secondsPerQuestion,
    required this.currentIndex,
    required this.questionStartedAt,
    required this.resolvedAt,
    required this.revealedIndex,
    required this.myChoice,
    required this.players,
    required this.clockSkew,
    this.review = const [],
  });

  static const int maxPlayers = 5;

  final String id;
  final String code;

  /// lobby → active → complete (or cancelled).
  final String status;
  final String hostId;
  final List<QuizQuestion> questions;
  final int questionCount;
  final int secondsPerQuestion;
  final int currentIndex;

  /// When the current question's clock started (server time). For the
  /// first question this is 3 s after the host pressed Start.
  final DateTime? questionStartedAt;

  /// Set once the current question has closed (everyone answered or time
  /// ran out); the answer shows until the server moves on.
  final DateTime? resolvedAt;
  final int? revealedIndex;

  /// What this player picked on the current question (-1 = timed out).
  final int? myChoice;

  /// Sorted by score, best first.
  final List<QuizRoomPlayer> players;

  /// Only once the game is over (patch_308): per question, what this
  /// player chose and what was right. Empty mid-game, by design.
  final List<QuizRoomReviewItem> review;

  /// `serverNow - deviceNow` when this snapshot was parsed, so every phone
  /// counts down from the server's clock, not its own.
  final Duration clockSkew;

  bool get isLobby => status == 'lobby';
  bool get isActive => status == 'active';
  bool get isComplete => status == 'complete';
  bool get isCancelled => status == 'cancelled';
  bool get isRevealing => isActive && resolvedAt != null;

  DateTime get serverNow => DateTime.now().add(clockSkew);

  QuizRoomPlayer? get me {
    for (final p in players) {
      if (p.isMe) return p;
    }
    return null;
  }

  bool isHost(String? userId) => userId != null && userId == hostId;

  /// Players still in the room.
  List<QuizRoomPlayer> get present => [
    for (final p in players)
      if (!p.left) p,
  ];

  bool get isFull => present.length >= maxPlayers;

  QuizQuestion? get question =>
      currentIndex >= 0 && currentIndex < questions.length
      ? questions[currentIndex]
      : null;

  /// True during the opening 3-second countdown.
  bool get inCountdown {
    final s = questionStartedAt;
    return isActive && s != null && serverNow.isBefore(s);
  }

  /// Whole seconds left in the opening countdown (3, 2, 1).
  int get countdownSeconds {
    final s = questionStartedAt;
    if (s == null) return 0;
    final ms = s.difference(serverNow).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  /// 1.0 at the start of a question, 0.0 when its time is up.
  double get remainingFraction {
    final s = questionStartedAt;
    if (s == null || !isActive) return 0;
    final total = secondsPerQuestion * 1000;
    final elapsed = serverNow.difference(s).inMilliseconds;
    if (elapsed <= 0) return 1;
    return (1 - elapsed / total).clamp(0.0, 1.0);
  }

  int get secondsLeft => (remainingFraction * secondsPerQuestion).ceil();

  /// Has this player locked in an answer for the current question?
  bool get iAnswered => me?.answered ?? false;

  /// How many players still in the room have answered this question.
  int get answeredCount => present.where((p) => p.answered).length;

  /// 1-based place of [p] on the board; ties share a place.
  int placeOf(QuizRoomPlayer p) =>
      1 + players.where((o) => o.points > p.points).length;

  factory QuizRoom.fromJson(Map<String, dynamic> json) {
    final serverNow = DateTime.tryParse(json['server_now']?.toString() ?? '');
    final rawQ = json['questions'];
    final rawP = json['players'];
    return QuizRoom(
      id: json['id'].toString(),
      code: (json['code'] ?? '').toString(),
      status: (json['status'] ?? 'lobby').toString(),
      hostId: (json['host_id'] ?? '').toString(),
      questions: rawQ is List
          ? rawQ
                .map((e) => QuizQuestion.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
      questionCount: _int(json['question_count']) ?? 0,
      secondsPerQuestion: _int(json['seconds_per_question']) ?? 15,
      currentIndex: _int(json['current_index']) ?? 0,
      questionStartedAt: _date(json['question_started_at']),
      resolvedAt: _date(json['resolved_at']),
      revealedIndex: _int(json['revealed_index']),
      myChoice: _int(json['my_choice']),
      players: rawP is List
          ? rawP
                .map(
                  (e) => QuizRoomPlayer.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList()
          : const [],
      clockSkew: serverNow == null
          ? Duration.zero
          : serverNow.difference(DateTime.now()),
      review: json['review'] is List
          ? (json['review'] as List)
                .map(
                  (e) =>
                      QuizRoomReviewItem.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList()
          : const [],
    );
  }

  static int? _int(Object? v) =>
      v == null ? null : (v is num ? v.toInt() : int.tryParse(v.toString()));

  static DateTime? _date(Object? v) =>
      v == null ? null : DateTime.tryParse(v.toString());
}

class QuizRoomPlayer {
  const QuizRoomPlayer({
    required this.userId,
    required this.name,
    required this.photoUrl,
    required this.verified,
    required this.points,
    required this.correct,
    required this.answered,
    required this.lastPoints,
    required this.lastCorrect,
    required this.left,
    required this.isMe,
  });

  final String userId;
  final String name;
  final String? photoUrl;
  final bool verified;

  /// As of the last REVEALED question — a score that jumped the instant
  /// someone tapped would tell everyone else they were right.
  final int points;
  final int correct;

  /// Locked in on the current question (no hint whether it was right).
  final bool answered;

  /// What the current question earned; only set during the reveal.
  final int? lastPoints;
  final bool? lastCorrect;

  /// Dropped out mid-game (still shown on the board).
  final bool left;
  final bool isMe;

  factory QuizRoomPlayer.fromJson(Map<String, dynamic> json) => QuizRoomPlayer(
    userId: json['user_id'].toString(),
    name: (json['name'] ?? 'Player').toString(),
    photoUrl: json['photo'] as String?,
    verified: json['verified'] == true,
    points: QuizRoom._int(json['points']) ?? 0,
    correct: QuizRoom._int(json['correct']) ?? 0,
    answered: json['answered'] == true,
    lastPoints: QuizRoom._int(json['last_points']),
    lastCorrect: json['last_correct'] as bool?,
    left: json['left'] == true,
    isMe: json['is_me'] == true,
  );
}

/// One line of the end-of-game "Your answers" list.
class QuizRoomReviewItem {
  const QuizRoomReviewItem({
    required this.index,
    required this.correctIndex,
    required this.myChoice,
    required this.correct,
    required this.points,
  });

  final int index;
  final int correctIndex;

  /// null or -1: no answer (the clock ran out, or they had dropped out).
  final int? myChoice;
  final bool correct;
  final int points;

  bool get answered => myChoice != null && myChoice! >= 0;

  factory QuizRoomReviewItem.fromJson(Map<String, dynamic> json) =>
      QuizRoomReviewItem(
        index: QuizRoom._int(json['index']) ?? 0,
        correctIndex: QuizRoom._int(json['correct_index']) ?? -1,
        myChoice: QuizRoom._int(json['my_choice']),
        correct: json['correct'] == true,
        points: QuizRoom._int(json['points']) ?? 0,
      );
}
