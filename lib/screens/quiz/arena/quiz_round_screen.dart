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

  // ---- Lifelines ----------------------------------------------------------
  /// Removed by 50/50.
  final Set<int> _hidden = {};

  /// Spent on the current question — all reset by [_next].
  final Set<Lifeline> _usedThisQuestion = {};

  /// Second Chance is once per ROUND, not per question; it's the expensive
  /// one and un-losing a Survival run repeatedly would make the mode moot.
  bool _secondChanceUsed = false;
  Lifeline? _lifelineBusy;

  /// Mutable because Extra Time lengthens the current question's clock.
  late int _questionSeconds = _mode.secondsPerQuestion;

  /// The combo going INTO the current question, so Second Chance can put it
  /// back rather than leaving the player revived but reset to zero.
  late int _comboBeforeQuestion = widget.config.startCombo;

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
    // _questionSeconds, not the mode default — Extra Time changes it.
    final secondsLeft = (_remaining.value * _questionSeconds).ceil();
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
      elapsedMs: ((1 - remaining) * _questionSeconds * 1000).round(),
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

    // Sudden death — but never auto-end the run while a Second Chance is
    // still on the table. That lifeline exists precisely for this moment,
    // and ending the round from under the player would make it unusable.
    if (!correct && _mode.suddenDeath) {
      if (_secondChanceUsed) {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        if (mounted && !_finishing) _finish();
      }
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
      _hidden.clear();
      _usedThisQuestion.clear();
      _lifelineBusy = null;
      _questionSeconds = _mode.secondsPerQuestion;
      _lastPoints = 0;
      _floatAt = null;
    });
    // Snapshot the combo so Second Chance can restore it if this question
    // goes wrong.
    _comboBeforeQuestion = _combo;
    _timer.duration = Duration(seconds: _questionSeconds);
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
    var coins = QuizCoins.forRound(total);
    try {
      final wasFirstDailyToday =
          _mode == QuizMode.daily && !QuizProgressService.playedToday();
      if (_mode == QuizMode.daily) {
        await QuizProgressService.recordDailyComplete();
        // Only the first daily of the day pays the bonus — replays don't.
        if (wasFirstDailyToday) coins += QuizCoins.dailyBonus;
      }
      leveledUp = await QuizProgressService.addXp(xp);
      if (leveledUp) coins += QuizCoins.levelUpBonus;
      await QuizProgressService.addCoins(coins);
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
      questions: List.of(_questions),
      points: total,
      bonusPoints: bonus,
      bestCombo: _bestCombo,
      xpEarned: xp,
      coinsEarned: coins,
      newLevel: QuizProgressService.level(),
      leveledUp: leveledUp,
      streak: QuizProgressService.currentStreak(),
      isNewBestScore: isNewBest,
      challengeId: widget.config.challengeId,
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

  // ---- Lifelines ----------------------------------------------------------

  bool _lifelineAvailable(Lifeline lifeline) {
    if (_usedThisQuestion.contains(lifeline)) return false;
    switch (lifeline) {
      case Lifeline.secondChance:
        // Offered only in response to a wrong answer, once per round.
        return !_secondChanceUsed &&
            _answered &&
            !_question.isCorrect(_chosen!);
      case Lifeline.fiftyFifty:
        return !_answered && _hidden.isEmpty;
      case Lifeline.skip:
        return !_answered;
      case Lifeline.extraTime:
        // Pointless once the clock is already empty.
        return !_answered && _remaining.value > 0.02;
    }
  }

  /// Pay for [lifeline] with coins, or offer a rewarded ad when the player
  /// can't afford it.
  ///
  /// A missing ad must NEVER hard-block a lifeline — poor fill or an
  /// offline player would just see the button do nothing, which is the
  /// exact complaint the old 50/50 generated. If there's no ad to show,
  /// the lifeline is granted anyway.
  Future<void> _useLifeline(Lifeline lifeline) async {
    if (_lifelineBusy != null || !_lifelineAvailable(lifeline)) return;

    final paid = await QuizProgressService.spendCoins(lifeline.cost);
    if (!paid) {
      if (RewardedAdManager.isReady) {
        setState(() => _lifelineBusy = lifeline);
        final earned = await RewardedAdManager.showForReward();
        if (!mounted) return;
        setState(() => _lifelineBusy = null);
        RewardedAdManager.loadAd();
        if (!earned) return;
      } else {
        RewardedAdManager.loadAd();
      }
    }

    if (!mounted) return;
    QuizSfx.tap();
    _usedThisQuestion.add(lifeline);
    switch (lifeline) {
      case Lifeline.fiftyFifty:
        _applyFiftyFifty();
      case Lifeline.skip:
        _applySkip();
      case Lifeline.extraTime:
        _applyExtraTime();
      case Lifeline.secondChance:
        _applySecondChance();
    }
  }

  void _applyFiftyFifty() {
    setState(() {
      final wrong = [
        for (var i = 0; i < _question.options.length; i++)
          if (i != _question.correctIndex) i,
      ]..shuffle();
      _hidden.addAll(wrong.take(2));
    });
  }

  /// Skips without recording an answer at all — a paid skip shouldn't dent
  /// your accuracy, and the combo deliberately survives.
  void _applySkip() {
    if (_index >= _questions.length - 1) {
      _finish();
      return;
    }
    _next();
  }

  void _applyExtraTime() {
    final secondsLeft = _remaining.value * _questionSeconds;
    final newTotal = _questionSeconds + LifelineInfo.extraSeconds;
    setState(() => _questionSeconds = newTotal);
    _timer.duration = Duration(seconds: newTotal);
    // Rebase the controller so the ring keeps the time it had, plus ten.
    _timer.value =
        (1 - ((secondsLeft + LifelineInfo.extraSeconds) / newTotal))
            .clamp(0.0, 1.0);
    _timer.forward();
  }

  /// Undo a wrong answer and re-open the question.
  ///
  /// The wrong answer is removed from [_answers] and the lifetime accuracy
  /// stat is walked back too — otherwise a revived question would be
  /// counted twice, once wrong and once right.
  void _applySecondChance() {
    final chosen = _chosen;
    if (chosen == null) return;
    _answers.removeWhere((a) => a.questionId == _question.id);
    unawaited(QuizProgressService.undoAnswer(correct: false));
    if (_mode.tracksMistakes) {
      unawaited(QuizProgressService.clearMistake(_question.id));
    }

    setState(() {
      _secondChanceUsed = true;
      _chosen = null;
      // Put back the streak they had walking into this question, rather
      // than reviving them onto a zeroed combo.
      _combo = _comboBeforeQuestion;
      _flashColor = ArenaTheme.correctOnNavy;
      _lastPoints = 0;
      _floatAt = null;
      // The answer they just tried is off the table — that's the mercy.
      _hidden.add(chosen);
    });
    _entrance.forward(from: 0.55);
    _timer.forward();
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
                const SizedBox(width: 8),
                ScorePill(points: _points, compact: true),
                const SizedBox(width: 6),
                _buildCoinPill(),
                const Spacer(),
                ComboMeter(combo: _combo),
                const SizedBox(width: 10),
                TimerRing(
                  remaining: _mode.roundSeconds != null
                      ? _roundRemaining
                      : _remaining,
                  totalSeconds: _mode.roundSeconds ?? _questionSeconds,
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
        const SizedBox(height: 12),
        _buildLifelines(),
        const SizedBox(height: 14),
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

  /// The lifeline strip.
  ///
  /// Second Chance is the odd one out: it only appears *after* a wrong
  /// answer, so it's the one lifeline that can be offered at the exact
  /// moment a Survival run would otherwise end.
  Widget _buildLifelines() {
    final available = [
      for (final lifeline in Lifeline.values)
        if (_lifelineAvailable(lifeline)) lifeline,
    ];
    if (available.isEmpty) return const SizedBox.shrink();

    final coins = QuizProgressService.coins();
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: available.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final lifeline = available[i];
          final affordable = coins >= lifeline.cost;
          final busy = _lifelineBusy == lifeline;
          return _LifelineChip(
            lifeline: lifeline,
            affordable: affordable,
            busy: busy,
            highlight: lifeline == Lifeline.secondChance,
            onTap: _lifelineBusy != null ? null : () => _useLifeline(lifeline),
          );
        },
      ),
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

  Widget _buildCoinPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: ArenaTheme.glass,
        borderRadius: BorderRadius.circular(ArenaTheme.radiusPill),
        border: Border.all(color: ArenaTheme.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.monetization_on_rounded,
              size: 14, color: ArenaTheme.gold),
          const SizedBox(width: 4),
          Text(
            '${QuizProgressService.coins()}',
            style: AppTextStyles.labelSmall.copyWith(
              color: ArenaTheme.goldBright,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
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

/// One lifeline button.
///
/// Shows the coin price when the player can afford it, and switches to an
/// explicit "watch ad" affordance when they can't — so the trade is always
/// visible before they tap, never a surprise.
class _LifelineChip extends StatelessWidget {
  const _LifelineChip({
    required this.lifeline,
    required this.affordable,
    required this.busy,
    required this.onTap,
    this.highlight = false,
  });

  final Lifeline lifeline;
  final bool affordable;
  final bool busy;
  final bool highlight;
  final VoidCallback? onTap;

  IconData get _icon => switch (lifeline) {
        Lifeline.fiftyFifty => Icons.filter_2_rounded,
        Lifeline.skip => Icons.skip_next_rounded,
        Lifeline.extraTime => Icons.more_time_rounded,
        Lifeline.secondChance => Icons.favorite_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final accent = highlight ? ArenaTheme.gold : ArenaTheme.textOnNavy;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(ArenaTheme.radiusPill),
        onTap: busy ? null : onTap,
        child: Tooltip(
          message: lifeline.description,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: highlight
                  ? ArenaTheme.gold.withValues(alpha: 0.16)
                  : ArenaTheme.glass,
              borderRadius: BorderRadius.circular(ArenaTheme.radiusPill),
              border: Border.all(
                color: highlight
                    ? ArenaTheme.gold.withValues(alpha: 0.55)
                    : ArenaTheme.glassBorder,
              ),
              boxShadow: highlight
                  ? ArenaTheme.glow(ArenaTheme.gold, strength: 0.45)
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ArenaTheme.gold,
                    ),
                  )
                else
                  Icon(_icon, size: 16, color: accent),
                const SizedBox(width: 7),
                Text(
                  lifeline.label,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 7),
                if (affordable)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.monetization_on_rounded,
                          size: 12, color: ArenaTheme.gold),
                      const SizedBox(width: 2),
                      Text(
                        '${lifeline.cost}',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: ArenaTheme.gold,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  )
                else
                  const Icon(Icons.play_circle_outline_rounded,
                      size: 14, color: ArenaTheme.gold),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
