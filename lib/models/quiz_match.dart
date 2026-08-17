import 'quiz_question_model.dart';

/// The other player in a live match, under their quiz identity.
class QuizMatchOpponent {
  const QuizMatchOpponent({
    required this.userId,
    required this.name,
    required this.photoUrl,
    required this.isVerified,
  });

  final String userId;
  final String name;
  final String? photoUrl;
  final bool isVerified;

  static QuizMatchOpponent? fromJson(Map<String, dynamic>? json) {
    if (json == null || json['user_id'] == null) return null;
    return QuizMatchOpponent(
      userId: json['user_id'].toString(),
      name: (json['name'] ?? 'Player').toString(),
      photoUrl: json['photo'] as String?,
      isVerified: json['verified'] == true,
    );
  }
}

/// A live head-to-head match, exactly as the server is willing to describe
/// it — the questions arrive with `correct_index` blanked to -1 and the real
/// key never leaves the database. What the player just answered comes back
/// from [QuizMatchService.answer] instead, once the answer is locked.
class QuizMatch {
  QuizMatch({
    required this.id,
    required this.status,
    required this.questions,
    required this.questionCount,
    required this.secondsPerQuestion,
    required this.currentIndex,
    required this.questionStartedAt,
    required this.resolvedAt,
    required this.playerA,
    required this.playerB,
    required this.aPoints,
    required this.bPoints,
    required this.aCorrect,
    required this.bCorrect,
    required this.aAnsweredIndex,
    required this.bAnsweredIndex,
    required this.winnerId,
    required this.forfeitedBy,
    required this.opponent,
    required this.clockSkew,
    this.revealedIndex,
    this.myChoice,
    this.aReady = false,
    this.bReady = false,
    this.readyDeadline,
    this.scoresHidden = false,
  });

  /// Ready check (patch_203). A pairing is provisional until BOTH players
  /// confirm — the match sits in `ready`, and crucially the question clock
  /// does not start. Before this, joining a match set it `active` and
  /// stamped `question_started_at` in the same statement, so the player who
  /// had been waiting lost time on question one while still looking at a
  /// "searching" spinner.
  final bool aReady;
  final bool bReady;

  /// When the ready check expires. Past this the server cancels the match
  /// and frees whichever player did confirm.
  final DateTime? readyDeadline;

  /// True while the opponent's score is deliberately withheld — the server
  /// returns null for it until the match is over. Without this flag a
  /// withheld score parses to 0 and reads as a real score of zero.
  final bool scoresHidden;

  /// The correct option for the current question — non-null only once the
  /// question has closed for BOTH players. This is what lets the reveal
  /// work for someone who ran out of time and so never got an answer
  /// response to learn it from.
  final int? revealedIndex;

  /// What I picked on the current question, from the server. Only used to
  /// redraw correctly after a reconnect; the live path already knows.
  final int? myChoice;

  final String id;

  /// open | invited | active | complete | cancelled
  final String status;

  final List<QuizQuestion> questions;
  final int questionCount;
  final int secondsPerQuestion;
  final int currentIndex;

  /// When the server started the current question. Every countdown is
  /// derived from this, never from when the packet happened to arrive —
  /// otherwise a 300ms slower connection silently loses every race.
  final DateTime? questionStartedAt;

  /// Non-null while the question is closed and both screens are showing
  /// the reveal. The server advances on its own schedule after this.
  final DateTime? resolvedAt;

  final String playerA;
  final String? playerB;
  final int aPoints;
  final int bPoints;
  final int aCorrect;
  final int bCorrect;

  /// The highest question index each player has locked. Says *that* they
  /// answered, never *what* — which is why it is safe to show live.
  final int aAnsweredIndex;
  final int bAnsweredIndex;

  final String? winnerId;
  final String? forfeitedBy;
  final QuizMatchOpponent? opponent;

