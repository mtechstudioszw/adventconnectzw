import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/quiz_question_model.dart';
import '../../../models/quiz_round.dart';
import '../../../services/ads/rewarded_ad_manager.dart';
import '../../../services/quiz_cloud_service.dart';
import '../../../services/quiz_progress_service.dart';
import '../../../services/quiz_service.dart';
import '../../../services/quiz_sfx.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_text_styles.dart';
import 'arena_theme.dart';
import 'widgets/answer_tile.dart';
import 'widgets/arena_hud.dart';
import 'widgets/arena_scaffold.dart';
import 'widgets/burst_layer.dart';
import 'widgets/countdown_overlay.dart';

/// Plays a round.
///
/// The whole screen is built around making an answer *land*: the clock
/// drains, the tile pops or shakes, gold sparks fly from the tile you
/// touched, the points fly up into the score, and the combo meter climbs.
/// None of it blocks — every effect is fire-and-forget so a slow frame
/// never delays the next question.
class QuizRoundScreen extends StatefulWidget {
  const QuizRoundScreen({super.key, required this.config});

  final QuizRoundConfig config;

  @override
  State<QuizRoundScreen> createState() => _QuizRoundScreenState();
}

class _QuizRoundScreenState extends State<QuizRoundScreen>
    with TickerProviderStateMixin {
  // ---- Round state --------------------------------------------------------
  late int _index = widget.config.startIndex;
  late int _points = widget.config.startPoints;
  late int _combo = widget.config.startCombo;
  int _bestCombo = 0;
  final List<QuizAnswer> _answers = [];

  int? _chosen;
  bool _counting = true;
  bool _finishing = false;

  /// Points scored on the question just answered, for the floating label.
  int _lastPoints = 0;
  int _lastMultiplier = 1;
  int _floatKey = 0;
  Offset? _floatAt;

  // 50/50 lifeline.
  bool _hintUsed = false;
  bool _hintBusy = false;
  final Set<int> _hidden = {};

  // ---- Animation ----------------------------------------------------------
  late final AnimationController _timer;
  late final AnimationController _roundTimer;
  late final AnimationController _entrance;
  late final AnimationController _flash;
  final BurstController _bursts = BurstController();

  late final Animation<double> _remaining =
      Tween<double>(begin: 1, end: 0).animate(_timer);

  /// Speed Round shows the whole-round clock instead of the per-question
  /// one. Built once here rather than per build() — the HUD rebuilds on
  /// every answer and re-creating the animation each time is pure waste.
  late final Animation<double> _roundRemaining =
      Tween<double>(begin: 1, end: 0).animate(_roundTimer);

  Color _flashColor = ArenaTheme.correctOnNavy;
  int _lastTickSecond = -1;

  QuizMode get _mode => widget.config.mode;
  List<QuizQuestion> get _questions => widget.config.questions;
  QuizQuestion get _question => _questions[_index];
  bool get _answered => _chosen != null;

  @override
  void initState() {
    super.initState();

    _timer = AnimationController(
      vsync: this,
      duration: Duration(seconds: _mode.secondsPerQuestion),
    )..addListener(_onTimerTick);

    _roundTimer = AnimationController(
      vsync: this,
      duration: Duration(seconds: _mode.roundSeconds ?? 60),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _finish();
      });

    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );

    _flash = AnimationController(
      vsync: this,
      duration: AppMotion.celebrate,
    );

    QuizSfx.init();
    RewardedAdManager.loadAd();
    QuizProgressService.markSeen(_questions);
    _persist();
  }

  @override
  void dispose() {
    _timer
      ..removeListener(_onTimerTick)
      ..dispose();
    _roundTimer.dispose();
    _entrance.dispose();
    _flash.dispose();
    _bursts.dispose();
    super.dispose();
  }

  // ---- Flow ---------------------------------------------------------------

  void _onCountdownBeat(int index) {
    // The last beat is "GO" and gets the whoosh instead of the tick.
    if (index >= 3) {
      QuizSfx.play(QuizSound.go);
      QuizSfx.hapticCombo();
    } else {
      QuizSfx.countBeat();
    }
  }

  void _startRound() {
    if (!mounted) return;
    setState(() => _counting = false);
    if (_mode.roundSeconds != null) _roundTimer.forward();
    _startQuestion();
  }

  void _startQuestion() {
    _lastTickSecond = -1;
    _entrance.forward(from: 0);
    if (AppMotion.enabled(context)) {
      _timer.forward(from: 0);
    } else {
      _timer.value = 0; // no clock pressure when motion is off
    }
  }

  /// Countdown ticks in the last few seconds.
  void _onTimerTick() {
    if (_answered || !mounted) return;
    final secondsLeft = (_remaining.value * _mode.secondsPerQuestion).ceil();
    if (secondsLeft <= 5 && secondsLeft > 0 && secondsLeft != _lastTickSecond) {
      _lastTickSecond = secondsLeft;
      QuizSfx.play(QuizSound.tick);
    }
  }

  Future<void> _answer(int choice, Offset? at) async {
    if (_answered) return;
    _timer.stop();

    final correct = _question.isCorrect(choice);
    final remaining = _remaining.value.clamp(0.0, 1.0);
    final nextCombo = correct ? _combo + 1 : 0;
    final multiplier = QuizScoring.multiplierFor(nextCombo);
    final earned = QuizScoring.pointsFor(
      correct: correct,
      remainingFraction: remaining,
      comboAfter: nextCombo,
      mode: _mode,
    );

    setState(() {
      _chosen = choice;
      _combo = nextCombo;
      if (nextCombo > _bestCombo) _bestCombo = nextCombo;
      _points += earned;
      _lastPoints = earned;
      _lastMultiplier = multiplier;
      _floatAt = at;
      _floatKey++;
      _flashColor =
          correct ? ArenaTheme.correctOnNavy : ArenaTheme.wrongOnNavy;
    });

    _answers.add(QuizAnswer(
      questionId: _question.id,
      chosenIndex: choice,
      correct: correct,
      elapsedMs:
          ((1 - remaining) * _mode.secondsPerQuestion * 1000).round(),
      points: earned,
      comboAfter: nextCombo,
    ));

    _flash.forward(from: 0);
    unawaited(QuizProgressService.recordAnswer(correct));

    if (correct) {
      QuizSfx.correct();
      if (at != null) {
        _bursts.fire(at, count: multiplier > 1 ? 24 : 16);
      }
      // A multiplier step-up gets its own fanfare on top of the ding.
      if (multiplier > QuizScoring.multiplierFor(nextCombo - 1)) {
        QuizSfx.combo();
      }
      if (_mode == QuizMode.mistakes) {
        // Learned it — take it off the list.
        unawaited(QuizProgressService.clearMistake(_question.id));
      }
    } else {
      QuizSfx.wrong();
      if (_mode.tracksMistakes) {
        unawaited(QuizProgressService.addMistake(_question));
      }
    }

    // Sudden death.
    if (!correct && _mode.suddenDeath) {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (mounted) _finish();
      return;
    }

    // Speed round keeps moving; the other modes let you read the explanation.
    if (_mode == QuizMode.speed) {
      await Future<void>.delayed(const Duration(milliseconds: 850));
      if (mounted && !_finishing) _next();
    }
  }

  void _next() {
    if (_index >= _questions.length - 1) {
      _finish();
      return;
    }
    setState(() {
      _index++;
      _chosen = null;
      _hintUsed = false;
      _hintBusy = false;
      _hidden.clear();
      _lastPoints = 0;
    });
    _persist();
    _startQuestion();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    _timer.stop();
    _roundTimer.stop();

    final perfect = _answers.isNotEmpty &&
        _answers.every((a) => a.correct) &&
        _answers.length >= 5 &&
        _mode != QuizMode.survival;
    final bonus = perfect ? QuizScoring.perfectBonus : 0;
    final total = _points + bonus;
    // Must be computed from the TOTAL (bonus included) — the results screen
    // fills the XP bar by `totalXp - xpEarned`, so if this disagreed with
    // what's actually banked the bar would animate from the wrong place.
    final xp = QuizScoring.xpFor(total);

    var leveledUp = false;
    var isNewBest = false;
    try {
      if (_mode == QuizMode.daily) {
        await QuizProgressService.recordDailyComplete();
      }
      leveledUp = await QuizProgressService.addXp(xp);
      await QuizProgressService.addPoints(total);
      isNewBest = await QuizProgressService.recordScore(_mode, total);
      await QuizProgressService.clearSession();
    } catch (_) {
      // Storage hiccups must never swallow the results screen.
    }

    final result = QuizRoundResult(
      mode: _mode,
      title: widget.config.title,
      answers: List.of(_answers),
      points: total,
      bonusPoints: bonus,
      bestCombo: _bestCombo,
      xpEarned: xp,
      newLevel: QuizProgressService.level(),
      leveledUp: leveledUp,
      streak: QuizProgressService.currentStreak(),
      isNewBestScore: isNewBest,
    );

    // Fire-and-forget: the results screen must never wait on the network.
    unawaited(QuizCloudService.recordRound(result));
    unawaited(QuizCloudService.syncUp());

    if (!mounted) return;
    // Hand the result back to the lobby, which owns the round → results →
    // replay flow. Pushing results from here instead would resolve the
    // lobby's await the moment the round ended (pushReplacement completes
    // the route it replaces), and back-from-results would land on a
    // finished round.
    Navigator.of(context).pop(result);
  }

  void _persist() {
    QuizProgressService.saveSession(
      questions: _questions,
      index: _index,
      points: _points,
      combo: _combo,
      mode: _mode,
      title: widget.config.title,
    );
  }

  /// Opt-in rewarded lifeline: remove two wrong answers.
  ///
  /// A missing ad must NEVER block the hint — poor fill or an offline
  /// player would otherwise just see the lifeline do nothing.
  Future<void> _useHint() async {
    if (_hintUsed || _answered || _hintBusy) return;
    if (RewardedAdManager.isReady) {
      setState(() => _hintBusy = true);
      final earned = await RewardedAdManager.showForReward();
      if (!mounted) return;
      setState(() => _hintBusy = false);
      if (earned) _grantHint();
    } else {
      _grantHint();
    }
    RewardedAdManager.loadAd();
  }

  void _grantHint() {
    if (_hintUsed) return;
    QuizSfx.tap();
    setState(() {
      _hintUsed = true;
      final wrong = [
        for (var i = 0; i < _question.options.length; i++)
          if (i != _question.correctIndex) i,
      ]..shuffle();
      _hidden.addAll(wrong.take(2));
    });
  }

  Future<void> _confirmQuit() async {
    if (_finishing) return;
    final quit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ArenaTheme.canvasTop,
        shape: RoundedRectangleBorder(borderRadius: ArenaTheme.cardRadius),
        title: Text(
          'Leave the round?',
          style: AppTextStyles.titleMedium.copyWith(
            color: ArenaTheme.textOnNavy,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'Your progress is saved — you can pick up right where you left off.',
          style: AppTextStyles.bodyMedium
              .copyWith(color: ArenaTheme.textMutedOnNavy),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Keep playing',
                style: AppTextStyles.labelMedium
                    .copyWith(color: ArenaTheme.textMutedOnNavy)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Leave',
                style: AppTextStyles.labelMedium.copyWith(
                    color: ArenaTheme.gold, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (quit == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _report() async {
    final question = _question;
    await QuizService.reportQuestion(question: question);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Thanks — we\'ll review this question.')),
    );
  }

  // ---- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmQuit();
      },
      child: ArenaScaffold(
        flash: _flash,
        flashColor: _flashColor,
        backdropIntensity: 0.65,
        showTopBar: false,
        child: Stack(
          children: [
            Column(
              children: [
                _buildHud(),
                Expanded(child: _buildBody()),
                if (_answered && _mode != QuizMode.speed) _buildNextButton(),
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
            if (_counting)
              Positioned.fill(
                child: CountdownOverlay(
                  onBeat: _onCountdownBeat,
                  onDone: _startRound,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHud() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
        child: Column(
          children: [
            Row(
              children: [
                ArenaIconButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Leave round',
                  onTap: _confirmQuit,
                ),
                const SizedBox(width: 10),
                ScorePill(points: _points),
                const Spacer(),
                ComboMeter(combo: _combo),
                const SizedBox(width: 10),
                TimerRing(
                  remaining: _mode.roundSeconds != null
                      ? _roundRemaining
                      : _remaining,
                  totalSeconds: _mode.roundSeconds ??
                      _mode.secondsPerQuestion,
                  frozen: _answered && _mode.roundSeconds == null,
                ),
              ],
            ),
            const SizedBox(height: 12),
            RoundProgress(index: _index, total: _questions.length),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      children: [
        _buildQuestionCard(),
        const SizedBox(height: 18),
        for (var i = 0; i < _question.options.length; i++)
          AnswerTile(
            // Keyed per question so tiles rebuild fresh each time rather
            // than animating the previous question's state.
            key: ValueKey('${_question.id}-$i'),
            label: _question.options[i],
            letter: String.fromCharCode(65 + i),
            hidden: _hidden.contains(i),
            entrance: CurvedAnimation(
              parent: _entrance,
              curve: Interval(
                (0.25 + i * 0.11).clamp(0.0, 0.9),
                1.0,
                curve: AppMotion.easeOut,
              ),
            ),
            state: _stateFor(i),
            onTap: (tileCentre) => _answer(i, tileCentre),
          ),
        if (_answered) _buildExplanation(),
      ],
    );
  }

  AnswerTileState _stateFor(int i) {
    if (!_answered) return AnswerTileState.idle;
    if (i == _question.correctIndex) {
      return i == _chosen ? AnswerTileState.correct : AnswerTileState.revealed;
    }
    return i == _chosen ? AnswerTileState.wrong : AnswerTileState.dimmed;
  }

  Widget _buildQuestionCard() {
    return AnimatedBuilder(
      animation: _entrance,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(
          CurvedAnimation(parent: _entrance, curve: const Interval(0, 0.7))
              .value,
        );
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset((1 - t) * 34, 0),
            child: child,
          ),
        );
      },
      child: ArenaPanel(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _question.category.toUpperCase(),
                  style: AppTextStyles.labelSmall.copyWith(
                    color: ArenaTheme.gold,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.3,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: ArenaTheme.glassStrong,
                    borderRadius:
                        BorderRadius.circular(ArenaTheme.radiusPill),
                  ),
                  child: Text(
                    _question.difficulty,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: ArenaTheme.difficulty(_question.difficulty),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${_index + 1}/${_questions.length}',
                  style: AppTextStyles.labelSmall
                      .copyWith(color: ArenaTheme.textFaintOnNavy),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _question.question,
              style: AppTextStyles.titleLarge.copyWith(
                color: ArenaTheme.textOnNavy,
                fontWeight: FontWeight.w700,
                height: 1.38,
                fontSize: 19,
              ),
            ),
            if (!_answered && !_hintUsed) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _hintBusy ? null : _useHint,
                  icon: _hintBusy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: ArenaTheme.gold,
                          ),
                        )
                      : const Icon(Icons.lightbulb_outline, size: 17),
                  label: const Text('50/50 lifeline'),
                  style: TextButton.styleFrom(
                    foregroundColor: ArenaTheme.gold,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExplanation() {
    final correct = _question.isCorrect(_chosen!);
    final explanation = _question.explanation ?? '';
    final reference = _question.reference ?? '';
    final hasReference = reference.isNotEmpty && reference != '-';
    if (explanation.isEmpty && !hasReference) return const SizedBox(height: 8);

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: AppMotion.maybe(context, AppMotion.standard),
        curve: AppMotion.easeOut,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, (1 - t) * 12), child: child),
        ),
        child: ArenaPanel(
          padding: const EdgeInsets.all(15),
          borderColor: (correct
                  ? ArenaTheme.correctOnNavy
                  : ArenaTheme.gold)
              .withValues(alpha: 0.35),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    correct
                        ? Icons.check_circle_rounded
                        : Icons.menu_book_rounded,
                    size: 17,
                    color: correct
                        ? ArenaTheme.correctOnNavy
                        : ArenaTheme.gold,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    correct ? 'Correct!' : 'Good to know',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: correct
                          ? ArenaTheme.correctOnNavy
                          : ArenaTheme.gold,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: _report,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      child: Text(
                        'Report',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: ArenaTheme.textFaintOnNavy,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (explanation.isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(
                  explanation,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: ArenaTheme.textOnNavy,
                    height: 1.55,
                  ),
                ),
              ],
              if (hasReference) ...[
                const SizedBox(height: 7),
                Text(
                  reference,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: ArenaTheme.gold,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNextButton() {
    final isLast = _index >= _questions.length - 1;
    final ended = _mode.suddenDeath && !_question.isCorrect(_chosen!);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
        child: ArenaButton(
          label: ended
              ? 'See results'
              : isLast
                  ? 'See results'
                  : 'Next question',
          icon: ended || isLast
              ? Icons.emoji_events_rounded
              : Icons.arrow_forward_rounded,
          gold: ended || isLast,
          onTap: ended ? _finish : _next,
        ),
      ),
    );
  }
}
