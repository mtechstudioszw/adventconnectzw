import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/quiz_round.dart';
import 'quiz_progress_service.dart';

/// One row of the weekly leaderboard.
class QuizLeaderboardEntry {
  const QuizLeaderboardEntry({
    required this.userId,
    required this.name,
    required this.photoUrl,
    required this.isVerified,
    required this.points,
    required this.rounds,
    required this.rank,
    required this.isMe,
  });

  final String userId;
  final String name;
  final String? photoUrl;
  final bool isVerified;
  final int points;
  final int rounds;
  final int rank;
  final bool isMe;

  factory QuizLeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      QuizLeaderboardEntry(
        userId: json['user_id'].toString(),
        name: (json['full_name'] ?? 'Member').toString(),
        photoUrl: json['photo_url'] as String?,
        isVerified: json['is_verified'] == true,
        points: (json['points'] as num?)?.toInt() ?? 0,
        rounds: (json['rounds'] as num?)?.toInt() ?? 0,
        rank: (json['rank'] as num?)?.toInt() ?? 0,
        isMe: json['is_me'] == true,
      );
}

/// Where the signed-in player sits this week.
class QuizRankSummary {
  const QuizRankSummary({
    required this.points,
    required this.rounds,
    required this.rank,
    required this.totalPlayers,
  });

  final int points;
  final int rounds;
  final int rank;
  final int totalPlayers;
}

/// Mirrors local quiz progress to Supabase and serves the leaderboard.
///
/// Deliberately best-effort in every direction: the arena must play, score
/// and celebrate with no network at all, so nothing here is ever awaited on
/// a path the player can feel. Local storage stays the source of truth for
/// reads; the cloud is a backup for reinstalls and the scoreboard.
class QuizCloudService {
  QuizCloudService._();

  static SupabaseClient get _client => Supabase.instance.client;
  static String? get _uid => _client.auth.currentUser?.id;

  /// Push local progress up. Safe to call after every round.
  static Future<void> syncUp() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _client.from('quiz_progress').upsert({
        'user_id': uid,
        'xp': QuizProgressService.totalXp(),
        'current_streak': QuizProgressService.currentStreak(),
        'best_streak': QuizProgressService.bestStreak(),
        'total_answered': QuizProgressService.totalAnswered(),
        'total_correct': QuizProgressService.totalCorrect(),
        'lifetime_points': QuizProgressService.lifetimePoints(),
        'coins': QuizProgressService.coins(),
        'best_daily': QuizProgressService.bestScore(QuizMode.daily),
        'best_practice': QuizProgressService.bestScore(QuizMode.practice),
        'best_survival': QuizProgressService.bestScore(QuizMode.survival),
        'best_speed': QuizProgressService.bestScore(QuizMode.speed),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('QuizCloudService.syncUp failed: $e');
    }
  }

  /// Restore progress after a reinstall.
  ///
  /// Only runs when local progress is genuinely empty — otherwise a stale
  /// cloud row could overwrite a streak the player is mid-way through. It's
  /// a restore, not a two-way merge.
  static Future<bool> restoreIfEmpty() async {
    final uid = _uid;
    if (uid == null) return false;
    final localIsEmpty = QuizProgressService.totalXp() == 0 &&
        QuizProgressService.totalAnswered() == 0 &&
        QuizProgressService.currentStreak() == 0;
    if (!localIsEmpty) return false;

    try {
      final row = await _client
          .from('quiz_progress')
          .select()
          .eq('user_id', uid)
          .maybeSingle();
      if (row == null) return false;
      await QuizProgressService.restoreFromCloud(
        xp: (row['xp'] as num?)?.toInt() ?? 0,
        currentStreak: (row['current_streak'] as num?)?.toInt() ?? 0,
        bestStreak: (row['best_streak'] as num?)?.toInt() ?? 0,
        totalAnswered: (row['total_answered'] as num?)?.toInt() ?? 0,
        totalCorrect: (row['total_correct'] as num?)?.toInt() ?? 0,
        lifetimePoints: (row['lifetime_points'] as num?)?.toInt() ?? 0,
        coins: (row['coins'] as num?)?.toInt() ?? 0,
        bestScores: {
          QuizMode.daily: (row['best_daily'] as num?)?.toInt() ?? 0,
          QuizMode.practice: (row['best_practice'] as num?)?.toInt() ?? 0,
          QuizMode.survival: (row['best_survival'] as num?)?.toInt() ?? 0,
          QuizMode.speed: (row['best_speed'] as num?)?.toInt() ?? 0,
        },
      );
      return true;
    } catch (e) {
      debugPrint('QuizCloudService.restoreIfEmpty failed: $e');
      return false;
    }
  }

  /// Log a finished round so it counts toward the weekly leaderboard.
  static Future<void> recordRound(QuizRoundResult result) async {
    final uid = _uid;
    if (uid == null || result.total == 0) return;
    try {
      await _client.from('quiz_scores').insert({
        'user_id': uid,
        'mode': result.mode.name,
        // Matches the column's CHECK. Clamped rather than sent raw so a
        // freak score logs at the ceiling instead of being rejected and lost.
        'points': result.points.clamp(0, 100000),
        'correct_count': result.correctCount,
        'total_count': result.total,
      });
    } catch (e) {
      debugPrint('QuizCloudService.recordRound failed: $e');
    }
  }

  /// Top players over the last [days].
  static Future<List<QuizLeaderboardEntry>> leaderboard({
    int days = 7,
    int limit = 50,
  }) async {
    try {
      final rows = await _client.rpc(
        'quiz_leaderboard',
        params: {'p_days': days, 'p_limit': limit},
      );
      return (rows as List)
          .map((r) =>
              QuizLeaderboardEntry.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('QuizCloudService.leaderboard failed: $e');
      return const [];
    }
  }

  /// The caller's own standing, even when outside the visible top N.
  static Future<QuizRankSummary?> myRank({int days = 7}) async {
    if (_uid == null) return null;
    try {
      final rows = await _client.rpc('quiz_my_rank', params: {'p_days': days});
      final list = rows as List;
      if (list.isEmpty) return null;
      final row = list.first as Map<String, dynamic>;
      return QuizRankSummary(
        points: (row['points'] as num?)?.toInt() ?? 0,
        rounds: (row['rounds'] as num?)?.toInt() ?? 0,
        rank: (row['rank'] as num?)?.toInt() ?? 0,
        totalPlayers: (row['total_players'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      debugPrint('QuizCloudService.myRank failed: $e');
      return null;
    }
  }
}