  /// `serverNow - deviceNow` at the moment this snapshot was parsed.
  ///
  /// Applied to every clock reading below, so a phone whose own clock is
  /// minutes out still counts down in step with its opponent. Without it
  /// the two players would see different amounts of time on the same
  /// question, which is the same unfairness as timing from packet arrival.
  final Duration clockSkew;

  bool get isWaiting => status == 'open' || status == 'invited';
  bool get isActive => status == 'active';
  bool get isOver => status == 'complete' || status == 'cancelled';
  bool get isRevealing => resolvedAt != null;

  /// Paired, but nobody is committed yet and no clock is running.
  bool get isReadyCheck => status == 'ready';

  /// Have I confirmed? Drives which half of the prompt is still live.
  bool iAmReady(String? uid) => amPlayerA(uid) ? aReady : bReady;
  bool theyAreReady(String? uid) => amPlayerA(uid) ? bReady : aReady;

  /// Seconds left to confirm, server-corrected like every other clock here.
  int get readySecondsLeft {
    final d = readyDeadline;
    if (d == null) return 0;
    return d.difference(serverNow).inSeconds.clamp(0, 60);
  }

  QuizQuestion? get question =>
      currentIndex >= 0 && currentIndex < questions.length
          ? questions[currentIndex]
          : null;

  /// Server time as this device best understands it.
  DateTime get serverNow => DateTime.now().add(clockSkew);

  /// How much of the current question's clock is left, 1.0 → 0.0.
  double get remainingFraction {
    final started = questionStartedAt;
    if (started == null || secondsPerQuestion <= 0) return 1;
    final elapsed = serverNow.difference(started).inMilliseconds;
    final total = secondsPerQuestion * 1000;
    return (1 - elapsed / total).clamp(0.0, 1.0);
  }

  bool amPlayerA(String? uid) => uid != null && uid == playerA;

  int myPoints(String? uid) => amPlayerA(uid) ? aPoints : bPoints;
  int theirPoints(String? uid) => amPlayerA(uid) ? bPoints : aPoints;
  int myCorrect(String? uid) => amPlayerA(uid) ? aCorrect : bCorrect;
  int theirCorrect(String? uid) => amPlayerA(uid) ? bCorrect : aCorrect;

  /// Have I locked an answer to the question on screen?
  bool iAnswered(String? uid) =>
      (amPlayerA(uid) ? aAnsweredIndex : bAnsweredIndex) >= currentIndex;

  /// Has the opponent? Drives the "they've answered" pip — the pressure
  /// that makes a live round feel live.
  bool theyAnswered(String? uid) =>
      (amPlayerA(uid) ? bAnsweredIndex : aAnsweredIndex) >= currentIndex;

  /// 1 = I won, 0 = draw, -1 = I lost. Null until the match is complete.
  int? outcomeFor(String? uid) {
    if (status != 'complete' || uid == null) return null;
    if (winnerId == null) return 0;
    return winnerId == uid ? 1 : -1;
  }

  bool iForfeited(String? uid) => forfeitedBy != null && forfeitedBy == uid;
  bool theyForfeited(String? uid) =>
      forfeitedBy != null && uid != null && forfeitedBy != uid;

