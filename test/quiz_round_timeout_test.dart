import 'package:advent_connect_zw/models/quiz_question_model.dart';
import 'package:advent_connect_zw/models/quiz_round.dart';
import 'package:advent_connect_zw/screens/quiz/arena/quiz_round_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The timeout path of a quiz round (#3 A4, reported 3 Aug 2026 as
/// "Null check operator used on a null value").
///
/// Running out of time IS getting the question wrong (founder's call,
/// 2 Aug 2026), and on that path `_chosen` is deliberately left null so
/// no answer tile lights up as though the player picked it. But both
/// reveal widgets are gated on `_answered`, which the timeout flag alone
/// satisfies, and both then dereferenced `_chosen!`. So the crash fired on
/// EVERY timeout, not occasionally — the one path nobody had a test for.
QuizQuestion _question(String id) => QuizQuestion(
  id: id,
  question: 'Who was swallowed by a great fish?',
  options: const ['Jonah', 'Job', 'Joel', 'Joshua'],
  correctIndex: 0,
  category: 'Old Testament',
  difficulty: 'easy',
  explanation: 'Jonah 1:17.',
  reference: 'Jonah 1:17',
);

Widget _round(QuizMode mode, {int questions = 3}) => MaterialApp(
  home: QuizRoundScreen(
    // autoStart: false skips the countdown film and the audio/ad/Hive
    // boot, none of which exist under a headless binding.
    autoStart: false,
    config: QuizRoundConfig(
      mode: mode,
      questions: [
        for (var i = 0; i < questions; i++) _question('q$i'),
      ],
      title: 'Test round',
    ),
  ),
);

/// Runs the per-question clock past zero without answering, then settles
/// far enough to reveal the miss.
Future<void> _timeOut(WidgetTester tester, {required int seconds}) async {
  await tester.pump();
  // One second at a time, not a single jump to the end. A jump lands the
  // controllers' status callbacks on a frame whose timestamp is already
  // past the ticker start they then capture, which trips
  // AnimationController's own `elapsedInSeconds >= 0.0` assertion — a
  // test artefact, not a bug in the screen.
  for (var i = 0; i <= seconds; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

/// Tears the round down, then lets `_timeUp`'s 1400ms "read what you
/// missed" delay expire against an unmounted state.
///
/// The delay is a real Future.delayed, so leaving it in flight fails
/// teardown with "A Timer is still pending" — but letting it fire while
/// the screen is still mounted advances to the next question and starts
/// fresh animations that outlive the test. Unmounting first means
/// `_timeUp` resumes, sees `!mounted` and returns.
Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1600));
}

/// Writing these turned up two further defects, both of which had to be
/// fixed before the timeout path could be exercised at all — and both of
/// which failed silently in production:
///
///  * `QuizProgressService.addMistake` mutated the `const []` that
///    `mistakes()` returns for an empty pool, so it threw on the FIRST
///    mistake anyone ever made and Fix Your Mistakes could never receive
///    an entry. Invisible, because every caller is `unawaited`.
///  * `BurstLayer` built its Ticker in a lazy `late final`, so a round
///    where no burst ever fired created it inside `dispose()` — where the
///    TickerMode lookup hits a deactivated element and aborts disposal
///    part-way. See test/burst_layer_test.dart.
void main() {
  testWidgets('running the clock out does not crash the round', (tester) async {
    await tester.pumpWidget(_round(QuizMode.practice));

    await _timeOut(tester, seconds: 20);

    expect(
      tester.takeException(),
      isNull,
      reason: 'the timeout reveal dereferenced a null _chosen',
    );
    await _drain(tester);
  });

  testWidgets('the timeout reveal is reachable in sudden death too', (
    tester,
  ) async {
    // Survival takes the other crash site: the Next button asks whether
    // the run has ended, which is the same `isCorrect(_chosen!)` question.
    await tester.pumpWidget(_round(QuizMode.survival));

    await _timeOut(tester, seconds: 15);

    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('a timed-out question still shows the player something', (
    tester,
  ) async {
    await tester.pumpWidget(_round(QuizMode.practice));

    await _timeOut(tester, seconds: 20);

    // The round must reveal the answer it missed rather than sitting on a
    // dead question — seeing the answer is what turns a miss into teaching.
    expect(find.textContaining('Jonah'), findsWidgets);
    await _drain(tester);
  });

  testWidgets('answering normally is unaffected', (tester) async {
    await tester.pumpWidget(_round(QuizMode.practice));
    await tester.pump();

    await tester.tap(find.text('Jonah'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    await _drain(tester);
  });
}
