import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/presence_service.dart';
import '../../../models/quiz_match.dart';
import '../../../models/quiz_question_model.dart';
import '../../../models/quiz_round.dart';
import '../../../services/quiz_challenge_service.dart';
import '../../../services/quiz_cloud_service.dart';
import '../../../services/quiz_home_signal.dart';
import '../../../services/quiz_launch_intent.dart';
import '../../../services/quiz_match_service.dart';
import '../../../services/quiz_music.dart';
import '../../../services/quiz_progress_service.dart';
import '../../../services/quiz_service.dart';
import '../../../services/quiz_sfx.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/motion/brand_spinner.dart';
import 'arena_theme.dart';
import 'quiz_boot_screen.dart' show showQuizSettings;
import 'quiz_challenge_screen.dart';
import 'quiz_leaderboard_screen.dart';
import 'quiz_matchmaking_screen.dart';
import 'quiz_results_screen.dart';
import 'quiz_round_screen.dart';
import 'widgets/arena_scaffold.dart';
import 'widgets/xp_bar.dart';

/// The Quiz Arena's home.
///
/// Deliberately NOT palette-aware: the arena is always navy, in light mode
/// and dark, so that tapping "Quiz" feels like opening a different app
/// rather than pushing another screen in this one. It also owns the whole
/// round → results → play-again flow, which keeps navigation in one place.
class QuizLobbyScreen extends StatefulWidget {
  const QuizLobbyScreen({super.key});

  @override
  State<QuizLobbyScreen> createState() => _QuizLobbyScreenState();
}

