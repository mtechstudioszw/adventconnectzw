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

/// First-run intro — a continuous, auto-playing motion piece, not
/// slides. One master timeline drives five overlapping scenes (brand →
/// churches → prayer → chat/marketplace → sabbath finale); elements
/// transform into each other instead of page-cutting, an ambient light
/// field keeps even resting moments breathing, and the final scene
/// settles into the sign-up CTA so intro → auth feels like the same
/// film continuing.
///
/// Interaction model (stories-style):
/// * it plays itself — no static frame ever waits for a swipe;
/// * tap = fast-forward to the next scene boundary (the film scrubs
///   through the in-between frames, so continuity is preserved);
/// * press-and-hold = pause, release = resume;
/// * Skip = glide straight to the end state.
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
    _film = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 28),
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

  void _skipToEnd() {
    HapticFeedback.selectionClick();
    _holdTimer?.cancel();
    _holdPaused = false;
    _film.animateTo(
      1.0,
      duration: AppMotion.maybe(context, const Duration(milliseconds: 700)),
      curve: Curves.easeInOutCubic,
    );
  }

  Future<void> _finish() async {
    HapticFeedback.mediumImpact();
    await SecureStorageService.write(
      OnboardingScreen.onboardingFlagKey,
      'true',
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
                    _buildProgressBars(t),
                    _buildSkip(t),
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
          if (live(FilmTimeline.s4)) SceneWatch(t: t),
          if (t > FilmTimeline.s5.$1 - 0.01) SceneSabbathFinale(t: t),
        ],
      ),
    );
  }

  /// Stories-style progress: five thin bars filling with the timeline,
  /// bowing out as the CTA arrives.
  Widget _buildProgressBars(double t) {
    final fade = 1 - seg(t, 0.86, 0.92);
    if (fade <= 0) return const SizedBox.shrink();
    var prev = 0.0;
    final bars = <Widget>[];
    for (final boundary in FilmTimeline.boundaries) {
      final fill = seg(t, prev, boundary);
      prev = boundary;
      bars.add(
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.darkNavy.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fill,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Positioned(
      top: 14,
      left: 20,
      right: 20,
      child: Opacity(
        opacity: fade,
        child: Row(children: bars),
      ),
    );
  }

  Widget _buildSkip(double t) {
    final fade = 1 - seg(t, 0.78, 0.85);
    if (fade <= 0) return const SizedBox.shrink();
    return Positioned(
      top: 26,
      right: 12,
      child: Opacity(
        opacity: fade,
        child: IgnorePointer(
          ignoring: fade < 0.5,
          child: TextButton(
            onPressed: _skipToEnd,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            child: Text(
              'Skip',
              style: AppTextStyles.labelMedium.copyWith(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
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
