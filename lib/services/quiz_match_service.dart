import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/quiz_match.dart';
import 'presence_service.dart';

/// Raised when an action needs a quiz profile the player hasn't made yet.
///
/// Its own type rather than a string match on the message: the founder's
/// rule is that a profile is optional for solo play and required for the
/// leaderboard and challenges, so this is a routine branch in the UI, not
/// an error to show.
class QuizProfileRequired implements Exception {
  const QuizProfileRequired();
  @override
  String toString() => 'QUIZ_PROFILE_REQUIRED';
}

/// Live head-to-head matches.
///
/// This sits *beside* [QuizChallengeService], which still runs the async
/// "play your round, they play theirs" challenges. Nothing here replaces
/// it — a live match and an async challenge are different games, and the
/// async one works.
///
/// Three things are deliberately NOT done on the client:
///
///  * **Timing.** Every countdown comes from the server's
///    `question_started_at` plus the measured clock skew. A device clock is
///    never consulted directly.
///  * **Marking.** [answer] posts a choice and the server decides; the
///    correct index comes back only once the answer is locked. Solo play
///    can hold the key on the client, and does — competitively it would let
///    anyone read the answers straight out of memory.
///  * **Ending.** Forfeits, timeouts and the final whistle are all server
///    transitions, so a player who force-quits cannot leave their opponent
///    watching a clock that never moves.
class QuizMatchService {
  QuizMatchService._();

  static SupabaseClient get _client => Supabase.instance.client;
  static String? get uid => _client.auth.currentUser?.id;

  // ---- Identity -----------------------------------------------------------

  static QuizProfile? _cachedProfile;

  /// The signed-in player's quiz identity, or null if they haven't made one.
  static Future<QuizProfile?> myProfile({bool refresh = false}) async {
    final me = uid;
    if (me == null) return null;
    if (!refresh && _cachedProfile?.userId == me) return _cachedProfile;
    try {
      final row = await _client
          .from('quiz_profiles')
          .select()
          .eq('user_id', me)
          .maybeSingle();
      _cachedProfile =
          row == null ? null : QuizProfile.fromJson(row);
      return _cachedProfile;
    } catch (e) {
      debugPrint('QuizMatchService.myProfile failed: $e');
      return null;
    }
  }

  /// Create or rename the quiz identity. Returns an error message, or null
  /// on success — the name can legitimately be rejected as taken or too
  /// short, and the sheet needs to say which.
  static Future<String?> saveProfile({
    required String displayName,
    String? photoUrl,
  }) async {
    try {
      final row = await _client.rpc('quiz_profile_upsert', params: {
        'p_display_name': displayName,
        'p_photo_url': photoUrl,
      });
      _cachedProfile =
          QuizProfile.fromJson(Map<String, dynamic>.from(row as Map));
      return null;
    } on PostgrestException catch (e) {
      return _friendlyMessage(e.message);
    } catch (e) {
      debugPrint('QuizMatchService.saveProfile failed: $e');
      return 'Could not save that right now.';
    }
  }

  static String _friendlyMessage(String raw) {
    if (raw.contains('taken')) return 'That name is already taken.';
    if (raw.contains('2 to 24')) return 'Use between 2 and 24 characters.';
    return 'Could not save that right now.';
  }

  /// Drops the cached identity. Called from [SessionReset] — a static that
  /// outlives sign-out would show the next account the last one's name.
  static void resetForSignOut() {
    _cachedProfile = null;
    unawaited(leaveMatchChannel());
  }

  // ---- Matchmaking --------------------------------------------------------

  /// Join whoever is waiting, or open a table and wait.
  ///
  /// The presence roster is passed to the server so it only pairs the
  /// caller with someone the channel says is actually there. Matching a
  /// queue entry whose owner closed the app is the failure this feature
  /// most has to avoid — an opponent who never answers is worse than an
  /// honest "nobody available right now".
  static Future<QuizMatch> find() async {
    final online = PresenceService.onlineUsers.toList();
    return _call('quiz_match_find', {
      'p_online': online.isEmpty ? null : online,
    });
  }

  /// Challenge one specific player, friend or not.
  static Future<QuizMatch> invite(String opponentId) =>
      _call('quiz_match_invite', {'p_opponent_id': opponentId});

  static Future<QuizMatch> accept(String matchId) =>
      _call('quiz_match_accept', {'p_match_id': matchId});

