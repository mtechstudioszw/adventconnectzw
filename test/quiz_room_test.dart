import 'package:advent_connect_zw/models/quiz_room.dart';
import 'package:advent_connect_zw/services/quiz_room_service.dart';
import 'package:advent_connect_zw/screens/quiz/arena/quiz_room_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Live rooms for 2–5 players (patch_306). The shape below is exactly what
/// `quiz_room_view` returned in the server dry run on 3 Nov 2026.
Map<String, dynamic> _view({
  String status = 'active',
  DateTime? started,
  DateTime? resolved,
  int? revealed,
  List<Map<String, dynamic>>? players,
}) {
  final now = DateTime.now().toUtc();
  return {
    'id': 'r1',
    'code': 'ABC234',
    'status': status,
    'host_id': 'u1',
    'questions': [
      {
        'id': 'q1',
        'question': 'Who built the ark?',
        'options': ['Noah', 'Moses', 'David', 'Paul'],
        'correct_index': -1,
        'category': 'Old Testament',
        'difficulty': 'easy',
      },
    ],
    'question_count': 1,
    'seconds_per_question': 15,
    'current_index': 0,
    'question_started_at': (started ?? now).toIso8601String(),
    'resolved_at': resolved?.toIso8601String(),
    'server_now': now.toIso8601String(),
    'revealed_index': revealed,
    'my_choice': null,
    'players':
        players ??
        [
          {
            'user_id': 'u1',
            'name': 'Tana',
            'points': 193,
            'correct': 1,
            'answered': true,
            'last_points': 193,
            'last_correct': true,
            'left': false,
            'is_me': true,
          },
          {
            'user_id': 'u2',
            'name': 'Rudo',
            'points': 0,
            'correct': 0,
            'answered': true,
            'last_points': 0,
            'last_correct': false,
            'left': false,
            'is_me': false,
          },
        ],
  };
}

void main() {
  test('parses the server view', () {
    final r = QuizRoom.fromJson(_view(resolved: DateTime.now(), revealed: 0));
    expect(r.code, 'ABC234');
    expect(r.isActive, isTrue);
    expect(r.isRevealing, isTrue);
    expect(r.revealedIndex, 0);
    expect(r.question!.correctIndex, -1, reason: 'the key never ships');
    expect(r.me!.name, 'Tana');
    expect(r.isHost('u1'), isTrue);
    expect(r.isHost('u2'), isFalse);
    expect(r.answeredCount, 2);
  });

  test('countdown before the first question', () {
    final r = QuizRoom.fromJson(
      _view(started: DateTime.now().toUtc().add(const Duration(seconds: 3))),
    );
    expect(r.inCountdown, isTrue);
    expect(r.countdownSeconds, inInclusiveRange(2, 3));
    expect(r.remainingFraction, 1);
  });

  test('clock runs from the question start and empties at the deadline', () {
    final half = QuizRoom.fromJson(
      _view(
        started: DateTime.now().toUtc().subtract(
          const Duration(milliseconds: 7500),
        ),
      ),
    );
    expect(half.remainingFraction, closeTo(0.5, 0.05));
    final over = QuizRoom.fromJson(
      _view(
        started: DateTime.now().toUtc().subtract(const Duration(seconds: 30)),
      ),
    );
    expect(over.remainingFraction, 0);
    expect(over.secondsLeft, 0);
  });

  test('ties share a place; players who left are not present', () {
    final r = QuizRoom.fromJson(
      _view(
        players: [
          for (final (id, pts, left) in [
            ('a', 300, false),
            ('b', 300, false),
            ('c', 100, false),
            ('d', 0, true),
          ])
            {
              'user_id': id,
              'name': id,
              'points': pts,
              'left': left,
              'is_me': id == 'c',
            },
        ],
      ),
    );
    expect(r.placeOf(r.players[0]), 1);
    expect(r.placeOf(r.players[1]), 1);
    expect(r.placeOf(r.players[2]), 3);
    expect(r.present.length, 3);
    expect(r.isFull, isFalse);
  });

  test('a room of five is full', () {
    final r = QuizRoom.fromJson(
      _view(
        status: 'lobby',
        players: [
          for (var i = 0; i < 5; i++)
            {'user_id': 'u$i', 'name': 'P$i', 'is_me': i == 0},
        ],
      ),
    );
    expect(r.isLobby, isTrue);
    expect(r.isFull, isTrue);
  });

  test('codes are forgiving about case and spaces', () {
    expect(QuizRoomService.normaliseCode(' abc 234 '), 'ABC234');
    expect(QuizRoomService.looksLikeCode('abc-234'), isTrue);
    expect(QuizRoomService.looksLikeCode('abc23'), isFalse);
  });

  test('server errors read as plain words', () {
    expect(QuizRoomService.friendly('ROOM_FULL'), contains('5 players'));
    expect(QuizRoomService.friendly('ROOM_NOT_FOUND'), contains('code'));
    expect(QuizRoomService.friendly('ROOM_STARTED'), contains('started'));
    expect(QuizRoomService.friendly('NEED_TWO_PLAYERS'), contains('one more'));
    expect(const QuizRoomError('x', raw: 'Not in this room').isFatal, isTrue);
  });

  group('layout with five players on a small phone', () {
    List<Map<String, dynamic>> five() => [
      for (var i = 0; i < 5; i++)
        {
          'user_id': 'u$i',
          'name': 'Tanatswa Michael Mikuwa Number $i',
          'points': 1000 - i * 150,
          'is_me': i == 3,
        },
    ];

    Future<void> pump(WidgetTester t, Widget w) async {
      await t.binding.setSurfaceSize(const Size(320, 640));
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SafeArea(child: w)),
        ),
      );
      await t.pump(const Duration(milliseconds: 400));
    }

    testWidgets('lobby', (t) async {
      final r = QuizRoom.fromJson(_view(status: 'lobby', players: five()));
      await pump(t, QuizRoomScreen.debugLobby(r));
      expect(t.takeException(), isNull);
      expect(find.text('ABC 234'), findsOneWidget);
      expect(find.text('Start with 5 players'), findsOneWidget);
    });

    testWidgets('live board during a reveal', (t) async {
      final players = [
        for (final p in five()) {...p, 'last_points': 290, 'answered': true},
      ];
      final r = QuizRoom.fromJson(
        _view(resolved: DateTime.now(), revealed: 0, players: players),
      );
      await pump(t, QuizRoomScreen.debugBoard(r));
      expect(t.takeException(), isNull);
      expect(find.text('+290'), findsNWidgets(5));
    });

    testWidgets('podium', (t) async {
      final r = QuizRoom.fromJson(_view(status: 'complete', players: five()));
      await pump(t, QuizRoomScreen.debugPodium(r));
      expect(t.takeException(), isNull);
      expect(find.text('You came 4th'), findsOneWidget);
    });
  });
}
