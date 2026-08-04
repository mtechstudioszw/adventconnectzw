import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/quiz_match.dart';
import '../../../models/quiz_round.dart';
import '../../../services/quiz_match_service.dart';
import '../../../services/quiz_music.dart';
import '../../../services/quiz_sfx.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/user_avatar.dart';
import 'arena_theme.dart';
import 'widgets/answer_tile.dart';
import 'widgets/arena_hud.dart';
import 'widgets/arena_scaffold.dart';
import 'widgets/burst_layer.dart';

/// A live head-to-head round.
///
/// The screen deliberately owns almost no rules. It draws whatever the
/// server says the match currently is, and the server decides when a
/// question closes, what a tap was worth, and who won — see
/// [QuizMatchService] for why each of those is not a client decision.
///
/// What it *does* own is the feel: a countdown that stays in step with the
/// opponent's, an opponent pip that lands the moment they answer, and a
/// reveal that arrives at the same instant on both phones.
class QuizMatchScreen extends StatefulWidget {
  const QuizMatchScreen({
    super.key,
    required this.match,
    this.autoStart = true,
  });

  final QuizMatch match;

  /// False in tests: the timers, the Realtime subscription and the audio
  /// pool all reach services that do not exist under a headless binding.
  /// With it false the screen renders the match it was handed and nothing
  /// else moves, which is what makes the layout testable on its own.
  final bool autoStart;

  @override
  State<QuizMatchScreen> createState() => _QuizMatchScreenState();
}

