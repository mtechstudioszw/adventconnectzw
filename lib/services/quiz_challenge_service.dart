import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/quiz_question_model.dart';
import '../models/quiz_round.dart';

/// A friend you can challenge.
class QuizOpponent {
  const QuizOpponent({
    required this.userId,
    required this.name,
    required this.photoUrl,
    required this.isVerified,
    required this.hasPendingChallenge,
  });

  final String userId;
  final String name;
  final String? photoUrl;
  final bool isVerified;

  /// True when you already have an unanswered challenge out to them.
  final bool hasPendingChallenge;

  factory QuizOpponent.fromJson(Map<String, dynamic> json) => QuizOpponent(
        userId: json['user_id'].toString(),
        name: (json['full_name'] ?? 'Member').toString(),
        photoUrl: json['photo_url'] as String?,
        isVerified: json['is_verified'] == true,
        hasPendingChallenge: json['pending'] == true,
      );
}

/// A head-to-head challenge, from either side.
class QuizChallenge {
  const QuizChallenge({
    required this.id,
    required this.challengerId,
    required this.opponentId,
    required this.questions,
    required this.challengerPoints,
    required this.challengerCorrect,
    required this.opponentPoints,
    required this.opponentCorrect,
    required this.status,
    required this.createdAt,
    this.otherName = 'Member',
    this.otherPhotoUrl,
  });

  final String id;
  final String challengerId;
  final String opponentId;
  final List<QuizQuestion> questions;
  final int challengerPoints;
  final int challengerCorrect;
  final int? opponentPoints;
  final int? opponentCorrect;
  final String status;
  final DateTime createdAt;

  /// Filled in by [QuizChallengeService] — the *other* player's display
  /// details, whichever side of the challenge you're on.
  final String otherName;
  final String? otherPhotoUrl;

  bool get isPending => status == 'pending';
  bool get isComplete => status == 'complete';

  bool amChallenger(String? uid) => uid != null && uid == challengerId;

  /// Your score and theirs, oriented for the viewer.
  (int, int) scoresFor(String? uid) => amChallenger(uid)
      ? (challengerPoints, opponentPoints ?? 0)
      : (opponentPoints ?? 0, challengerPoints);

  /// 1 = you won, 0 = draw, -1 = you lost. Null while unplayed.
  int? outcomeFor(String? uid) {
    if (!isComplete) return null;
    final (mine, theirs) = scoresFor(uid);
    return mine.compareTo(theirs);
  }

  factory QuizChallenge.fromJson(
    Map<String, dynamic> json, {
    String otherName = 'Member',
    String? otherPhotoUrl,
  }) {
    final raw = json['questions'];
    return QuizChallenge(
      id: json['id'].toString(),
      challengerId: json['challenger_id'].toString(),
      opponentId: json['opponent_id'].toString(),
      questions: raw is List
          ? raw
              .map((e) => QuizQuestion.fromJson(e as Map<String, dynamic>))
              .toList()
          : const [],
      challengerPoints: (json['challenger_points'] as num?)?.toInt() ?? 0,
      challengerCorrect: (json['challenger_correct'] as num?)?.toInt() ?? 0,
      opponentPoints: (json['opponent_points'] as num?)?.toInt(),
      opponentCorrect: (json['opponent_correct'] as num?)?.toInt(),
      status: (json['status'] ?? 'pending').toString(),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
              DateTime.now(),
      otherName: otherName,
      otherPhotoUrl: otherPhotoUrl,
    );
  }
}

/// Head-to-head challenges: same questions, two players, higher score wins.
///
/// The full question payload travels with the challenge rather than a list
/// of ids, because roughly half of every round is generated from the KJV at
/// runtime and those questions have no `quiz_questions` row. Storing ids
/// would make "you both answered the same questions" impossible to keep
/// true — which is the whole premise of a head-to-head.
class QuizChallengeService {
  QuizChallengeService._();

  static SupabaseClient get _client => Supabase.instance.client;
  static String? get _uid => _client.auth.currentUser?.id;

