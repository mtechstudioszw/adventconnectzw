import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/share_config.dart';
import '../../../models/quiz_round.dart';
import '../../../services/ads/interstitial_ad_manager.dart';
import '../../../services/quiz_progress_service.dart';
import '../../../services/quiz_sfx.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_text_styles.dart';
import 'arena_theme.dart';
import 'quiz_review_screen.dart';
import 'widgets/arena_scaffold.dart';
import 'widgets/burst_layer.dart';
import 'widgets/quiz_share_card.dart';
import 'widgets/xp_bar.dart';

/// The payoff.
///
/// A round used to end on a static percentage in a circle. Now the score
/// rolls up, the stars land one at a time with a haptic each, sparks fire
/// on the last one, and the XP bar fills from where you were to where you
/// are. The ad waits until all of that has finished — an interstitial
/// landing on top of the celebration was the old behaviour and it undercut
/// the entire moment.
class QuizResultsScreen extends StatefulWidget {
  const QuizResultsScreen({super.key, required this.result});

  final QuizRoundResult result;

  @override
  State<QuizResultsScreen> createState() => _QuizResultsScreenState();
}

class _QuizResultsScreenState extends State<QuizResultsScreen>
    with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  final BurstController _bursts = BurstController();

  int _starsShown = 0;
  bool _celebrationDone = false;
  bool _sharing = false;
  Timer? _starTimer;

  QuizRoundResult get _result => widget.result;

  /// Where the XP bar starts filling from.
  late final int _xpBefore =
      (QuizProgressService.totalXp() - _result.xpEarned).clamp(0, 1 << 31);

  @override
  void initState() {
    super.initState();
    _enter.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _celebrate());
  }

  @override
  void dispose() {
    _starTimer?.cancel();
    _enter.dispose();
    _bursts.dispose();
    super.dispose();
  }

  Future<void> _celebrate() async {
    if (!mounted) return;
    QuizSfx.play(QuizSound.finish);

    if (!AppMotion.enabled(context)) {
      setState(() {
        _starsShown = _result.stars;
        _celebrationDone = true;
      });
      _afterCelebration();
      return;
    }

    // Stars land one at a time — the pause between them is the drama.
    for (var i = 0; i < _result.stars; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 420));
      if (!mounted) return;
      setState(() => _starsShown = i + 1);
      QuizSfx.hapticCorrect();
      if (i == _result.stars - 1) {
        final size = MediaQuery.sizeOf(context);
        _bursts.fire(
          Offset(size.width / 2, size.height * 0.30),
          count: 26,
          speed: 1.25,
        );
      }
    }

    if (_result.leveledUp) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      QuizSfx.play(QuizSound.levelUp);
      QuizSfx.hapticCombo();
    }

    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _celebrationDone = true);
    _afterCelebration();
  }

  /// The one capped interstitial for the session — only now that the
  /// celebration has actually played out.
  void _afterCelebration() {
    InterstitialAdManager.maybeShow();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return ArenaScaffold(
      showTopBar: false,
      backdropIntensity: 1.0,
      child: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
                    children: [
                      const SizedBox(height: 10),
                      _buildStars(),
                      const SizedBox(height: 18),
                      Text(
                        result.headline,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.headlineMedium.copyWith(
                          color: ArenaTheme.textOnNavy,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${result.correctCount} of ${result.total} correct'
                        '${result.total > 0 ? " · ${result.accuracyPct}%" : ""}',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: ArenaTheme.textMutedOnNavy),
                      ),
                      const SizedBox(height: 22),
                      _buildScore(),
                      const SizedBox(height: 16),
                      _buildStats(),
                      if (result.isNewBestScore) ...[
                        const SizedBox(height: 14),
                        _buildBanner(
                          icon: Icons.emoji_events_rounded,
                          label: 'NEW PERSONAL BEST',
                          detail: '${result.mode.label} record beaten',
                        ),
                      ],
                      if (result.mode == QuizMode.daily &&
                          result.streak > 0) ...[
                        const SizedBox(height: 14),
                        _buildBanner(
                          icon: Icons.local_fire_department_rounded,
                          label: '${result.streak}-DAY STREAK',
                          detail: result.streak == 1
                              ? 'Come back tomorrow to keep it alive'
                              : 'Keep it going tomorrow',
                        ),
                      ],
                      const SizedBox(height: 22),
                      _buildXp(),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
                _buildActions(),
              ],
            ),
          ),
          Positioned.fill(child: BurstLayer(controller: _bursts)),
        ],
      ),
    );
  }

  Widget _buildStars() {
    return SizedBox(
      height: 78,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: i < _starsShown ? 1.0 : 0.0),
                duration: AppMotion.maybe(context, AppMotion.celebrate),
                curve: Curves.elasticOut,
                builder: (context, t, _) {
                  // The middle star sits higher, like an arcade scoreboard.
                  final lift = i == 1 ? 8.0 : 0.0;
                  return Transform.translate(
                    offset: Offset(0, -lift * t),
                    child: Transform.scale(
                      scale: 0.55 + 0.45 * t,
                      child: Icon(
                        i < _starsShown
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: i == 1 ? 62 : 54,
                        color: i < _starsShown
                            ? ArenaTheme.gold
                            : Colors.white.withValues(alpha: 0.18),
                        shadows: i < _starsShown
                            ? [
                                BoxShadow(
                                  color: ArenaTheme.gold
                                      .withValues(alpha: 0.55 * t),
                                  blurRadius: 24,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScore() {
    return Column(
      children: [
        Text(
          'POINTS',
          style: AppTextStyles.labelSmall.copyWith(
            color: ArenaTheme.textFaintOnNavy,
            letterSpacing: 2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: _result.points.toDouble()),
          duration: AppMotion.maybe(
              context, const Duration(milliseconds: 1200)),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) => ShaderMask(
            shaderCallback: (rect) =>
                ArenaTheme.goldGradient.createShader(rect),
            child: Text(
              '${value.round()}',
              textAlign: TextAlign.center,
              style: AppTextStyles.displayLarge.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 54,
                height: 1.05,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        if (_result.bonusPoints > 0) ...[
          const SizedBox(height: 4),
          Text(
            'includes a ${_result.bonusPoints} perfect-round bonus',
            style: AppTextStyles.labelSmall
                .copyWith(color: ArenaTheme.gold, fontSize: 11.5),
          ),
        ],
      ],
    );
  }

  Widget _buildStats() {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.check_circle_outline_rounded,
            value: '${_result.correctCount}/${_result.total}',
            label: 'Correct',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: Icons.local_fire_department_rounded,
            value: '${_result.bestCombo}',
            label: 'Best streak',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: Icons.bolt_rounded,
            value: '+${_result.xpEarned}',
            label: 'XP earned',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: Icons.monetization_on_rounded,
            value: '+${_result.coinsEarned}',
            label: 'Coins',
          ),
        ),
      ],
    );
  }

  Widget _buildSecondaryActions() {
    final hasReview = _result.reviewPairs.isNotEmpty;
    return Row(
      children: [
        if (hasReview)
          Expanded(
            child: _GhostButton(
              icon: Icons.fact_check_outlined,
              label: 'Review answers',
              onTap: () {
                QuizSfx.tap();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => QuizReviewScreen(result: _result),
                  ),
                );
              },
            ),
          ),
        if (hasReview) const SizedBox(width: 10),
        Expanded(
          child: _GhostButton(
            icon: Icons.ios_share_rounded,
            label: _sharing ? 'Preparing…' : 'Share',
            onTap: _sharing ? null : _share,
          ),
        ),
      ],
    );
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    QuizSfx.tap();
    final name = Supabase.instance.client.auth.currentUser?.userMetadata?[
        'full_name'] as String?;
    final ok = await QuizShareCard.share(context, _result, playerName: name);
    if (!mounted) return;
    setState(() => _sharing = false);
    if (!ok) {
      // Image capture can fail on odd devices — never leave the button dead.
      await Share.share(
        'I scored ${_result.points} points in the Advent Connect ZW '
        'Bible Quiz!\n\n$appDownloadUrl',
      );
    }
  }

  Widget _buildBanner({
    required IconData icon,
    required String label,
    required String detail,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.maybe(context, AppMotion.entrance),
      curve: AppMotion.spring,
      builder: (context, t, child) => Transform.scale(
        scale: 0.86 + 0.14 * t,
        child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
      ),
      child: ArenaPanel(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        borderColor: ArenaTheme.gold.withValues(alpha: 0.5),
        glow: ArenaTheme.gold,
        child: Row(
          children: [
            Icon(icon, color: ArenaTheme.gold, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.labelMedium.copyWith(
                      color: ArenaTheme.goldBright,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: ArenaTheme.textMutedOnNavy),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildXp() {
    return ArenaPanel(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 17),
      borderColor: _result.leveledUp
          ? ArenaTheme.gold.withValues(alpha: 0.5)
          : null,
      glow: _result.leveledUp ? ArenaTheme.gold : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_result.leveledUp) ...[
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded,
                    color: ArenaTheme.gold, size: 18),
                const SizedBox(width: 8),
                Text(
                  'LEVEL UP! You reached level ${_result.newLevel}',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: ArenaTheme.goldBright,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          XpBar(xp: QuizProgressService.totalXp(), fromXp: _xpBefore),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 16),
      child: Column(
        children: [
          // Held back until the celebration finishes so nobody taps
          // straight past the moment they just earned.
          AnimatedOpacity(
            opacity: _celebrationDone ? 1 : 0.35,
            duration: AppMotion.maybe(context, AppMotion.standard),
            child: ArenaButton(
              label: 'Play again',
              icon: Icons.replay_rounded,
              gold: true,
              // Popping with the mode tells the lobby to start another
              // round of the same thing immediately, rather than dumping
              // the player back on the menu to find it again.
              onTap: _celebrationDone
                  ? () => Navigator.of(context).pop(_result.mode)
                  : null,
            ),
          ),
          const SizedBox(height: 10),
          _buildSecondaryActions(),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Back to the lobby',
              style: AppTextStyles.labelMedium
                  .copyWith(color: ArenaTheme.textMutedOnNavy),
            ),
          ),
        ],
      ),
    );
  }
}

/// Secondary action — outlined glass, so it never competes with the gold
/// "Play again" button.
class _GhostButton extends StatelessWidget {
  const _GhostButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ArenaTheme.glass,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ArenaTheme.glassBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: ArenaTheme.textOnNavy),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelMedium.copyWith(
                      color: ArenaTheme.textOnNavy,
                      fontWeight: FontWeight.w700,
                    ),
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

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
      decoration: BoxDecoration(
        color: ArenaTheme.glass,
        borderRadius: ArenaTheme.tileRadius,
        border: Border.all(color: ArenaTheme.glassBorder),
      ),
      child: Column(
        children: [
          Icon(icon, size: 19, color: ArenaTheme.gold),
          const SizedBox(height: 7),
          FittedBox(
            child: Text(
              value,
              style: AppTextStyles.titleMedium.copyWith(
                color: ArenaTheme.textOnNavy,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: AppTextStyles.labelSmall.copyWith(
              color: ArenaTheme.textFaintOnNavy,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}
