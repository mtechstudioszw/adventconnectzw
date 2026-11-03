import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/quiz_room.dart';

/// Live quiz rooms for 2 to 5 players (patch_306).
///
/// Every call goes to a SECURITY DEFINER function; the room tables have no
/// client access. There is no server loop — each phone in the room calls
/// [tick] about once a second, and that is what moves the game on.
class QuizRoomService {
  QuizRoomService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static Future<QuizRoom> create() => _call('quiz_room_create', const {});

  static Future<QuizRoom> join(String code) =>
      _call('quiz_room_join', {'p_code': normaliseCode(code)});

  static Future<QuizRoom> start(String roomId, {int questions = 10}) =>
      _call('quiz_room_start', {'p_room': roomId, 'p_count': questions});

  static Future<QuizRoom> tick(String roomId) =>
      _call('quiz_room_tick', {'p_room': roomId});

  static Future<QuizRoom> answer({
    required String roomId,
    required int index,
    required int choice,
  }) => _call('quiz_room_answer', {
    'p_room': roomId,
    'p_index': index,
    'p_choice': choice,
  });

  static Future<void> invite(String roomId, String userId) async {
    try {
      await _client.rpc(
        'quiz_room_invite',
        params: {'p_room': roomId, 'p_user': userId},
      );
    } on PostgrestException catch (e) {
      throw QuizRoomError(friendly(e.message));
    }
  }

  /// Best effort: leaving must never trap someone on the screen.
  static Future<void> leave(String roomId) async {
    try {
      await _client.rpc('quiz_room_leave', params: {'p_room': roomId});
    } catch (_) {}
  }

  /// Codes are read aloud and typed on phones: ignore case and spaces.
  static String normaliseCode(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static bool looksLikeCode(String raw) => normaliseCode(raw).length == 6;

  static String friendly(String raw) {
    if (raw.contains('ROOM_NOT_FOUND')) {
      return 'No room with that code. Check the letters and try again.';
    }
    if (raw.contains('ROOM_FULL')) return 'That room already has 5 players.';
    if (raw.contains('ROOM_STARTED')) {
      return 'That game has already started.';
    }
    if (raw.contains('NEED_TWO_PLAYERS')) {
      return 'Wait for at least one more player to join.';
    }
    if (raw.contains('no quiz profile')) {
      return "They haven't opened the Bible quiz yet.";
    }
    if (raw.contains('MAINTENANCE')) {
      return 'The app is under maintenance. Try again shortly.';
    }
    return 'Something went wrong. Try again.';
  }

  static Future<QuizRoom> _call(String fn, Map<String, dynamic> params) async {
    try {
      final row = await _client.rpc(fn, params: params);
      return QuizRoom.fromJson(Map<String, dynamic>.from(row as Map));
    } on PostgrestException catch (e) {
      throw QuizRoomError(friendly(e.message), raw: e.message);
    }
  }
}

class QuizRoomError implements Exception {
  const QuizRoomError(this.message, {this.raw});
  final String message;
  final String? raw;

  /// The room is gone for this player — stop ticking.
  bool get isFatal =>
      (raw ?? '').contains('Not in this room') ||
      (raw ?? '').contains('Room not found');

  @override
  String toString() => message;
}