  factory QuizMatch.fromJson(Map<String, dynamic> json) {
    final rawQuestions = json['questions'];
    final serverNow = DateTime.tryParse(json['server_now']?.toString() ?? '');
    return QuizMatch(
      id: json['id'].toString(),
      status: (json['status'] ?? 'open').toString(),
      questions: rawQuestions is List
          ? rawQuestions
              .map((e) => QuizQuestion.fromJson(e as Map<String, dynamic>))
              .toList()
          : const [],
      questionCount: (json['question_count'] as num?)?.toInt() ?? 0,
      secondsPerQuestion:
          (json['seconds_per_question'] as num?)?.toInt() ?? 15,
      currentIndex: (json['current_index'] as num?)?.toInt() ?? 0,
      questionStartedAt:
          DateTime.tryParse(json['question_started_at']?.toString() ?? ''),
      resolvedAt: DateTime.tryParse(json['resolved_at']?.toString() ?? ''),
      playerA: json['player_a'].toString(),
      playerB: json['player_b']?.toString(),
      aPoints: (json['a_points'] as num?)?.toInt() ?? 0,
      bPoints: (json['b_points'] as num?)?.toInt() ?? 0,
      aCorrect: (json['a_correct'] as num?)?.toInt() ?? 0,
      bCorrect: (json['b_correct'] as num?)?.toInt() ?? 0,
      aAnsweredIndex: (json['a_answered_index'] as num?)?.toInt() ?? -1,
      bAnsweredIndex: (json['b_answered_index'] as num?)?.toInt() ?? -1,
      winnerId: json['winner_id']?.toString(),
      forfeitedBy: json['forfeited_by']?.toString(),
      opponent:
          QuizMatchOpponent.fromJson(json['opponent'] as Map<String, dynamic>?),
      clockSkew: serverNow == null
          ? Duration.zero
          : serverNow.difference(DateTime.now()),
      revealedIndex: (json['revealed_index'] as num?)?.toInt(),
      myChoice: (json['my_choice'] as num?)?.toInt(),
      aReady: json['a_ready'] == true,
      bReady: json['b_ready'] == true,
      readyDeadline:
          DateTime.tryParse(json['ready_deadline']?.toString() ?? ''),
      // Absent on a server that predates patch_203, which is the same
      // deployment where nothing is withheld — so false is the right
      // default and the score fields below stay meaningful.
      scoresHidden: json['scores_hidden'] == true,
    );
  }

  /// Re-reads a row that arrived over Realtime.
  ///
  /// A `postgres_changes` payload is the raw table row: it has no
  /// `server_now`, no `opponent`, and its `questions` still carry the
  /// blanked key. So the durable parts of the previous snapshot are carried
  /// forward rather than re-fetched — a round trip per push would defeat
  /// the point of the subscription.
  QuizMatch mergeRealtimeRow(Map<String, dynamic> row) {
    final nextStatus = (row['status'] ?? status).toString();
    // Decide from the INCOMING status, not the current one. Reading the old
    // value here meant the row that flips the match to `complete` was still
    // treated as hidden, so the final totals were dropped and the reveal
    // never happened — the scores simply stayed blank at the end.
    final nextHidden = nextStatus != 'complete';
    return QuizMatch(
        id: id,
        status: nextStatus,
        questions: questions,
        questionCount:
            (row['question_count'] as num?)?.toInt() ?? questionCount,
        secondsPerQuestion:
            (row['seconds_per_question'] as num?)?.toInt() ?? secondsPerQuestion,
        currentIndex: (row['current_index'] as num?)?.toInt() ?? currentIndex,
        questionStartedAt:
            DateTime.tryParse(row['question_started_at']?.toString() ?? '') ??
                questionStartedAt,
        resolvedAt: DateTime.tryParse(row['resolved_at']?.toString() ?? ''),
        playerA: (row['player_a'] ?? playerA).toString(),
        playerB: row['player_b']?.toString() ?? playerB,
        // Scores are deliberately NOT taken from a Realtime row while they
        // are hidden.
        //
        // `quiz_match_view` withholds the opponent's total until the match
        // is over, but Realtime delivers the RAW table row — which carries
        // a_points and b_points in full. Merging them here would hand back
        // exactly what the view is withholding, and the hiding would be
        // decorative. Own score still moves: the answer response carries it.
        //
        // Once the match completes, `scores_hidden` goes false and the final
        // totals merge normally, which is what reveals them.
        aPoints: nextHidden
            ? aPoints
            : (row['a_points'] as num?)?.toInt() ?? aPoints,
        bPoints: nextHidden
            ? bPoints
            : (row['b_points'] as num?)?.toInt() ?? bPoints,
        aCorrect: nextHidden
            ? aCorrect
            : (row['a_correct'] as num?)?.toInt() ?? aCorrect,
        bCorrect: nextHidden
            ? bCorrect
            : (row['b_correct'] as num?)?.toInt() ?? bCorrect,
        aAnsweredIndex:
            (row['a_answered_index'] as num?)?.toInt() ?? aAnsweredIndex,
        bAnsweredIndex:
            (row['b_answered_index'] as num?)?.toInt() ?? bAnsweredIndex,
        winnerId: row['winner_id']?.toString(),
        forfeitedBy: row['forfeited_by']?.toString(),
        opponent: opponent,
        clockSkew: clockSkew,
        aReady: row['a_ready'] == true || aReady,
        bReady: row['b_ready'] == true || bReady,
        readyDeadline:
            DateTime.tryParse(row['ready_deadline']?.toString() ?? '') ??
                readyDeadline,
        // The raw row has no `scores_hidden` — it is a view-only field — so
        // it is derived from the status the row DID carry.
        scoresHidden: nextHidden,
      );
  }
}

