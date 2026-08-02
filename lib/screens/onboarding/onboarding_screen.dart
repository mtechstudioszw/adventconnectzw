import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../services/secure_storage_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/motion/pressable.dart';
import 'widgets/film_scenes.dart';
import 'widgets/film_scenes_library.dart';

/// First-run intro — a continuous, auto-playing motion piece, not
/// slides. One master timeline drives TEN overlapping scenes (brand →
/// churches → prayer → chat → marketplace/jobs → watch → offline
/// Library → feed → quiz → sabbath finale); elements transform into each
/// other instead of page-cutting, an ambient light field keeps even
/// resting moments breathing, and the final scene settles into the
/// sign-up CTA so intro → auth feels like the same film continuing.
///
/// The film is the pitch, so it has to actually cover the product. It
/// was seven scenes and silently omitted the three things most likely to
/// win a member: the offline Library, the feed they'll live in, and the
/// quiz. See FilmTimeline.
///
/// Interaction model (stories-style):
/// * it plays itself — no static frame ever waits for a swipe;
/// * tap = fast-forward to the next scene boundary (the film scrubs
///   through the in-between frames, so continuity is preserved);
/// * press-and-hold = pause, release = resume.
///
/// There is deliberately NO Skip and no progress bar (founder, 29 Jul).
/// Segmented bars are the universal "these are slides" tell, and a Skip
/// in the corner invites people out before the pitch lands. Tap-to-
/// advance covers anyone in a hurry without advertising itself.
///
/// Accessibility: with "remove animations" on, the film parks on its
/// final frame immediately — headline + CTA, fully usable.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const onboardingFlagKey = 'has_seen_onboarding';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  /// The master timeline. Every scene, caption and morph reads from this
  /// one controller (via Interval-style windows in FilmTimeline), so the
  /// whole film is choreographed against shared timing.
  late final AnimationController _film;

  /// Ambient light loop — independent of the film so the background
  /// never stops breathing, even while paused or parked on the CTA.
  late final AnimationController _ambient;

  Timer? _holdTimer;
  bool _holdPaused = false;
  bool _reducedMotion = false;
  int _lastSceneIndex = 0;

  @override
  void initState() {
    super.initState();
    // 42s for ten scenes ≈ 4.2s each — was 31s for seven. Holding the
    // per-scene pace matters more than the total: each scene has to
    // finish its move AND let a two-line caption be read, and the new
    // ones (Library, feed, quiz) carry more detail than the early ones.
    _film = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 42),
    )..addListener(_onFilmTick);
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = !AppMotion.enabled(context);
    if (reduced && !_reducedMotion) {
      _reducedMotion = true;
      _film.value = 1.0;
      _ambient.stop();
    } else if (!_reducedMotion && !_film.isAnimating && _film.value == 0) {
      _film.forward();
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _film.dispose();
    _ambient.dispose();
    super.dispose();
  }

  void _onFilmTick() {
    // A soft tick as each scene hands off to the next.
    final index = FilmTimeline.sceneIndex(_film.value);
    if (index != _lastSceneIndex) {
      _lastSceneIndex = index;
      if (_film.value < 1.0) HapticFeedback.selectionClick();
    }
  }

  // ---- Interaction ---------------------------------------------------------

  void _advanceToNextScene() {
    if (_reducedMotion || _film.value >= 1.0) return;
    HapticFeedback.selectionClick();
    final next = FilmTimeline.boundaries.firstWhere(
      (b) => b > _film.value + 0.005,
      orElse: () => 1.0,
    );
    _film
        .animateTo(
          next,
          duration: const Duration(milliseconds: 550),
          curve: Curves.easeInOutCubic,
        )
        .whenCompleteOrCancel(_resumeIfIdle);
  }

  void _resumeIfIdle() {
    if (mounted &&
        !_holdPaused &&
        !_reducedMotion &&
        !_film.isAnimating &&
        _film.value < 1.0) {
      _film.forward();
    }
  }

  void _onTapDown(TapDownDetails _) {
    if (_reducedMotion) return;
    _holdTimer?.cancel();
    _holdTimer = Timer(const Duration(milliseconds: 180), () {
      _holdPaused = true;
      _film.stop();
    });
  }

  void _onTapUp(TapUpDetails _) {
    final wasQuickTap = _holdTimer?.isActive ?? false;
    _holdTimer?.cancel();
    if (wasQuickTap) {
      _advanceToNextScene();
    } else if (_holdPaused) {
      _holdPaused = false;
      _resumeIfIdle();
    }
  }

  void _onTapCancel() {
    _holdTimer?.cancel();
    if (_holdPaused) {
      _holdPaused = false;
      _resumeIfIdle();
    }
  }

  Future<void> _finish() async {
    HapticFeedback.mediumImpact();
    // Fire-and-forget: the secure-storage write can take a beat on some
    // devices, and awaiting it made "Get started" feel dead before the
    // route transition began. Navigate now; the flag lands in parallel.
    unawaited(
      SecureStorageService.write(OnboardingScreen.onboardingFlagKey, 'true'),
    );
    if (!mounted) return;
    context.goNamed('login');
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Ambient light field — always moving, in its own repaint layer.
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: Listenable.merge([_ambient, _film]),
              builder: (context, _) => CustomPaint(
                painter: AmbientPainter(
                  loop: _ambient.value,
                  film: _film.value,
                ),
              ),
            ),
          ),
          SafeArea(
            child: AnimatedBuilder(
              animation: _film,
              builder: (context, _) {
                final t = _film.value;
                return Stack(
                  children: [
                    // Tap / hold layer + the film's stage.
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: _onTapDown,
                        onTapUp: _onTapUp,
                        onTapCancel: _onTapCancel,
                        child: _buildStage(t),
                      ),
                    ),
                    // No progress bars and no Skip (founder, 29 Jul).
                    // Segmented bars across the top are the universal
                    // signal for "these are slides you page through",
                    // which is the opposite of what this is — one
                    // continuous film. Skip went with them: the piece is
                    // the pitch, and an escape hatch in the corner
                    // invites people to leave before it makes it.
                    // Tap-to-advance still works, unlabelled, so nobody
                    // is actually trapped.
                    _buildCta(t),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// The film's stage: scenes are only mounted while their window (plus
  /// a small margin) is live, and they overlap so exits become entrances.
  Widget _buildStage(double t) {
    bool live((double, double) w) => t > w.$1 - 0.01 && t < w.$2 + 0.03;
    return Padding(
      // Keep the action clear of the CTA zone at the bottom.
      padding: const EdgeInsets.only(bottom: 120),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (live(FilmTimeline.s0)) SceneBrandOpen(t: t),
          if (live(FilmTimeline.s1)) SceneChurch(t: t),
          if (live(FilmTimeline.s2)) ScenePrayer(t: t),
          if (live(FilmTimeline.s3)) SceneChatMarket(t: t),
          if (live(FilmTimeline.s4)) SceneMarketJobs(t: t),
          if (live(FilmTimeline.s5)) SceneWatch(t: t),
          if (live(FilmTimeline.s6)) SceneLibrary(t: t),
          if (live(FilmTimeline.s7)) SceneFeed(t: t),
          if (live(FilmTimeline.s8)) SceneQuiz(t: t),
          if (t > FilmTimeline.s9.$1 - 0.01) SceneSabbathFinale(t: t),
        ],
      ),
    );
  }

  /// The landing: real buttons that rise as the film settles. The gold
  /// ring's handoff (Scene 4) sinks into this button's glow.
  Widget _buildCta(double t) {
    final ctaIn = seg(t, 0.885, 0.965, Curves.easeOutCubic);
    final glow = seg(t, 0.930, 0.985, Curves.easeOutCubic);
    if (ctaIn <= 0) return const SizedBox.shrink();
    return Positioned(
      left: 24,
      right: 24,
      bottom: 24,
      child: IgnorePointer(
        ignoring: ctaIn < 0.6,
        child: Opacity(
          opacity: ctaIn,
          child: Transform.translate(
            offset: Offset(0, 34 * (1 - ctaIn)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PressEffect(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        // Blue lift + the gold bloom the ring dissolves into.
                        BoxShadow(
                          color: AppColors.primaryBlue.withValues(alpha: 0.32),
                          blurRadius: 22,
                          offset: const Offset(0, 12),
                        ),
                        BoxShadow(
                          color: AppColors.goldAccent.withValues(
                            alpha: 0.35 * glow,
                          ),
                          blurRadius: 34,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _finish,
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Get started',
                                style: AppTextStyles.buttonText.copyWith(
                                  color: AppColors.white,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                color: AppColors.white,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _finish,
                  child: Text(
                    'I already have an account',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
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