class _QuizMatchScreenState extends State<QuizMatchScreen>
    with TickerProviderStateMixin {
  late QuizMatch _match = widget.match;
  String? get _uid => QuizMatchService.uid;

  /// What I tapped on the question showing now.
  int? _chosen;

  /// The right answer, once the server is willing to say. Comes either from
  /// my own answer response or — when the clock beat me to it — from the
  /// match view once the question is resolved for both of us.
  int? _revealIndex;

  bool _sending = false;
  bool _leaving = false;
  int _lastIndex = -1;

  int _lastPoints = 0;
  int _lastMultiplier = 1;
  int _floatKey = 0;
  Offset? _floatAt;

  // Built in initState, never as a lazy `late final`: a controller first
  // touched inside dispose() constructs its ticker off a deactivated
  // context, and the throw aborts disposal part-way.
  late final AnimationController _entrance;
  late final AnimationController _flash;
  late final AnimationController _clock;
  final BurstController _bursts = BurstController();

  Color _flashColor = ArenaTheme.correctOnNavy;
  int _lastTickSecond = -1;

  Timer? _uiTimer;
  Timer? _heartbeat;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _flash = AnimationController(vsync: this, duration: AppMotion.celebrate);
    // Driven by hand from the server clock rather than run forward: the
    // countdown must track `question_started_at`, so its value is assigned
    // each UI tick instead of being animated locally.
    _clock = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
      value: 1,
    );

    if (widget.autoStart) {
      QuizSfx.init();
      unawaited(QuizMusic.start());
      _subscribe();
      _uiTimer = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => _onUiTick(),
      );
      // Heartbeat AND clock: this is what advances a question whose time
      // ran out, and what lets the server notice a player who has gone.
      _heartbeat = Timer.periodic(
        const Duration(milliseconds: 1200),
        (_) => _serverTick(),
      );
    }
    _lastIndex = _match.currentIndex;
    _entrance.forward(from: 0);
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _heartbeat?.cancel();
    unawaited(QuizMatchService.leaveMatchChannel());
    // Does NOT stop the soundtrack — the lobby owns it. Leaving a live
    // match drops you back into the arena, not out of it. See the note in
    // quiz_round_screen.dispose().
    _entrance.dispose();
    _flash.dispose();
    _clock.dispose();
    _bursts.dispose();
    super.dispose();
  }

  Future<void> _subscribe() async {
    await QuizMatchService.watchMatch(_match.id, (row) {
      if (!mounted) return;
      _apply(_match.mergeRealtimeRow(row));
    });
  }

  /// Fold a newer snapshot in, and react to what changed.
  void _apply(QuizMatch next) {
    if (!mounted) return;
    final movedOn = next.currentIndex != _lastIndex;
    final justResolved = next.isRevealing && _revealIndex == null;

    setState(() {
      _match = next;
      if (movedOn) {
        _lastIndex = next.currentIndex;
        _chosen = next.myChoice;
        _revealIndex = null;
        _lastPoints = 0;
        _floatAt = null;
        _lastTickSecond = -1;
      }
      if (next.revealedIndex != null) _revealIndex = next.revealedIndex;
    });

    if (movedOn) _entrance.forward(from: 0);

    // The clock took the question and I never answered, so no answer
    // response ever told me the key. One targeted fetch gets it in time for
    // the reveal rather than waiting on the next heartbeat.
    if (justResolved && next.revealedIndex == null && next.isActive) {
      unawaited(_serverTick());
    }
  }

  void _onUiTick() {
    if (!mounted) return;
    final fraction = _match.isRevealing ? 0.0 : _match.remainingFraction;
    _clock.value = fraction;

    if (_match.isActive && !_match.isRevealing && _chosen == null) {
      final secondsLeft = (fraction * _match.secondsPerQuestion).ceil();
      if (secondsLeft <= 5 && secondsLeft > 0 && secondsLeft != _lastTickSecond) {
        _lastTickSecond = secondsLeft;
        QuizSfx.play(QuizSound.tick);
      }
    }
  }

  Future<void> _serverTick() async {
    if (!mounted || _leaving) return;
    try {
      final next = await QuizMatchService.tick(_match.id);
      _apply(next);
    } catch (_) {
      // A dropped tick is survivable — the next one is 1.2s away, and the
      // Realtime channel is still pushing state changes independently.
    }
  }

  Future<void> _answer(int choice, Offset? at) async {
    if (_chosen != null || _sending || !_match.isActive || _match.isRevealing) {
      return;
    }
    setState(() {
      _chosen = choice;
      _sending = true;
      _floatAt = at;
    });
    QuizSfx.tap();

    try {
      final result = await QuizMatchService.answer(
        matchId: _match.id,
        index: _match.currentIndex,
        choice: choice,
      );
      if (!mounted) return;
      setState(() {
        _sending = false;
        _revealIndex = result.correctIndex;
        _lastPoints = result.points;
        _lastMultiplier = QuizScoring.multiplierFor(result.combo);
        _floatKey++;
        _flashColor = result.correct
            ? ArenaTheme.correctOnNavy
            : ArenaTheme.wrongOnNavy;
      });
      _flash.forward(from: 0);
      if (result.correct) {
        QuizSfx.correct();
        if (at != null) {
          _bursts.fire(at, count: _lastMultiplier > 1 ? 24 : 16);
        }
        if (_lastMultiplier > QuizScoring.multiplierFor(result.combo - 1)) {
          QuizSfx.combo();
        }
      } else {
        QuizSfx.wrong();
      }
      _apply(result.match);
    } catch (e) {
      if (!mounted) return;
      // The server refused it — almost always because the question moved on
      // underneath the tap. Hand the tile back rather than leaving a
      // selection that will never resolve.
      setState(() {
        _sending = false;
        _chosen = null;
      });
      unawaited(_serverTick());
    }
  }

  Future<void> _confirmLeave() async {
    if (_match.isOver) {
      Navigator.of(context).pop(_match);
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ArenaTheme.canvasTop,
        shape: RoundedRectangleBorder(borderRadius: ArenaTheme.cardRadius),
        title: Text(
          'Leave the match?',
          style: AppTextStyles.titleMedium
              .copyWith(color: ArenaTheme.textOnNavy),
        ),
        content: Text(
          // Said plainly, because it is true and irreversible: the server
          // hands the win over the moment this screen goes away.
          'Your opponent wins straight away. There is no rejoining.',
          style: AppTextStyles.bodyMedium
              .copyWith(color: ArenaTheme.textMutedOnNavy),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep playing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: ArenaTheme.wrongOnNavy,
            ),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave != true || !mounted) return;
    _leaving = true;
    _heartbeat?.cancel();
    unawaited(QuizMatchService.forfeit(_match.id));
    if (mounted) Navigator.of(context).pop(_match);
  }

  // ---- Build --------------------------------------------------------------

  AnswerTileState _stateFor(int index) {
    final reveal = _revealIndex;
    if (reveal == null) {
      return _chosen == index ? AnswerTileState.correct : AnswerTileState.idle;
    }
    if (index == reveal) {
      return _chosen == index ? AnswerTileState.correct : AnswerTileState.revealed;
    }
    if (_chosen == index) return AnswerTileState.wrong;
    return AnswerTileState.dimmed;
  }

  @override
  Widget build(BuildContext context) {
    if (_match.status == 'complete' || _match.status == 'cancelled') {
      return _MatchResult(
        match: _match,
        uid: _uid,
        onDone: () => Navigator.of(context).pop(_match),
      );
    }

    final question = _match.question;
    final answered = _chosen != null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: ArenaScaffold(
        flash: _flash,
        flashColor: _flashColor,
        onClose: _confirmLeave,
        showMute: true,
        child: Stack(
          children: [
            Column(
              children: [
                _MatchScoreboard(match: _match, uid: _uid),
                const SizedBox(height: 6),
                RoundProgress(
                  index: _match.currentIndex,
                  total: _match.questionCount,
                ),
                const SizedBox(height: 14),
                if (question == null)
                  const Expanded(
                    child: Center(
                      child: CircularProgressIndicator(
                        color: ArenaTheme.gold,
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: TimerRing(
                              remaining: _clock,
                              totalSeconds: _match.secondsPerQuestion,
                              frozen: answered || _match.isRevealing,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _QuestionCard(question: question),
                          const SizedBox(height: 18),
                          for (var i = 0; i < question.options.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: AnswerTile(
                                label: question.options[i],
                                letter: String.fromCharCode(65 + i),
                                state: _stateFor(i),
                                entrance: _entrance,
                                onTap: answered || _match.isRevealing
                                    ? null
                                    : (centre) => _answer(i, centre),
                              ),
                            ),
                          if (answered && _revealIndex == null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                // Never "waiting". It states what is true
                                // about the opponent, not about a spinner.
                                'Locked in — they are still choosing',
                                textAlign: TextAlign.center,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: ArenaTheme.textFaintOnNavy,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            // Sparks sit above the content but never take a tap.
            Positioned.fill(child: BurstLayer(controller: _bursts)),
            if (_floatAt != null && _lastPoints > 0)
              Positioned(
                left: _floatAt!.dx - 60,
                top: _floatAt!.dy - 40,
                width: 120,
                child: Center(
                  child: FloatingPoints(
                    key: ValueKey(_floatKey),
                    points: _lastPoints,
                    multiplier: _lastMultiplier,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The two-player header: me, them, and who is ahead.
class _MatchScoreboard extends StatelessWidget {
  const _MatchScoreboard({required this.match, required this.uid});

  final QuizMatch match;
  final String? uid;

  @override
  Widget build(BuildContext context) {
    final mine = match.myPoints(uid);
    final theirs = match.theirPoints(uid);
    final opponent = match.opponent;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: _PlayerScore(
              name: 'You',
              photoUrl: null,
              points: mine,
              leading: mine >= theirs,
              answered: match.iAnswered(uid),
              alignEnd: false,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'VS',
              style: AppTextStyles.labelSmall.copyWith(
                color: ArenaTheme.textFaintOnNavy,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: _PlayerScore(
              name: opponent?.name ?? 'Opponent',
              photoUrl: opponent?.photoUrl,
              points: theirs,
              leading: theirs > mine,
              answered: match.theyAnswered(uid),
              alignEnd: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerScore extends StatelessWidget {
  const _PlayerScore({
    required this.name,
    required this.photoUrl,
    required this.points,
    required this.leading,
    required this.answered,
    required this.alignEnd,
  });

  final String name;
  final String? photoUrl;
  final int points;
  final bool leading;

  /// They have locked an answer to the question on screen. The pip says
  /// only THAT, never what — which is what makes it safe to show live, and
  /// it is most of what makes a live round feel live.
  final bool answered;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final avatar = Stack(
      clipBehavior: Clip.none,
      children: [
        UserAvatar(photoUrl: photoUrl, size: 34, name: name),
        if (answered)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: ArenaTheme.correctOnNavy,
                shape: BoxShape.circle,
                border: Border.all(color: ArenaTheme.canvasTop, width: 2),
              ),
            ),
          ),
      ],
    );

    final text = Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.labelSmall.copyWith(
            color: leading ? ArenaTheme.gold : ArenaTheme.textMutedOnNavy,
            fontWeight: FontWeight.w600,
          ),
        ),
        ScorePill(points: points, compact: true),
      ],
    );

    return Row(
      mainAxisAlignment:
          alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: alignEnd
          ? [Flexible(child: text), const SizedBox(width: 8), avatar]
          : [avatar, const SizedBox(width: 8), Flexible(child: text)],
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.question});

  final dynamic question;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ArenaTheme.glass,
        borderRadius: ArenaTheme.cardRadius,
        border: Border.all(color: ArenaTheme.glassBorder),
        boxShadow: ArenaTheme.panelShadow,
      ),
      child: Text(
        question.question as String,
        textAlign: TextAlign.center,
        style: AppTextStyles.titleMedium.copyWith(
          color: ArenaTheme.textOnNavy,
          height: 1.35,
        ),
      ),
    );
  }
}

/// How it ended. Deliberately not a separate route: the final answer's
/// reveal flows straight into this, so the celebration lands on the beat
/// instead of after a navigation.
class _MatchResult extends StatelessWidget {
  const _MatchResult({
    required this.match,
    required this.uid,
    required this.onDone,
  });

  final QuizMatch match;
  final String? uid;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final outcome = match.outcomeFor(uid);
    final mine = match.myPoints(uid);
    final theirs = match.theirPoints(uid);
    final opponent = match.opponent;
    final theyQuit = match.theyForfeited(uid);
    final iQuit = match.iForfeited(uid);

    final (headline, accent) = switch (outcome) {
      1 => (theyQuit ? 'They left — you win' : 'You win!', ArenaTheme.gold),
      0 => ('Dead heat', ArenaTheme.textOnNavy),
      -1 => (iQuit ? 'You left' : 'They got you', ArenaTheme.wrongOnNavy),
      _ => ('Match ended', ArenaTheme.textMutedOnNavy),
    };

    return ArenaScaffold(
      onClose: onDone,
      closeIcon: Icons.close_rounded,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              headline,
              textAlign: TextAlign.center,
              style: AppTextStyles.headlineMedium.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _FinalScore(
                  name: 'You',
                  photoUrl: null,
                  points: mine,
                  correct: match.myCorrect(uid),
                  total: match.questionCount,
                  winner: outcome == 1,
                ),
                _FinalScore(
                  name: opponent?.name ?? 'Opponent',
                  photoUrl: opponent?.photoUrl,
                  points: theirs,
                  correct: match.theirCorrect(uid),
                  total: match.questionCount,
                  winner: outcome == -1,
                ),
              ],
            ),
            const SizedBox(height: 32),
            if (outcome == 1 && !theyQuit)
              Text(
                'Your points are on this week’s leaderboard.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(
                  color: ArenaTheme.textFaintOnNavy,
                ),
              ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: ArenaTheme.actionGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TextButton(
                  onPressed: onDone,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    'Done',
                    style: AppTextStyles.labelLarge.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FinalScore extends StatelessWidget {
  const _FinalScore({
    required this.name,
    required this.photoUrl,
    required this.points,
    required this.correct,
    required this.total,
    required this.winner,
  });

  final String name;
  final String? photoUrl;
  final int points;
  final int correct;
  final int total;
  final bool winner;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: winner ? ArenaTheme.gold : Colors.transparent,
              width: 2,
            ),
          ),
          child: UserAvatar(photoUrl: photoUrl, size: 62, name: name),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: 120,
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTextStyles.labelMedium.copyWith(
              color: ArenaTheme.textOnNavy,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$points',
          style: AppTextStyles.headlineSmall.copyWith(
            color: winner ? ArenaTheme.gold : ArenaTheme.textOnNavy,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          '$correct of $total',
          style: AppTextStyles.bodySmall.copyWith(
            color: ArenaTheme.textFaintOnNavy,
          ),
        ),
      ],
    );
  }
}