/// What the server hands back once an answer is locked — and the only route
/// by which a client ever learns the correct index.
class QuizMatchAnswerResult {
  const QuizMatchAnswerResult({
    required this.match,
    required this.correct,
    required this.correctIndex,
    required this.points,
    required this.combo,
  });

  final QuizMatch match;
  final bool correct;
  final int correctIndex;
  final int points;
  final int combo;

  factory QuizMatchAnswerResult.fromJson(Map<String, dynamic> json) =>
      QuizMatchAnswerResult(
        match: QuizMatch.fromJson(json),
        correct: json['correct'] == true,
        correctIndex: (json['correct_index'] as num?)?.toInt() ?? -1,
        points: (json['points'] as num?)?.toInt() ?? 0,
        combo: (json['combo'] as num?)?.toInt() ?? 0,
      );
}

/// A player's public quiz identity.
class QuizProfile {
  const QuizProfile({
    required this.userId,
    required this.displayName,
    required this.photoUrl,
  });

  final String userId;
  final String displayName;
  final String? photoUrl;

  factory QuizProfile.fromJson(Map<String, dynamic> json) => QuizProfile(
        userId: json['user_id'].toString(),
        displayName: (json['display_name'] ?? 'Player').toString(),
        photoUrl: json['photo_url'] as String?,
      );
}

/// Someone who can be challenged to a live match.
class QuizPlayer {
  const QuizPlayer({
    required this.userId,
    required this.name,
    required this.photoUrl,
    required this.isVerified,
    required this.isOnline,
    required this.weekPoints,
  });

  final String userId;
  final String name;
  final String? photoUrl;
  final bool isVerified;
  final bool isOnline;
  final int weekPoints;

  factory QuizPlayer.fromJson(Map<String, dynamic> json) => QuizPlayer(
        userId: json['user_id'].toString(),
        name: (json['full_name'] ?? 'Player').toString(),
        photoUrl: json['photo_url'] as String?,
        isVerified: json['is_verified'] == true,
        isOnline: json['is_online'] == true,
        weekPoints: (json['week_points'] as num?)?.toInt() ?? 0,
      );
}

/// A live invite waiting for me.
class QuizMatchInvite {
  const QuizMatchInvite({
    required this.matchId,
    required this.fromId,
    required this.fromName,
    required this.fromPhoto,
    required this.createdAt,
  });

  final String matchId;
  final String fromId;
  final String fromName;
  final String? fromPhoto;
  final DateTime createdAt;

  factory QuizMatchInvite.fromJson(Map<String, dynamic> json) =>
      QuizMatchInvite(
        matchId: json['match_id'].toString(),
        fromId: json['from_id'].toString(),
        fromName: (json['from_name'] ?? 'Player').toString(),
        fromPhoto: json['from_photo'] as String?,
        createdAt:
            DateTime.tryParse(json['created_at']?.toString() ?? '') ??
                DateTime.now(),
      );
}
