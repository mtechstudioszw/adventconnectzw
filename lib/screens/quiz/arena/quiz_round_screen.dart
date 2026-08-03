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
  const QuizRoundScreen({
    super.key,
    required this.config,
    this.autoStart = true,
  });

  final QuizRoundConfig config;

  /// Whether to run the countdown film and boot the services the arena
  /// needs (sound pool, rewarded ad, progress persistence).
  ///
  /// Tests pass false: those calls reach audioplayers, AdMob and Hive,
  /// none of which exist under a headless binding, and the countdown
  /// overlay stands between the test and the clock it wants to run out.
  /// With it false the first question starts immediately and the round
  /// logic — scoring, timeout, sudden death — is reachable on its own.
  final bool autoStart;

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

  /// Showing the 3-2-1-GO film. Assigned in [initState] rather than here
  /// because a field initializer runs before `widget` is consulted.
  late bool _counting;
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

  Lifeline? _lifelineBusy;

  /// Mutable because Extra Time lengthens the current question's clock.
  late int _questionSeconds = _mode.secondsPerQuestion;

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

  /// The per-question clock ran out before a choice was made.
  ///
  /// Kept separate from [_chosen] rather than faking a selection: the
  /// answer tiles read [_chosen] to decide which one the player picked,
  /// and a sentinel there would light a tile nobody touched. With this
  /// flag set and [_chosen] still null, [_stateFor] reveals the correct
  /// answer and dims the rest — which is exactly the "time's up" state.
  bool _timedOut = false;

  /// True once the question is closed, whether by a choice or the clock.
  bool get _answered => _chosen != null || _timedOut;

  /// Did the player get this question right?
  ///
  /// Running out of time is getting it WRONG (founder's call, 2 Aug 2026),
  /// and on that path [_chosen] is deliberately still null — so asking
  /// `_question.isCorrect(_chosen!)` threw `Null check operator used on a
  /// null value` the instant the reveal rebuilt. Both reveal widgets are
  /// gated on [_answered], which [_timedOut] alone satisfies, so the
  /// crash was guaranteed on every timeout rather than occasional.
  bool get _wasCorrect =>
      _chosen != null && _question.isCorrect(_chosen!);

  @override
  void initState() {
    super.initState();

    _timer = AnimationController(
      vsync: this,
      duration: Duration(seconds: _mode.secondsPerQuestion),
    )
      ..addListener(_onTimerTick)
      ..addStatusListener(_onTimerStatus);

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

    _counting = widget.autoStart;
    if (widget.autoStart) {
      QuizSfx.init();
      RewardedAdManager.loadAd();
      QuizProgressService.markSeen(_questions);
      _persist();
    }
  }

  /// Set once the first question's clock has been started by [autoStart]
  /// being false. Normally the countdown film ends and calls
  /// [_startRound] for us.
  bool _startedWithoutCountdown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.autoStart || _startedWithoutCountdown) return;
    _startedWithoutCountdown = true;
    // Here rather than a post-frame callback: _startQuestion reads
    // AppMotion from the context, which is legal from this point on, and
    // starting a controller from a post-frame callback hands its ticker a
    // start time the first frame has already passed — which trips
    // AnimationController's `elapsedInSeconds >= 0.0` assertion.
    _startQuestion();
  }

  /// The "let them read what they missed" pause before the round moves on.
  ///
  /// A cancellable Timer rather than `await Future.delayed(...)`, because
  /// `mounted` is NOT a sufficient guard here: while the widget tree is
  /// being finalized an element is already deactivated but `mounted` still
  /// reads true, so a delayed continuation that passed the check went on
  /// to read an ancestor off a dead context. Leaving the quiz during the
  /// reveal is the ordinary way to hit that. Cancelling in [dispose] means
  /// the work simply never runs.
  Timer? _pendingAdvance;

  /// Runs [action] after [delay] unless the screen goes away first.
  void _advanceAfter(Duration delay, VoidCallback action) {
    _pendingAdvance?.cancel();
    _pendingAdvance = Timer(delay, () {
      _pendingAdvance = null;
      if (!mounted || _finishing) return;
      action();
    });
  }

  @override
  void dispose() {
    _pendingAdvance?.cancel();
    _pendingAdvance = null;
    _timer
      ..removeListener(_onTimerTick)
      ..removeStatusListener(_onTimerStatus)
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

  void _onTimerStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) unawaited(_timeUp());
  }

  /// The clock beat the player to it.
  ///
  /// Founder's call (2 Aug 2026): running out of time IS getting the
  /// question wrong, and there is no second attempt at it — the round
  /// records the miss, shows what the answer was, and moves on by itself
  /// until every question has been seen.
  ///
  /// Before this, the per-question controller had a listener for the
  /// ticking sound and no status listener at all, so reaching zero did
  /// nothing whatsoever: the ring sat empty and the question stayed open
  /// indefinitely, which made the countdown decorative.
  Future<void> _timeUp() async {
    if (_answered || _finishing || !mounted) return;

    _timer.stop();

    setState(() {
      _timedOut = true;
      // A miss breaks the streak exactly as a wrong answer does.
      _combo = 0;
      _lastPoints = 0;
      _lastMultiplier = 1;
      _floatAt = null;
      _flashColor = ArenaTheme.wrongOnNavy;
    });

    _answers.add(QuizAnswer(
      questionId: _question.id,
      // -1 is the established "never chose" sentinel, shared with Skip.
      chosenIndex: -1,
      correct: false,
      elapsedMs: _questionSeconds * 1000,
      points: 0,
      comboAfter: 0,
    ));

    _flash.forward(from: 0);
    unawaited(QuizProgressService.recordAnswer(false));
    // The same cue as a wrong answer, because that is what this is. No
    // separate clip: the sound set is authored, and inventing an asset
    // name that does not exist is how a sound silently stops playing.
    QuizSfx.wrong();
    if (_mode.tracksMistakes) {
      unawaited(QuizProgressService.addMistake(_question));
    }

    // Long enough to read the answer that was missed, short enough that
    // the round never feels stalled. Sudden death ends here instead.
    _advanceAfter(const Duration(milliseconds: 1400), () {
      if (_mode.suddenDeath) {
        _finish();
      } else {
        _next();
      }
    });
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

    // Sudden death ends on a wrong answer. This used to hold the round
    // open when a Second Chance was still available; that lifeline is
    // retired, so waiting would have left the run frozen on the question
    // it should have ended on.
    if (!correct && _mode.suddenDeath) {
      _advanceAfter(const Duration(milliseconds: 1200), _finish);
      return;
    }

    // Speed round keeps moving; the other modes let you read the explanation.
    if (_mode == QuizMode.speed) {
      _advanceAfter(const Duration(milliseconds: 850), _next);
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
      _timedOut = false;
      _hidden.clear();
      _usedThisQuestion.clear();
      _lifelineBusy = null;
      _questionSeconds = _mode.secondsPerQuestion;
      _lastPoints = 0;
      _floatAt = null;
    });
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
        // Retired 2 Aug 2026 by founder call: "no try option until you
        // finish all questions". A question you got wrong — or let the
        // clock take — stays wrong, and the run continues to the end.
        //
        // Closed off here rather than deleted from the enum, because
        // Lifeline values are persisted on finished rounds and dropping
        // one would change how old rounds decode. The rail filters on
        // this method, so the button simply stops being offered.
        return false;
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
        // Unreachable: _lifelineAvailable never offers it any more.
        break;
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
    final correct = _wasCorrect;
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
    // Timing out in sudden death ends the run, exactly as a wrong answer
    // does — _wasCorrect is false either way.
    final ended = _mode.suddenDeath && !_wasCorrect;
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
