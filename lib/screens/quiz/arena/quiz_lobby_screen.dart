import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/quiz_question_model.dart';
import '../../../models/quiz_round.dart';
import '../../../services/quiz_challenge_service.dart';
import '../../../services/quiz_cloud_service.dart';
import '../../../services/quiz_progress_service.dart';
import '../../../services/quiz_service.dart';
import '../../../services/quiz_sfx.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/motion/brand_spinner.dart';
import 'arena_theme.dart';
import 'quiz_challenge_screen.dart';
import 'quiz_leaderboard_screen.dart';
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
    unawaited(QuizService.warm());
    unawaited(QuizCloudService.restoreIfEmpty().then((restored) {
      if (restored && mounted) setState(() {});
      // After a restore the cloud balance wins; otherwise this grants the
      // starting coins on a genuinely new player's first visit.
      return QuizProgressService.ensureStartingCoins()
          .then((_) => mounted ? setState(() {}) : null);
    }));
    _refreshChallenges();
  }

  @override
  void dispose() {
    _intro.dispose();
    // The arena owns the sound players; free them when the player leaves.
    unawaited(QuizSfx.dispose());
    super.dispose();
  }

  // ---- Flow ---------------------------------------------------------------

  Future<void> _play(QuizMode mode, {String? category}) async {
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mode == QuizMode.mistakes
              ? 'No mistakes to fix yet — play a round first.'
              : 'No questions available yet. Check your connection.'),
        ),
      );
      return;
    }

    await _runRound(
      QuizRoundConfig(
        mode: mode,
        questions: questions,
        title: category ?? mode.label,
        category: category,
      ),
    );
  }

  /// round → results → optional replay, then refresh the lobby.
  Future<void> _runRound(QuizRoundConfig config) async {
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

    final again = await Navigator.of(context).push<QuizMode>(
      MaterialPageRoute(builder: (_) => QuizResultsScreen(result: result)),
    );
    if (!mounted) return;
    setState(() {});

    // A fresh round is offered as a challenge — you can only challenge
    // someone with a score you've actually just set.
    if (config.challengeId == null && _pendingChallengeTo != null) {
      final opponent = _pendingChallengeTo!;
      _pendingChallengeTo = null;
      // Captured before the await — the analyzer is right that `context`
      // shouldn't be reached for across an async gap.
      final messenger = ScaffoldMessenger.of(context);
      final sent = await QuizChallengeService.create(
        opponentId: opponent.userId,
        result: result,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(sent
              ? 'Challenge sent to ${opponent.name}.'
              : 'Could not send the challenge. Try again.'),
        ),
      );
      setState(() {});
      return;
    }

    // Replay the same kind of round, topic included.
    if (again != null) {
      await _play(again, category: config.category);
    }
  }

  /// Pick a friend, then play a round that becomes the challenge.
  Future<void> _startChallenge() async {
    final opponent = await Navigator.of(context).push<QuizOpponent>(
      MaterialPageRoute(builder: (_) => const QuizOpponentPickerScreen()),
    );
    if (!mounted || opponent == null) return;
    _pendingChallengeTo = opponent;
    await _play(QuizMode.practice);
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

  void _refreshChallenges() {
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
          child: Transform.translate(offset: Offset(0, (1 - t) * 26), child: inner),
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
              const SizedBox(height: 18),
              _reveal(2, _buildDaily()),
              const SizedBox(height: 18),
              _reveal(3, _buildSectionLabel('GAME MODES')),
              const SizedBox(height: 10),
              _reveal(4, _buildModes(mistakes)),
              const SizedBox(height: 20),
              _reveal(5, _buildSectionLabel('TOPICS')),
              const SizedBox(height: 10),
              _reveal(6, _buildTopics()),
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
            CurvedAnimation(parent: _intro, curve: const Interval(0, 0.55))
                .value,
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
          const Icon(Icons.play_circle_fill_rounded,
              color: ArenaTheme.gold, size: 30),
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
                  style: AppTextStyles.bodySmall
                      .copyWith(color: ArenaTheme.textMutedOnNavy),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              await QuizProgressService.clearSession();
              if (mounted) setState(() {});
            },
            child: Text('Discard',
                style: AppTextStyles.labelSmall
                    .copyWith(color: ArenaTheme.textFaintOnNavy)),
          ),
          IconButton(
            onPressed: () => _resume(session),
            icon: const Icon(Icons.arrow_forward_rounded,
                color: ArenaTheme.gold),
          ),
        ],
      ),
    );
  }

  Widget _buildDaily() {
    final played = QuizProgressService.playedToday();
    final streak = QuizProgressService.currentStreak();
    return ArenaPanel(
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 18),
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
              const Icon(Icons.today_rounded,
                  color: ArenaTheme.goldBright, size: 21),
              const SizedBox(width: 9),
              Text(
                'Daily Challenge',
                style: AppTextStyles.titleLarge.copyWith(
                  color: ArenaTheme.textOnNavy,
                  fontWeight: FontWeight.w800,
                  fontSize: 19,
                ),
              ),
              const Spacer(),
              if (streak > 0)
                Row(
                  children: [
                    const Icon(Icons.local_fire_department_rounded,
                        color: ArenaTheme.gold, size: 18),
                    const SizedBox(width: 3),
                    Text(
                      '$streak',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: ArenaTheme.goldBright,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            played
                ? 'Today\'s challenge is done — your streak is safe. Play it again for points any time.'
                : 'Five questions. Everyone gets the same set today. Keep your streak alive.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: ArenaTheme.textMutedOnNavy,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 15),
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

  Widget _buildModes(int mistakes) {
    final tiles = <Widget>[
      _ModeTile(
        mode: QuizMode.practice,
        icon: Icons.shuffle_rounded,
        onTap: () => _play(QuizMode.practice),
      ),
      _ModeTile(
        mode: QuizMode.survival,
        icon: Icons.favorite_rounded,
        best: QuizProgressService.bestScore(QuizMode.survival),
        onTap: () => _play(QuizMode.survival),
      ),
      _ModeTile(
        mode: QuizMode.speed,
        icon: Icons.bolt_rounded,
        best: QuizProgressService.bestScore(QuizMode.speed),
        onTap: () => _play(QuizMode.speed),
      ),
      _ModeTile(
        mode: QuizMode.mistakes,
        icon: Icons.auto_fix_high_rounded,
        badge: mistakes > 0 ? '$mistakes' : null,
        enabled: mistakes > 0,
        onTap: () => _play(QuizMode.mistakes),
      ),
      _ChallengeTile(
        incoming: _incomingChallenges,
        onChallenge: _startChallenge,
        onOpen: _openChallenges,
      ),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.28,
      children: tiles,
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
            style: AppTextStyles.bodyMedium
                .copyWith(color: ArenaTheme.textMutedOnNavy),
          );
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final category in categories)
              _TopicChip(
                label: category,
                onTap: () =>
                    _play(QuizMode.category, category: category),
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
      icon: QuizSfx.muted
          ? Icons.volume_off_rounded
          : Icons.volume_up_rounded,
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

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.mode,
    required this.icon,
    required this.onTap,
    this.best = 0,
    this.badge,
    this.enabled = true,
  });

  final QuizMode mode;
  final IconData icon;
  final VoidCallback onTap;
  final int best;
  final String? badge;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
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
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ArenaTheme.glass,
              borderRadius: ArenaTheme.tileRadius,
              border: Border.all(color: ArenaTheme.glassBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: ArenaTheme.gold.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 18, color: ArenaTheme.gold),
                    ),
                    const Spacer(),
                    if (badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: ArenaTheme.gold,
                          borderRadius: BorderRadius.circular(
                              ArenaTheme.radiusPill),
                        ),
                        child: Text(
                          badge!,
                          style: AppTextStyles.labelSmall.copyWith(
                            color: ArenaTheme.canvasTop,
                            fontWeight: FontWeight.w800,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  mode.label,
                  style: AppTextStyles.titleSmall.copyWith(
                    color: ArenaTheme.textOnNavy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  best > 0 ? 'Best: $best' : mode.blurb,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: best > 0
                        ? ArenaTheme.gold
                        : ArenaTheme.textFaintOnNavy,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Two actions in one tile: challenge someone new, or answer the ones
/// waiting for you. The badge is the hook — an unanswered challenge is the
/// strongest reason to reopen the arena.
class _ChallengeTile extends StatelessWidget {
  const _ChallengeTile({
    required this.incoming,
    required this.onChallenge,
    required this.onOpen,
  });

  final int incoming;
  final VoidCallback onChallenge;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final waiting = incoming > 0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: ArenaTheme.tileRadius,
        onTap: () {
          QuizSfx.tap();
          waiting ? onOpen() : onChallenge();
        },
        onLongPress: onOpen,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: waiting
                ? ArenaTheme.gold.withValues(alpha: 0.14)
                : ArenaTheme.glass,
            borderRadius: ArenaTheme.tileRadius,
            border: Border.all(
              color: waiting
                  ? ArenaTheme.gold.withValues(alpha: 0.55)
                  : ArenaTheme.glassBorder,
            ),
            boxShadow:
                waiting ? ArenaTheme.glow(ArenaTheme.gold, strength: 0.5) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: ArenaTheme.gold.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.sports_kabaddi_rounded,
                        size: 18, color: ArenaTheme.gold),
                  ),
                  const Spacer(),
                  if (waiting)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: ArenaTheme.gold,
                        borderRadius:
                            BorderRadius.circular(ArenaTheme.radiusPill),
                      ),
                      child: Text(
                        '$incoming',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: ArenaTheme.canvasTop,
                          fontWeight: FontWeight.w800,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                waiting ? 'Challenges' : 'Challenge a friend',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.titleSmall.copyWith(
                  color: ArenaTheme.textOnNavy,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                waiting
                    ? '$incoming waiting for you'
                    : 'Same questions. Higher score wins.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelSmall.copyWith(
                  color: waiting
                      ? ArenaTheme.gold
                      : ArenaTheme.textFaintOnNavy,
                  fontSize: 11,
                  height: 1.3,
                ),
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