class _QuizLobbyScreenState extends State<QuizLobbyScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  );

  late Future<List<String>> _categories;
  bool _busy = false;

  /// Set while a "challenge a friend" round is being played — the challenge
  /// is only created once there's a real score to challenge with.
  QuizOpponent? _pendingChallengeTo;
  int _incomingChallenges = 0;

  /// Live invites aimed at me right now. Separate from [_incomingChallenges]
  /// because they expire in five minutes — showing the two in one count
  /// would make a number that keeps dropping on its own.
  int _liveInvites = 0;

  @override
  void initState() {
    super.initState();
    _categories = QuizService.categories();
    _intro.forward();

    // Warm everything behind the intro animation so the first Start is
    // instant: the sound players, the curated cache, and the KJV index the
    // generator builds (a ~4.5 MB parse we never want to pay for in front
    // of the player).
    unawaited(QuizSfx.init());
    // The soundtrack starts in the LOBBY, not just once a round begins.
    //
    // It was only ever started by quiz_round_screen and quiz_match_screen,
    // so every other surface in the arena — the lobby you sit on while
    // choosing a mode, the leaderboard, the results screen — was silent.
    // "The music is not playing in the quiz game" is the accurate report
    // of that: the arena has a soundtrack that almost never plays.
    //
    // QuizMusic.start() is idempotent (it returns early when a player
    // already exists), so the round screens calling it again is harmless,
    // and it still stands down on its own when the member's own Library
    // music is playing.
    unawaited(QuizMusic.start());
    unawaited(QuizService.warm());
    unawaited(
      QuizCloudService.restoreIfEmpty().then((restored) {
        if (restored && mounted) setState(() {});
        // After a restore the cloud balance wins; otherwise this grants the
        // starting coins on a genuinely new player's first visit.
        return QuizProgressService.ensureStartingCoins().then(
          (_) => mounted ? setState(() {}) : null,
        );
      }),
    );
    _refreshChallenges();

    // Home can ask for a mode to start immediately — the Daily Challenge
    // card "taps straight into the questions" (founder, 17 Aug). Started
    // here rather than duplicated on Home so the round keeps the lobby's
    // whole flow: results, streak, challenge submit/send, opponent claim.
    //
    // Deferred a frame: _play pushes a route and can show a SnackBar,
    // neither of which is legal from initState.
    final wanted = QuizLaunchIntent.take();
    if (wanted != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _play(wanted);
      });
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    // The arena owns the sound players; free them when the player leaves.
    // The soundtrack goes with them — it is arena ambience, and leaving it
    // running under the rest of the app would be the "music kept playing
    // after I left" bug in a new place.
    unawaited(QuizMusic.stop());
    unawaited(QuizSfx.dispose());
    super.dispose();
  }

  // ---- Flow ---------------------------------------------------------------

  Future<void> _play(QuizMode mode, {String? category, String? title}) async {
    if (_busy) return;
    setState(() => _busy = true);

    List<QuizQuestion> questions;
    try {
      questions = await QuizService.buildRound(mode: mode, category: category);
    } catch (_) {
      questions = const [];
    }
    if (!mounted) return;
    setState(() => _busy = false);

    if (questions.isEmpty) {
      // No round means no challenge either — drop the opponent rather than
      // leaving them queued up to be challenged by whatever is played next.
      _pendingChallengeTo = null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mode == QuizMode.mistakes
                ? 'No mistakes to fix yet — play a round first.'
                : 'No questions available yet. Check your connection.',
          ),
        ),
      );
      return;
    }

    await _runRound(
      QuizRoundConfig(
        mode: mode,
        questions: questions,
        title: title ?? category ?? mode.label,
        category: category,
      ),
    );
  }

  /// round → results → optional replay, then refresh the lobby.
  Future<void> _runRound(QuizRoundConfig config) async {
    // Claim the pending opponent HERE, before anything can go wrong.
    //
    // It used to be read at the very end, after the results screen had been
    // popped, and cleared only on the one path that reached that line. So
    // every other exit left it set: quitting mid-round, or a round that
    // never started because the questions failed to build. The member got
    // no challenge — "challenge a friend doesn't work" — and worse, the
    // next unrelated round they played silently fired the challenge at
    // whoever they had picked minutes earlier.
    final challengeTo = config.challengeId == null ? _pendingChallengeTo : null;
    _pendingChallengeTo = null;

    final result = await Navigator.of(context).push<QuizRoundResult>(
      MaterialPageRoute(builder: (_) => QuizRoundScreen(config: config)),
    );
    if (!mounted) return;
    setState(() {}); // streak / XP / resume may all have changed

    if (result == null) return; // quit mid-round

    // Answering a challenge: submit before the results screen, so the
    // outcome is already settled by the time they look at it.
    if (config.challengeId != null) {
      await QuizChallengeService.submit(
        challengeId: config.challengeId!,
        points: result.points,
        correct: result.correctCount,
      );
      if (!mounted) return;
    }

    // Sending a challenge: also BEFORE the results screen, and for the same
    // reason. This used to run after the member had closed their results,
    // so anyone who backed straight out of the arena from that screen —
    // which is the natural thing to do when you have finished — never sent
    // the thing they had set the score for.
    if (challengeTo != null) {
      // Captured before the await — the analyzer is right that `context`
      // shouldn't be reached for across an async gap.
      final messenger = ScaffoldMessenger.of(context);
      final sent = await QuizChallengeService.create(
        opponentId: challengeTo.userId,
        result: result,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            sent
                ? 'Challenge sent to ${challengeTo.name}.'
                : 'Could not send the challenge. Check your connection.',
          ),
        ),
      );
    }

    final again = await Navigator.of(context).push<QuizMode>(
      MaterialPageRoute(builder: (_) => QuizResultsScreen(result: result)),
    );
    if (!mounted) return;
    setState(() {});

    // Replay the same kind of round, topic included.
    if (again != null) {
      await _play(again, category: config.category);
    }
  }

  /// Pick a friend, then play a round that becomes the challenge.
  ///
  /// The round has to SAY so. It used to start an ordinary round titled
  /// "Practice", with nothing on screen connecting it to the friend who had
  /// just been chosen — so it read as though picking them had done nothing,
  /// and the challenge appeared out of nowhere several screens later.
  Future<void> _startChallenge() async {
    final opponent = await Navigator.of(context).push<QuizOpponent>(
      MaterialPageRoute(builder: (_) => const QuizOpponentPickerScreen()),
    );
    if (!mounted || opponent == null) return;
    _pendingChallengeTo = opponent;
    await _play(QuizMode.practice, title: 'Challenging ${opponent.name}');
  }

  /// Play a challenge someone sent you — the exact same questions they got.
  Future<void> _playChallenge(QuizChallenge challenge) async {
    if (challenge.questions.isEmpty) return;
    await _runRound(
      QuizRoundConfig(
        mode: QuizMode.practice,
        questions: challenge.questions,
        title: 'vs ${challenge.otherName}',
        challengeId: challenge.id,
      ),
    );
  }

  Future<void> _openChallenges() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => QuizChallengesScreen(onPlay: _playChallenge),
      ),
    );
    if (mounted) _refreshChallenges();
  }

  /// Open the live arena, then refresh — a match just played has moved the
  /// weekly points and may have cleared an invite.
  Future<void> _openLiveMatch() async {
    await Navigator.of(context).push<QuizMatch>(
      MaterialPageRoute(builder: (_) => const QuizMatchmakingScreen()),
    );
    if (!mounted) return;
    setState(() {});
    _refreshChallenges();
  }

  void _refreshChallenges() {
    QuizMatchService.invites().then((list) {
      // Keep Home's live dot in step with what the lobby just learned.
      // Without this the dot stays lit after the member has come in and
      // dealt with the invite, until Home's own refresh window reopens —
      // and returning from the arena does not re-run Home's bootstrap.
      // Set outside the mounted check: the count is true regardless of
      // whether this screen is still on the tree.
      QuizHomeSignal.invites.value = list.length;
      if (mounted) setState(() => _liveInvites = list.length);
    });
    QuizChallengeService.incoming().then((list) {
      if (mounted) setState(() => _incomingChallenges = list.length);
    });
  }

  Future<void> _resume(Map<String, dynamic> session) async {
    if (_busy) return;
    final questions = QuizProgressService.sessionQuestions(session);
    if (questions.isEmpty) {
      await QuizProgressService.clearSession();
      if (mounted) setState(() {});
      return;
    }
    await _runRound(
      QuizRoundConfig(
        mode: QuizProgressService.sessionMode(session),
        questions: questions,
        title: session['title']?.toString() ?? 'Quiz',
        startIndex: (session['index'] as num?)?.toInt() ?? 0,
        startPoints: (session['points'] as num?)?.toInt() ?? 0,
        startCombo: (session['combo'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  // ---- Build --------------------------------------------------------------

  /// A section's entrance, staggered behind the intro.
  Animation<double> _step(int index) => CurvedAnimation(
    parent: _intro,
    curve: Interval(
      (0.30 + index * 0.075).clamp(0.0, 0.92),
      1.0,
      curve: AppMotion.easeOut,
    ),
  );

  Widget _reveal(int index, Widget child) {
    final animation = _step(index);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, inner) {
        if (!AppMotion.enabled(context)) return inner!;
        final t = animation.value;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 26),
            child: inner,
          ),
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = QuizProgressService.loadSession();
    final mistakes = QuizProgressService.mistakeCount();

    return ArenaScaffold(
      showTopBar: false,
      child: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              _reveal(0, _buildIdentity()),
              if (session != null) ...[
                const SizedBox(height: 16),
                _reveal(1, _buildResume(session)),
              ],
              // Hierarchy, not decoration (founder, 17 Aug). The lobby was
              // a uniform 2-up grid of glass tiles at ONE visual weight, so
              // nothing on it read as the thing to do — the same fault that
              // was fixed on the create screen. Today's challenge now
              // dominates, live match gets its own full-width strip because
              // it is the only real-time thing in the app, and the rest
              // drop to a quiet list.
              const SizedBox(height: 18),
              _reveal(2, _buildDailyHero()),
              const SizedBox(height: 14),
              _reveal(3, _buildLiveStrip()),
              const SizedBox(height: 20),
              _reveal(4, _buildSectionLabel('MORE WAYS TO PLAY')),
              const SizedBox(height: 10),
              _reveal(5, _buildModeList(mistakes)),
              const SizedBox(height: 20),
              _reveal(6, _buildSectionLabel('TOPICS')),
              const SizedBox(height: 10),
              _reveal(7, _buildTopics()),
            ],
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x99060C1F),
                child: Center(child: BrandSpinner(size: 34)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return SafeArea(
      bottom: false,
      child: AnimatedBuilder(
        animation: _intro,
        builder: (context, child) {
          if (!AppMotion.enabled(context)) return child!;
          final t = Curves.easeOutCubic.transform(
            CurvedAnimation(
              parent: _intro,
              curve: const Interval(0, 0.55),
            ).value,
          );
          return Opacity(
            opacity: t,
            child: Transform.scale(scale: 0.88 + 0.12 * t, child: child),
          );
        },
        child: Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Row(
            children: [
              ArenaIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onTap: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BIBLE QUIZ',
                      style: AppTextStyles.headlineSmall.copyWith(
                        color: ArenaTheme.textOnNavy,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.4,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Know it. Live it.',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: ArenaTheme.gold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              // Arena settings — sound, music, haptics.
              //
              // This control existed ONLY on the boot screen, which is on
              // screen for the second or two the arena takes to load. So
              // the founder's report was exactly right: "it appears only
              // when the quiz lobby is loading." You could see it, but not
              // reliably reach it, and once the lobby painted there was no
              // way back to it without leaving the arena entirely.
              //
              // The lobby is where somebody actually decides they want the
              // music off, so the button belongs here.
              ArenaIconButton(
                icon: Icons.tune_rounded,
                tooltip: 'Arena settings',
                onTap: () {
                  QuizSfx.tap();
                  showQuizSettings(context);
                },
              ),
              const SizedBox(width: 8),
              ArenaIconButton(
                icon: Icons.leaderboard_rounded,
                tooltip: 'Leaderboard',
                onTap: () {
                  QuizSfx.tap();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const QuizLeaderboardScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              const _MuteButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdentity() {
    final streak = QuizProgressService.currentStreak();
    return ArenaPanel(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      child: Column(
        children: [
          XpBar(xp: QuizProgressService.totalXp()),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  icon: Icons.local_fire_department_rounded,
                  value: '$streak',
                  label: streak == 1 ? 'day streak' : 'day streak',
                ),
              ),
              Expanded(
                child: _MiniStat(
                  icon: Icons.percent_rounded,
                  value: '${QuizProgressService.accuracyPct()}',
                  label: 'accuracy',
                ),
              ),
              Expanded(
                child: _MiniStat(
                  icon: Icons.monetization_on_rounded,
                  value: '${QuizProgressService.coins()}',
                  label: 'coins',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResume(Map<String, dynamic> session) {
    final total = (session['questions'] as List?)?.length ?? 0;
    final index = (session['index'] as num?)?.toInt() ?? 0;
    return ArenaPanel(
      padding: const EdgeInsets.fromLTRB(15, 13, 12, 13),
      borderColor: ArenaTheme.gold.withValues(alpha: 0.5),
      child: Row(
        children: [
          const Icon(
            Icons.play_circle_fill_rounded,
            color: ArenaTheme.gold,
            size: 30,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Continue "${session['title'] ?? 'Quiz'}"',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleSmall.copyWith(
                    color: ArenaTheme.textOnNavy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Question ${index + 1} of $total',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: ArenaTheme.textMutedOnNavy,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              await QuizProgressService.clearSession();
              if (mounted) setState(() {});
            },
            child: Text(
              'Discard',
              style: AppTextStyles.labelSmall.copyWith(
                color: ArenaTheme.textFaintOnNavy,
              ),
            ),
          ),
          IconButton(
            onPressed: () => _resume(session),
            icon: const Icon(
              Icons.arrow_forward_rounded,
              color: ArenaTheme.gold,
            ),
          ),
        ],
      ),
    );
  }

  /// The hero. Today's challenge is the habit the whole quiz hangs on, so
  /// it carries the weight that used to be spread evenly across six tiles.
  ///
  /// The streak is the reason to come back and is promoted accordingly:
  /// it was a small gold number in the corner, and it is now a labelled
  /// chip on its own line — "3 day streak" says what the number means,
  /// which a flame glyph and a digit never did.
  Widget _buildDailyHero() {
    final played = QuizProgressService.playedToday();
    final streak = QuizProgressService.currentStreak();
    return ArenaPanel(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      gradient: LinearGradient(
        colors: [
          const Color(0xFF2B7FE0).withValues(alpha: 0.34),
          ArenaTheme.gold.withValues(alpha: 0.12),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderColor: ArenaTheme.gold.withValues(alpha: 0.42),
      glow: const Color(0xFF2B7FE0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.today_rounded,
                color: ArenaTheme.goldBright,
                size: 17,
              ),
              const SizedBox(width: 7),
              Text(
                'TODAY',
                style: AppTextStyles.labelSmall.copyWith(
                  color: ArenaTheme.goldBright,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              if (played)
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: ArenaTheme.correctOnNavy,
                      size: 15,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Done',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: ArenaTheme.correctOnNavy,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Flexible/soft-wrapping: this is the biggest type on the screen
          // and it has to survive 2.5x text scale without throwing.
          Text(
            'Daily Challenge',
            style: AppTextStyles.headlineLarge.copyWith(
              color: ArenaTheme.textOnNavy,
              fontWeight: FontWeight.w800,
              fontSize: 27,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            played
                ? 'Done for today — your streak is safe. Play it again for points any time.'
                : 'Five questions. Everyone gets the same set today.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: ArenaTheme.textMutedOnNavy,
              height: 1.45,
            ),
          ),
          if (streak > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: ArenaTheme.gold.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(ArenaTheme.radiusPill),
                border: Border.all(
                  color: ArenaTheme.gold.withValues(alpha: 0.45),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.local_fire_department_rounded,
                    color: ArenaTheme.goldBright,
                    size: 16,
                  ),
                  const SizedBox(width: 5),
                  // Flexible, not bare: the label scales with the system
                  // font and this Row is inside a pill with no give.
                  Flexible(
                    child: Text(
                      streak == 1 ? '1 day streak' : '$streak day streak',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelMedium.copyWith(
                        color: ArenaTheme.goldBright,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          ArenaButton(
            label: played ? 'Play again' : 'Start today\'s challenge',
            icon: played ? Icons.replay_rounded : Icons.play_arrow_rounded,
            gold: !played,
            onTap: () => _play(QuizMode.daily),
          ),
        ],
      ),
    );
  }

  /// Live match, promoted out of the grid onto its own full-width strip.
  ///
  /// It is the only real-time, person-to-person feature in the app, and it
  /// was one of six identical tiles — which is most of why only ~11 members
  /// have ever played one. The strip keeps the tile's hard-won honesty
  /// about an empty arena (see [_LiveMatchStrip]).
  Widget _buildLiveStrip() {
    return _LiveMatchStrip(
      invites: _liveInvites,
      online: PresenceService.onlineUsers.length,
      onTap: _openLiveMatch,
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: AppTextStyles.labelSmall.copyWith(
        color: ArenaTheme.gold,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.6,
        fontSize: 11.5,
      ),
    );
  }

  /// The quiet list. Everything that is NOT today's challenge or a live
  /// opponent, at a deliberately lower weight.
  ///
  /// A list, not a grid: rows give each mode its blurb back (the grid had
  /// to drop them for space), read top-to-bottom in one pass, and — the
  /// point of the change — visibly rank below the hero instead of
  /// competing with it. The async challenge stays here rather than beside
  /// live match: they are different games, one played whenever you like.
  Widget _buildModeList(int mistakes) {
    return Column(
      children: [
        _ModeRow(
          label: QuizMode.practice.label,
          blurb: QuizMode.practice.blurb,
          icon: Icons.shuffle_rounded,
          onTap: () => _play(QuizMode.practice),
        ),
        _ModeRow(
          label: QuizMode.survival.label,
          blurb: QuizMode.survival.blurb,
          icon: Icons.favorite_rounded,
          best: QuizProgressService.bestScore(QuizMode.survival),
          onTap: () => _play(QuizMode.survival),
        ),
        _ModeRow(
          label: QuizMode.speed.label,
          blurb: QuizMode.speed.blurb,
          icon: Icons.bolt_rounded,
          best: QuizProgressService.bestScore(QuizMode.speed),
          onTap: () => _play(QuizMode.speed),
        ),
        _ModeRow(
          label: QuizMode.mistakes.label,
          // Say why it is unavailable rather than just dimming it. A
          // disabled row with no explanation reads as broken.
          blurb: mistakes > 0
              ? QuizMode.mistakes.blurb
              : 'Nothing to fix yet — play a round first.',
          icon: Icons.auto_fix_high_rounded,
          badge: mistakes > 0 ? '$mistakes' : null,
          enabled: mistakes > 0,
          onTap: () => _play(QuizMode.mistakes),
        ),
        _ModeRow(
          label: 'Challenge a friend',
          blurb: _incomingChallenges > 0
              ? 'Your turn in $_incomingChallenges'
              : 'Send five questions. They play when they can.',
          icon: Icons.sports_kabaddi_rounded,
          badge: _incomingChallenges > 0 ? '$_incomingChallenges' : null,
          highlight: _incomingChallenges > 0,
          onTap: _incomingChallenges > 0 ? _openChallenges : _startChallenge,
        ),
        _ModeRow(
          label: 'Leaderboard',
          blurb: 'Where you stand this week.',
          icon: Icons.leaderboard_rounded,
          onTap: () {
            QuizSfx.tap();
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const QuizLeaderboardScreen(),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTopics() {
    return FutureBuilder<List<String>>(
      future: _categories,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Center(child: BrandSpinner(size: 26)),
          );
        }
        final categories = snapshot.data ?? const <String>[];
        if (categories.isEmpty) {
          return Text(
            'No topics yet.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: ArenaTheme.textMutedOnNavy,
            ),
          );
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final category in categories)
              _TopicChip(
                label: category,
                onTap: () => _play(QuizMode.category, category: category),
              ),
          ],
        );
      },
    );
  }
}

class _MuteButton extends StatefulWidget {
  const _MuteButton();

  @override
  State<_MuteButton> createState() => _MuteButtonState();
}

class _MuteButtonState extends State<_MuteButton> {
  @override
  Widget build(BuildContext context) {
    return ArenaIconButton(
      icon: QuizSfx.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
      tooltip: QuizSfx.muted ? 'Unmute' : 'Mute',
      onTap: () async {
        await QuizSfx.toggleMute();
        if (!QuizSfx.muted) QuizSfx.play(QuizSound.tap);
        if (mounted) setState(() {});
      },
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 17, color: ArenaTheme.gold),
        const SizedBox(height: 5),
        Text(
          value,
          style: AppTextStyles.titleMedium.copyWith(
            color: ArenaTheme.textOnNavy,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: ArenaTheme.textFaintOnNavy,
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }
}

/// One row in the quiet "more ways to play" list.
///
/// Replaces the square `_ModeTile` that lived in a 2-up grid. The grid was
/// the fault the founder named: six tiles at one visual weight, so nothing
/// read as the thing to do, and each was too small to carry its blurb. A
/// row is lower-weight than the hero by construction AND has the width to
/// say what the mode actually is.
class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.label,
    required this.blurb,
    required this.icon,
    required this.onTap,
    this.best = 0,
    this.badge,
    this.enabled = true,
    this.highlight = false,
  });

  final String label;
  final String blurb;
  final IconData icon;
  final VoidCallback onTap;
  final int best;
  final String? badge;
  final bool enabled;

  /// Draws the row in the "something is waiting for you" state — used when
  /// a challenge is your turn. Deliberately the same green the live strip
  /// uses, so "someone is waiting" reads identically wherever it appears.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final accent = highlight ? ArenaTheme.correctOnNavy : ArenaTheme.gold;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: ArenaTheme.tileRadius,
            onTap: enabled
                ? () {
                    QuizSfx.tap();
                    onTap();
                  }
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 13,
              ),
              decoration: BoxDecoration(
                color: highlight
                    ? ArenaTheme.correctOnNavy.withValues(alpha: 0.12)
                    : ArenaTheme.glass,
                borderRadius: ArenaTheme.tileRadius,
                border: Border.all(
                  color: highlight
                      ? ArenaTheme.correctOnNavy.withValues(alpha: 0.5)
                      : ArenaTheme.glassBorder,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 19, color: accent),
                  ),
                  const SizedBox(width: 13),
                  // Expanded, not bare: these labels and blurbs scale with
                  // the system font, and an unflexed Text in a Row THROWS
                  // rather than clipping. This project has shipped that bug
                  // before.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.titleSmall.copyWith(
                            color: ArenaTheme.textOnNavy,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          blurb,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.labelSmall.copyWith(
                            color: highlight
                                ? ArenaTheme.correctOnNavy
                                : ArenaTheme.textFaintOnNavy,
                            fontSize: 11.5,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(
                          ArenaTheme.radiusPill,
                        ),
                      ),
                      child: Text(
                        badge!,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: ArenaTheme.canvasTop,
                          fontWeight: FontWeight.w800,
                          fontSize: 10.5,
                        ),
                      ),
                    )
                  else if (best > 0)
                    Text(
                      'Best $best',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: ArenaTheme.textFaintOnNavy,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  else
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: ArenaTheme.textFaintOnNavy,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Live head-to-head, as a full-width strip directly under the hero.
///
/// Promoted out of the 2-up grid (founder, 17 Aug): it is the only
/// real-time, person-to-person feature in the app and it was one of six
/// identical squares, which is most of why only ~11 members have ever
/// played one.
///
/// The honesty about an empty arena is carried over unchanged and matters
/// as much here as it did in the tile: the strip promised "head to head"
/// whether forty people were online or nobody, so anyone tapping it at a
/// quiet hour waited out a search, found no one, and concluded the feature
/// was broken. An empty arena is the COMMON case, not the edge one.
class _LiveMatchStrip extends StatelessWidget {
  const _LiveMatchStrip({
    required this.invites,
    required this.online,
    required this.onTap,
  });

  final int invites;

  /// Members online right now, from the presence roster.
  final int online;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final waiting = invites > 0;
    final live = online > 1;
    // Three states, three colours: someone is waiting (green, glowing),
    // people are around (green), nobody is (faint).
    final accent = waiting || live
        ? ArenaTheme.correctOnNavy
        : ArenaTheme.textFaintOnNavy;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: ArenaTheme.tileRadius,
        onTap: () {
          QuizSfx.tap();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: waiting
                ? ArenaTheme.correctOnNavy.withValues(alpha: 0.16)
                : ArenaTheme.glass,
            borderRadius: ArenaTheme.tileRadius,
            border: Border.all(
              color: waiting
                  ? ArenaTheme.correctOnNavy.withValues(alpha: 0.6)
                  : ArenaTheme.glassBorder,
            ),
            boxShadow: waiting
                ? ArenaTheme.glow(ArenaTheme.correctOnNavy, strength: 0.5)
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ArenaTheme.correctOnNavy.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  size: 22,
                  color: ArenaTheme.correctOnNavy,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      waiting ? 'Someone wants to play' : 'Live match',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall.copyWith(
                        color: ArenaTheme.textOnNavy,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      waiting
                          ? 'Join before it expires'
                          : live
                          ? '$online online now · play someone'
                          : 'Quiet right now — challenge someone instead',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: accent,
                        fontSize: 11.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (waiting)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: ArenaTheme.correctOnNavy,
                    borderRadius: BorderRadius.circular(ArenaTheme.radiusPill),
                  ),
                  child: Text(
                    '$invites',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: ArenaTheme.canvasTop,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: ArenaTheme.textFaintOnNavy,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopicChip extends StatelessWidget {
  const _TopicChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(ArenaTheme.radiusPill),
        onTap: () {
          QuizSfx.tap();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: ArenaTheme.glass,
            borderRadius: BorderRadius.circular(ArenaTheme.radiusPill),
            border: Border.all(color: ArenaTheme.glassBorder),
          ),
          child: Text(
            label,
            style: AppTextStyles.labelMedium.copyWith(
              color: ArenaTheme.textOnNavy,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
