import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../services/secure_storage_service.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import 'widgets/film_scenes.dart';
import 'widgets/film_scenes_library.dart';

/// First-run intro — a continuous, auto-playing motion piece, not
/// slides. (Since 4 Nov 2026 only four of these scenes play, ~15s, with a
/// Skip button, then sign-in opens by itself — see [keptScenes].) One master
/// timeline drives ELEVEN overlapping scenes (brand →
/// churches → prayer → chat + calls → marketplace/jobs → watch → offline
/// Library → feed → quiz → Advent AI → sabbath finale); elements
/// transform into each other instead of page-cutting, an ambient light
/// field keeps even resting moments breathing, and the final scene
/// settles into the sign-up CTA so intro → auth feels like the same film
/// continuing.
///
/// The film is the pitch, so it has to actually cover the product, and
/// the product keeps moving. It was seven scenes and omitted the offline
/// Library, the feed and the quiz; it was then ten and omitted calling
/// and Advent AI, both of which shipped after it was written. Calling
/// lives inside the chat scene — same thread, out loud — and Advent AI
/// has the last slot before the finale. See FilmTimeline.
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

  /// The scenes the short film plays, in order. Everything else on the
  /// master timeline is jumped over (and never built), so the scenes
  /// themselves stay untouched — their internal beats are tuned against
  /// the master timeline, and re-timing them would break them.
  ///
  /// Chosen for what a new member most needs to know: it's for Adventist
  /// churches, you can chat and call, the Bible works offline, and the
  /// finale hands over to sign-up. Prayer, Marketplace, Watch, the feed,
  /// the quiz and Advent AI are all one tap away inside the app.
  static const keptScenes = <(double, double)>[
    FilmTimeline.s0, // brand
    FilmTimeline.s1, // churches
    FilmTimeline.s3, // chat + calls
    FilmTimeline.s6, // offline Bible library
    // No Sabbath finale (owner, 4 Nov 2026: "is that slide necessary …
    // after the slides just go straight to the login screen"). When the
    // last kept scene ends, the film hands over to sign-in by itself.
  ];

  /// The moment the film is over and sign-in opens.
  static double get filmEnd => keptScenes.last.$2;

  /// Where to jump to when [t] has run off the end of a kept scene into
  /// dropped ones, or null to keep playing.
  @visibleForTesting
  static double? jumpTargetFor(double t) {
    for (var i = 0; i < keptScenes.length - 1; i++) {
      final end = keptScenes[i].$2;
      final nextStart = keptScenes[i + 1].$1;
      if (t >= end && t < nextStart) return nextStart;
    }
    return null;
  }


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
    // 46s for eleven scenes ≈ 4.2s each — was 42s for ten, 31s for
    // seven. Holding the per-scene pace matters more than the total:
    // each scene has to finish its move AND let a two-line caption be
    // read. The Advent AI scene in particular types a whole question in
    // and streams an answer back, which is not a beat you can rush.
    //
    // Owner, 4 Nov 2026: "the onboarding slides before sign in … taking
    // long". 46 seconds with no way out is too long for anyone, and
    // unbearable for someone reinstalling. The film now plays only the
    // scenes in [keptScenes] (four, ~15s) at 1.3x the old pace, and a Skip
    // button sits in the corner from the first frame.
    _film = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 35000),
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

  bool _handedOver = false;

  void _onFilmTick() {
    if (!_handedOver && _film.value >= OnboardingScreen.filmEnd) {
      _handedOver = true;
      _film.stop();
      // After this frame — the tick can arrive mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
      return;
    }
    final jump = OnboardingScreen.jumpTargetFor(_film.value);
    if (jump != null) {
      _film.value = jump;
      if (!_holdPaused && !_reducedMotion) _film.forward();
      return;
    }
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
    // Next kept scene's START (a tap skips the rest of this one).
    final next = OnboardingScreen.keptScenes
        .map((w) => w.$1)
        .firstWhere(
          (b) => b > _film.value + 0.005,
          orElse: () => OnboardingScreen.filmEnd,
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
                  dark: Theme.of(context).brightness == Brightness.dark,
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
                    // Still no progress bars (they say "slides"). But Skip
                    // is back (owner, 4 Nov 2026), reversing 29 Jul: an
                    // unlabelled tap-to-advance helped nobody who didn't
                    // know it was there, and someone reinstalling the
                    // app should never have to sit through the pitch.
                    Positioned(
                        top: 4,
                        right: 8,
                        child: TextButton(
                          onPressed: _finish,
                          style: TextButton.styleFrom(
                            foregroundColor: context.palette.textMuted,
                          ),
                          child: Text(
                            'Skip',
                            style: AppTextStyles.labelMedium.copyWith(
                              color: context.palette.textMuted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
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
          // Only the kept scenes are ever built — a dropped scene would
          // otherwise flash in during the overlap before the jump.
          if (live(FilmTimeline.s0)) SceneBrandOpen(t: t),
          if (live(FilmTimeline.s1)) SceneChurch(t: t),
          if (live(FilmTimeline.s3)) SceneChatMarket(t: t),
          if (live(FilmTimeline.s6)) SceneLibrary(t: t),
        ],
      ),
    );
  }
}