  /// Accepted friends, with a flag for anyone already challenged.
  static Future<List<QuizOpponent>> opponents() async {
    try {
      final rows = await _client.rpc('quiz_challengeable_friends');
      return (rows as List)
          .map((r) => QuizOpponent.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('QuizChallengeService.opponents failed: $e');
      return const [];
    }
  }

  /// Create a challenge from a round the challenger has just played.
  static Future<bool> create({
    required String opponentId,
    required QuizRoundResult result,
  }) async {
    final uid = _uid;
    if (uid == null || result.questions.isEmpty) return false;
    try {
      await _client.from('quiz_challenges').insert({
        'challenger_id': uid,
        'opponent_id': opponentId,
        'questions': [for (final q in result.questions) q.toJson()],
        'challenger_points': result.points.clamp(0, 100000),
        'challenger_correct': result.correctCount,
      });
      return true;
    } catch (e) {
      debugPrint('QuizChallengeService.create failed: $e');
      return false;
    }
  }

  /// Challenges waiting for *you* to play.
  static Future<List<QuizChallenge>> incoming() async {
    final uid = _uid;
    if (uid == null) return const [];
    return _fetch(
      _client
          .from('quiz_challenges')
          .select()
          .eq('opponent_id', uid)
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(20),
      otherIdOf: (row) => row['challenger_id'].toString(),
    );
  }

  /// Recently settled challenges, either side.
  static Future<List<QuizChallenge>> history({int limit = 30}) async {
    final uid = _uid;
    if (uid == null) return const [];
    return _fetch(
      _client
          .from('quiz_challenges')
          .select()
          .eq('status', 'complete')
          .or('challenger_id.eq.$uid,opponent_id.eq.$uid')
          .order('completed_at', ascending: false)
          .limit(limit),
      otherIdOf: (row) => row['challenger_id'].toString() == uid
          ? row['opponent_id'].toString()
          : row['challenger_id'].toString(),
    );
  }

  /// Runs a query then resolves the other player's name/photo in one go —
  /// the challenge rows only carry ids, and RLS keeps us off a join.
  static Future<List<QuizChallenge>> _fetch(
    PostgrestTransformBuilder<List<Map<String, dynamic>>> query, {
    required String Function(Map<String, dynamic> row) otherIdOf,
  }) async {
    try {
      final rows = (await query).cast<Map<String, dynamic>>();
      if (rows.isEmpty) return const [];

      final otherIds = {for (final row in rows) otherIdOf(row)}.toList();
      final profiles = await _client
          .from('profiles')
          .select('id, full_name, profile_photo_url')
          .inFilter('id', otherIds);
      final byId = {
        for (final p in (profiles as List).cast<Map<String, dynamic>>())
          p['id'].toString(): p,
      };

      return [
        for (final row in rows)
          QuizChallenge.fromJson(
            row,
            otherName:
                (byId[otherIdOf(row)]?['full_name'] ?? 'Member').toString(),
            otherPhotoUrl:
                byId[otherIdOf(row)]?['profile_photo_url'] as String?,
          ),
      ];
    } catch (e) {
      debugPrint('QuizChallengeService._fetch failed: $e');
      return const [];
    }
  }

  /// Submit your score against a challenge.
  ///
  /// Goes through an RPC rather than an UPDATE because RLS can't restrict
  /// *columns* — with update rights the opponent could rewrite the
  /// challenger's score. The function checks caller, status and ownership.
  static Future<bool> submit({
    required String challengeId,
    required int points,
    required int correct,
  }) async {
    try {
      await _client.rpc('quiz_challenge_submit', params: {
        'p_challenge_id': challengeId,
        'p_points': points.clamp(0, 100000),
        'p_correct': correct,
      });
      return true;
    } catch (e) {
      debugPrint('QuizChallengeService.submit failed: $e');
      return false;
    }
  }

  static Future<void> decline(String challengeId) async {
    try {
      await _client
          .rpc('quiz_challenge_decline', params: {'p_challenge_id': challengeId});
    } catch (e) {
      debugPrint('QuizChallengeService.decline failed: $e');
    }
  }
}
