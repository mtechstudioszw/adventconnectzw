// The live-match ready check, and the score that must stay hidden.
//
// Two things are pinned here because both fail silently:
//
//  1. A pairing is provisional. Before patch_203 the second player joining
//     set the match `active` AND stamped question_started_at in the same
//     statement, so the player who had been waiting was pulled into a match
//     they never agreed to and lost time on question one while still
//     looking at a "searching" spinner.
//
//  2. The opponent's running score is withheld until the match completes.
//     The view stops sending it — but Realtime delivers the RAW table row,
//     which carries a_points and b_points in full. Merging those would hand
//     back exactly what the view is withholding, and the hiding would be
//     decorative. That is the regression this file exists to catch.
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/quiz_match.dart';

const _me = 'aaaaaaaa-0000-4000-8000-000000000001';
const _them = 'bbbbbbbb-0000-4000-8000-000000000002';

Map<String, dynamic> _json({
  required String status,
  bool aReady = false,
  bool bReady = false,
  String? questionStartedAt,
  int? aPoints,
  int? bPoints,
  bool scoresHidden = true,
}) => {
      'id': 'match-1',
      'status': status,
      'questions': const [],
      'question_count': 7,
      'seconds_per_question': 15,
      'current_index': 0,
      'question_started_at': questionStartedAt,
      'player_a': _me,
      'player_b': _them,
      'a_ready': aReady,
      'b_ready': bReady,
      'ready_deadline': '2030-01-01T00:00:12Z',
      'server_now': '2030-01-01T00:00:00Z',
      'a_points': aPoints,
      'b_points': bPoints,
      'scores_hidden': scoresHidden,
    };

void main() {
  group('ready check', () {
    test('a fresh pairing is provisional and has no clock', () {
      final m = QuizMatch.fromJson(_json(status: 'ready'));
      expect(m.isReadyCheck, isTrue);
      expect(m.isActive, isFalse);
      // The whole point: no clock while either player is still deciding.
      expect(m.questionStartedAt, isNull);
      expect(m.iAmReady(_me), isFalse);
      expect(m.theyAreReady(_me), isFalse);
    });

    test('one player confirming does not start the match', () {
      final m = QuizMatch.fromJson(_json(status: 'ready', bReady: true));
      expect(m.isReadyCheck, isTrue);
      expect(m.questionStartedAt, isNull);
      expect(m.iAmReady(_me), isFalse);
      expect(m.theyAreReady(_me), isTrue);
    });

    test('both confirming starts it, with the clock stamped then', () {
      final m = QuizMatch.fromJson(_json(
        status: 'active',
        aReady: true,
        bReady: true,
        questionStartedAt: '2030-01-01T00:00:00Z',
      ));
      expect(m.isActive, isTrue);
      expect(m.isReadyCheck, isFalse);
      expect(m.questionStartedAt, isNotNull);
      // Full clock for both — nobody entered part-way through question one.
      expect(m.remainingFraction, 1.0);
    });

    test('the countdown is server-corrected, not device time', () {
      // The deadline is 12s after `server_now`, and clockSkew is measured
      // against DateTime.now() at parse time — so a few milliseconds of
      // real elapsed time truncate this to 11. A range, not an equality:
      // what matters is that it derives from the SERVER clock rather than
      // the device's, so a phone whose clock is minutes out still counts
      // down correctly.
      final m = QuizMatch.fromJson(_json(status: 'ready'));
      expect(m.readySecondsLeft, inInclusiveRange(11, 12));
    });

    test('a missing deadline counts down to zero rather than crashing', () {
      final json = _json(status: 'ready')..remove('ready_deadline');
      expect(QuizMatch.fromJson(json).readySecondsLeft, 0);
    });
  });

  group('scores stay hidden until it is over', () {
    test('the opponent has no number during play', () {
      final m = QuizMatch.fromJson(
        _json(status: 'active', aPoints: 400, bPoints: null),
      );
      expect(m.scoresHidden, isTrue);
      expect(m.myPoints(_me), 400);
      expect(m.theirPoints(_me), 0); // parsed from null; UI renders a dash
    });

    test('a Realtime row must NOT leak the withheld score', () {
      // This is the one that matters. The raw table row has both totals.
      final during = QuizMatch.fromJson(
        _json(status: 'active', aPoints: 400, bPoints: null),
      );
      final merged = during.mergeRealtimeRow({
        'status': 'active',
        'a_points': 400,
        'b_points': 950, // the real value, straight off the table
        'a_correct': 2,
        'b_correct': 5,
      });
      expect(merged.scoresHidden, isTrue);
      expect(
        merged.theirPoints(_me),
        isNot(950),
        reason: 'Realtime re-published the score the view withheld',
      );
      expect(merged.theirCorrect(_me), isNot(5));
    });

    test('completing the match reveals both totals', () {
      final during = QuizMatch.fromJson(
        _json(status: 'active', aPoints: 400, bPoints: null),
      );
      final done = during.mergeRealtimeRow({
        'status': 'complete',
        'a_points': 400,
        'b_points': 950,
        'a_correct': 2,
        'b_correct': 5,
      });
      expect(done.scoresHidden, isFalse);
      expect(done.myPoints(_me), 400);
      expect(done.theirPoints(_me), 950);
    });
  });
}