  /// Confirm (or refuse) a ready check — patch_203.
  ///
  /// A random pairing is provisional: the match sits in `ready` and the
  /// question clock does NOT start until both players call this. Before it
  /// existed, the second player joining set the match active and stamped
  /// `question_started_at` in the same statement, so the player who had been
  /// waiting was pulled into a match they never agreed to AND lost time on
  /// question one while still watching a "searching" spinner.
  ///
  /// Declining, or letting the 12-second deadline pass, cancels the match
  /// and frees the other player to search again immediately.
  static Future<QuizMatch> setReady(String matchId, {bool ready = true}) =>
      _call('quiz_match_ready', {
        'p_match_id': matchId,
        'p_ready': ready,
      });

  static Future<QuizMatch> state(String matchId) =>
      _call('quiz_match_state', {'p_match_id': matchId});

  /// Heartbeat + clock. Also what advances an expired question, so it must
  /// keep running for the whole match, not just while waiting.
  static Future<QuizMatch> tick(String matchId) =>
      _call('quiz_match_tick', {'p_match_id': matchId});

  static Future<QuizMatch> forfeit(String matchId) =>
      _call('quiz_match_forfeit', {'p_match_id': matchId});

  static Future<void> cancel(String matchId) async {
    try {
      await _client.rpc('quiz_match_cancel', params: {'p_match_id': matchId});
    } catch (e) {
      debugPrint('QuizMatchService.cancel failed: $e');
    }
  }

  /// Lock in an answer. [choice] is -1 when the clock took it.
  static Future<QuizMatchAnswerResult> answer({
    required String matchId,
    required int index,
    required int choice,
  }) async {
    final row = await _client.rpc('quiz_match_answer', params: {
      'p_match_id': matchId,
      'p_index': index,
      'p_choice': choice,
    });
    return QuizMatchAnswerResult.fromJson(
      Map<String, dynamic>.from(row as Map),
    );
  }

  static Future<QuizMatch> _call(
    String fn,
    Map<String, dynamic> params,
  ) async {
    try {
      final row = await _client.rpc(fn, params: params);
      return QuizMatch.fromJson(Map<String, dynamic>.from(row as Map));
    } on PostgrestException catch (e) {
      if (e.message.contains('QUIZ_PROFILE_REQUIRED')) {
        throw const QuizProfileRequired();
      }
      rethrow;
    }
  }

  // ---- Opponents ----------------------------------------------------------

  /// Everyone with a quiz profile, online players first.
  static Future<List<QuizPlayer>> players({String? query}) async {
    final online = PresenceService.onlineUsers.toList();
    try {
      final rows = await _client.rpc('quiz_players', params: {
        'p_query': query,
        'p_online': online.isEmpty ? null : online,
      });
      return (rows as List)
          .map((r) => QuizPlayer.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('QuizMatchService.players failed: $e');
      return const [];
    }
  }

  static Future<List<QuizMatchInvite>> invites() async {
    try {
      final rows = await _client.rpc('quiz_match_invites');
      return (rows as List)
          .map((r) => QuizMatchInvite.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('QuizMatchService.invites failed: $e');
      return const [];
    }
  }

  /// Retires stale queue entries and dead matches. Cheap, best-effort.
  static Future<void> sweep() async {
    try {
      await _client.rpc('quiz_matches_sweep');
    } catch (_) {}
  }

  // ---- Realtime -----------------------------------------------------------

  static RealtimeChannel? _channel;

  /// Bumped by [leaveMatchChannel]. [watchMatch] captures it before its
  /// first await and re-checks after, so a channel built for a match the
  /// player has already left is torn down instead of being published into
  /// a field the next match is about to use.
  ///
  /// This is the same publish/dispose race that silenced the quiz's sound
  /// for a whole session, in a place where it would instead have shown one
  /// match's score inside another.
  static int _generation = 0;

  /// Push updates for [matchId]. [onUpdate] receives the raw row; callers
  /// fold it into their snapshot with [QuizMatch.mergeRealtimeRow].
  static Future<void> watchMatch(
    String matchId,
    void Function(Map<String, dynamic> row) onUpdate,
  ) async {
    await leaveMatchChannel();
    final generation = _generation;

    final channel = _client
        .channel('quiz_match:$matchId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'quiz_matches',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: matchId,
          ),
          callback: (payload) {
            // A trailing event from a channel we have already replaced must
            // never be folded into the new match's state.
            if (generation != _generation) return;
            onUpdate(payload.newRecord);
          },
        );

    channel.subscribe();

    if (generation != _generation) {
      // Left while subscribing. Drop it rather than publish a channel the
      // screen has already walked away from.
      try {
        await _client.removeChannel(channel);
      } catch (_) {}
      return;
    }
    _channel = channel;
  }

  static Future<void> leaveMatchChannel() async {
    _generation++;
    final channel = _channel;
    _channel = null;
    if (channel == null) return;
    try {
      await _client.removeChannel(channel);
    } catch (_) {}
  }
}
