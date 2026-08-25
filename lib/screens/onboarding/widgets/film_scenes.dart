import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';

/// Scene compositions for the onboarding film.
///
/// Everything in here is driven by ONE master timeline value `t` (0 → 1
/// over the whole film) passed down from OnboardingScreen — no widget
/// owns its own controller, so all elements stay choreographed against
/// shared timing and the film can be scrubbed / fast-forwarded freely.
///
/// Layout note: scenes are composed inside a fixed "stage" box; all
/// motion is Transform/Opacity on small subtrees + tiny CustomPaints, so
/// there are no layout passes per frame and no blur filters — the whole
/// film is compositor-friendly for mid-range Android.

// ---------------------------------------------------------------------------
// Timeline helpers
// ---------------------------------------------------------------------------

/// Maps master time [t] onto a local 0→1 progress within [a]..[b].
double seg(double t, double a, double b, [Curve curve = Curves.linear]) {
  if (b <= a) return t >= b ? 1 : 0;
  return curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));
}

/// 0→1→0 pulse inside [a]..[b] — for elements that appear then leave.
double pulse(double t, double a, double b) {
  final p = seg(t, a, b);
  return math.sin(p * math.pi);
}

/// Scene windows on the master timeline. Entrances overlap the previous
/// scene's exit so nothing ever hard-cuts.
class FilmTimeline {
  FilmTimeline._();

  // Eleven scenes. It was seven, then ten, and the app kept growing past
  // its own pitch: the offline Library, the feed and the Quiz Arena were
  // added in Aug 2026, and voice/video calling and Advent AI shipped after
  // that (founder, 25 Aug 2026). A member arriving at sign-up had no idea
  // either existed. Calls ride along with chat — they are the same
  // conversation, one of them just out loud — and Advent AI takes the last
  // slot before the finale, which is the one people remember.
  //
  // **Every window keeps the LENGTH it had.** Room for the new scene comes
  // out of the GAPS between starts, not out of any scene's duration —
  // because each scene's internal beats are written as absolute `a + 0.0x`
  // offsets tuned against its own length, and shortening a window would
  // silently push its last beat past its own exit. Overlap grew from
  // ~0.017 to ~0.025, which is if anything cleaner: an outgoing scene now
  // begins its exit exactly as the next one begins its entrance.
  static const s0 = (0.000, 0.088); // brand open
  static const s1 = (0.070, 0.185); // churches
  static const s2 = (0.158, 0.274); // prayer
  static const s3 = (0.248, 0.353); // chat + calls
  static const s4 = (0.330, 0.446); // marketplace + jobs
  static const s5 = (0.420, 0.536); // watch (video + live)
  static const s6 = (0.510, 0.636); // library — offline scripture
  static const s7 = (0.608, 0.714); // home feed + stories
  static const s8 = (0.690, 0.786); // quiz arena
  static const s9 = (0.770, 0.870); // advent ai
  static const s10 = (0.860, 1.000); // sabbath finale + CTA

  /// Tap-to-advance targets. The film still scrubs THROUGH the frames in
  /// between rather than cutting, so tapping never breaks continuity.
  static const boundaries = <double>[
    0.088,
    0.185,
    0.274,
    0.353,
    0.446,
    0.536,
    0.636,
    0.714,
    0.786,
    0.870,
    1.0,
  ];

  /// Which progress segment (0..4) the value falls in — for the top bars.
  static int sceneIndex(double t) {
    for (var i = 0; i < boundaries.length; i++) {
      if (t < boundaries[i]) return i;
    }
    return boundaries.length - 1;
  }
}

// ---------------------------------------------------------------------------
// Ambient background — always moving, whisper-subtle
// ---------------------------------------------------------------------------

/// Slow drifting light + a few ghost UI fragments at different depths.
/// Driven by its own repeating loop value [loop] plus the film value for
/// parallax, painted in one layer with zero blur filters.
class AmbientPainter extends CustomPainter {
  AmbientPainter({
    required this.loop,
    required this.film,
    required this.dark,
  });

  final double loop; // 0→1 repeating (~14s)
  final double film; // master film position, for parallax drift

  /// Whether the surface underneath is the dark palette.
  ///
  /// Required, not defaulted: this painter backs SIX screens (onboarding,
  /// auth shell, the auth flow, splash, maintenance, the create sheet) and
  /// a default would have let some of them keep the light-mode field
  /// silently. Let the compiler ask every caller.
  final bool dark;

  /// Light has to EMIT on a dark ground. The brand blue at alpha 0.07
  /// reads as a soft wash over #F5F7FA and is simply *not there* over
  /// #0B1124 — which is how the ambient field, the thing that keeps the
  /// film breathing, collapsed into a flat dead slab in dark mode. Lift
  /// the hue toward white and roughly double the alpha so it still glows.
  Color _lift(Color c) => dark ? Color.lerp(c, Colors.white, 0.42)! : c;
  double _a(double alpha) => dark ? alpha * 2.1 : alpha;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final a = loop * 2 * math.pi;

    void blob(Offset c, double r, Color color, double alpha) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    // Two blue lights + one gold, orbiting slow ellipses. The film value
    // pans them gently left so the light itself travels with the story.
    final pan = film * w * 0.25;
    blob(
      Offset(w * 0.82 - pan + math.cos(a) * 30, h * 0.16 + math.sin(a) * 22),
      w * 0.55,
      _lift(AppColors.primaryBlue),
      _a(0.07),
    );
    blob(
      Offset(w * 0.05 - pan * 0.6 + math.sin(a * 0.8) * 26, h * 0.62),
      w * 0.48,
      _lift(AppColors.primaryBlue),
      _a(0.05),
    );
    blob(
      Offset(w * 0.55 - pan * 0.8, h * 0.88 + math.cos(a * 0.7) * 18),
      w * 0.42,
      _lift(AppColors.goldAccent),
      _a(0.06),
    );

    // Ghost UI fragments — faint rounded rects floating at 3 depths.
    final ghost = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    const depths = [0.35, 0.6, 1.0];
    for (var i = 0; i < 6; i++) {
      final d = depths[i % 3];
      final phase = a * (0.5 + d * 0.5) + i * 1.1;
      final x =
          w * (0.12 + (i * 0.15) % 0.8) - pan * d + math.sin(phase) * 10 * d;
      final y = h * (0.10 + (i * 0.23) % 0.85) + math.cos(phase) * 14 * d;
      ghost.color = _lift(
        AppColors.primaryBlue,
      ).withValues(alpha: _a(0.05 + 0.03 * d));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x, y),
            width: 46 * d + 22,
            height: 30 * d + 12,
          ),
          const Radius.circular(9),
        ),
        ghost,
      );
    }

    // A sparse gold dust field, drifting upward forever.
    final dust = Paint();
    for (var i = 0; i < 10; i++) {
      final d = depths[i % 3];
      final x = w * ((i * 0.37 + 0.08) % 1.0) + math.sin(a + i) * 8 * d;
      final y = h * ((i * 0.61 + loop * (0.10 + 0.12 * d)) % 1.0);
      dust.color = _lift(
        i.isEven ? AppColors.goldAccent : AppColors.primaryBlue,
      ).withValues(alpha: _a(0.10 + 0.08 * d).clamp(0.0, 1.0));
      canvas.drawCircle(Offset(x, y), 1.2 + 1.6 * d, dust);
    }
  }

  @override
  bool shouldRepaint(AmbientPainter old) =>
      // `dark` belongs here: without it a live theme switch keeps the old
      // field painted until some other value happens to change.
      old.loop != loop || old.film != film || old.dark != dark;
}

// ---------------------------------------------------------------------------
// Shared mini-UI pieces (fake data, pure visuals)
// ---------------------------------------------------------------------------

/// Pick a value per brightness.
///
/// Used where a colour has no clean [AppPalette] token — mostly fills that
/// sit ON a card and so cannot simply reuse `palette.card`. Light-mode
/// values are passed through untouched, keeping the pre-dark-mode look
/// byte-for-byte identical, which is the same contract AppPalette follows.
T byBrightness<T>(BuildContext context, {required T light, required T dark}) =>
    Theme.of(context).brightness == Brightness.dark ? dark : light;

/// A knocked-back "ink" tone for the placeholder bars, hairlines and
/// dots the film draws ON a card.
///
/// Navy at 10–30% alpha is the light-mode look and is simply absent on a
/// dark card, which is why every mock row and text bar in the film went
/// blank in dark mode. Dark mode uses white at a slightly higher alpha to
/// land at the same perceived weight.
Color ink(BuildContext context, double alpha) => byBrightness(
  context,
  light: AppColors.darkNavy.withValues(alpha: alpha),
  dark: Colors.white.withValues(alpha: (alpha * 1.5).clamp(0.0, 1.0)),
);

/// Brand blue, made legible as TEXT on whichever ground is behind it.
///
/// #1565C0 on the dark scaffold #0B1124 measures about 2.9:1 — under the
/// 4.5:1 floor and visibly murky. Identity is the hue, not the exact
/// value, so lift it in dark mode rather than abandoning the blue.
Color blueText(BuildContext context) => byBrightness(
  context,
  light: AppColors.primaryBlue,
  dark: const Color(0xFF6FA8F5),
);

/// The "app surface" used by every miniature demo card in the film.
///
/// This was a hardcoded white slab with a navy shadow. In dark mode that
/// is a glaring white rectangle on a near-black ground, which is most of
/// what "the onboarding is not premium in dark mode" meant — the film
/// showed off an app that looked nothing like the one behind it.
class _MiniSurface extends StatelessWidget {
  const _MiniSurface({required this.child, this.width = 280, this.padding});
  final Widget child;
  final double width;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          // A dark card on a dark ground needs its edge drawn by a LIGHT
          // hairline; the light-mode navy border is invisible there and
          // the card loses its shape.
          color: dark
              ? Colors.white.withValues(alpha: 0.09)
              : AppColors.darkNavy.withValues(alpha: 0.05),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            // Shadows do not read on dark backgrounds — they need to be
            // deeper and closer to black to separate the card at all.
            color: dark
                ? Colors.black.withValues(alpha: 0.44)
                : AppColors.darkNavy.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Grey placeholder text bar whose width "types itself in".
class _TextBar extends StatelessWidget {
  const _TextBar({required this.grow, required this.width, this.height = 9});
  final double grow; // 0→1
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width * grow,
      height: height,
      decoration: BoxDecoration(
        color: ink(context, 0.10),
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }
}

/// The gold ring — the film's connective tissue. Draws an arc sweep and
/// optionally a small trailing head dot.
class GoldRingPainter extends CustomPainter {
  GoldRingPainter({
    required this.sweep,
    this.strokeWidth = 3,
    this.headDot = true,
  });
  final double sweep; // 0→1 of full circle
  final double strokeWidth;
  final bool headDot;

  @override
  void paint(Canvas canvas, Size size) {
    if (sweep <= 0) return;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - strokeWidth;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep * 2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = AppColors.goldAccent,
    );
    if (headDot && sweep < 1) {
      final angle = -math.pi / 2 + sweep * 2 * math.pi;
      canvas.drawCircle(
        Offset(
          center.dx + radius * math.cos(angle),
          center.dy + radius * math.sin(angle),
        ),
        strokeWidth * 1.1,
        Paint()..color = AppColors.goldAccent,
      );
    }
  }

  @override
  bool shouldRepaint(GoldRingPainter old) =>
      old.sweep != sweep || old.strokeWidth != strokeWidth;
}

/// One choreographed caption line: rises + fades in, then rises + fades
/// out — timing owned by the scene via [enter]/[exit].
class SceneLine extends StatelessWidget {
  const SceneLine({
    super.key,
    required this.text,
    required this.enter,
    required this.exit,
    this.emphasis = false,
  });

  final String text;
  final double enter; // 0→1
  final double exit; // 0→1 (1 = fully gone)
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final opacity = (enter * (1 - exit)).clamp(0.0, 1.0);
    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(0, 18 * (1 - enter) - 12 * exit),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style:
              (emphasis
                      ? AppTextStyles.displayMedium
                      : AppTextStyles.headlineMedium)
                  .copyWith(
                    // Was AppColors.darkNavy — navy caption text on the
                    // dark scaffold, i.e. "Ready for Sabbath." was
                    // invisible in dark mode (founder, 17 Aug). Every
                    // caption in the film went through this one line.
                    color: context.palette.text,
                    fontWeight: emphasis ? FontWeight.w800 : FontWeight.w700,
                    height: 1.2,
                    letterSpacing: -0.2,
                  ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scene 0 — brand open
// ---------------------------------------------------------------------------

class SceneBrandOpen extends StatelessWidget {
  const SceneBrandOpen({super.key, required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    final (a, b) = FilmTimeline.s0;
    final logoIn = seg(t, a, a + 0.04, Curves.easeOutCubic);
    final ringSweep = seg(t, a + 0.03, a + 0.082, Curves.easeInOutCubic);
    final lineIn = seg(t, a + 0.055, a + 0.095, Curves.easeOutCubic);
    final exit = seg(t, b - 0.022, b, Curves.easeInCubic);

    // On exit the whole composition glides up and shrinks; the ring
    // "detaches" (fades) exactly as the church card's gold tick pops in
    // Scene 1 — the ring becomes the tick.
    return Opacity(
      opacity: (logoIn * (1 - exit)).clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, 24 * (1 - logoIn) - 90 * exit),
        child: Transform.scale(
          scale: (0.9 + 0.1 * logoIn) * (1 - 0.35 * exit),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 150,
                height: 150,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(150, 150),
                      painter: GoldRingPainter(sweep: ringSweep),
                    ),
                    Container(
                      width: 104,
                      height: 104,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryBlue.withValues(
                              alpha: 0.30,
                            ),
                            blurRadius: 26,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(14),
                      child: Image.asset(
                        'assets/icon/logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              SceneLine(
                // The opening line, so it is the first thing a new member
                // reads. Says the promise outright rather than implying it
                // — and matches the splash ("Connecting Adventists all over
                // the world"), so the first two screens tell one story.
                text: 'Connect with Adventists\nall over the world.',
                enter: lineIn,
                exit: exit,
                emphasis: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scene 1 — find your church
// ---------------------------------------------------------------------------

class SceneChurch extends StatelessWidget {
  const SceneChurch({super.key, required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    final (a, b) = FilmTimeline.s1;
    final cardIn = seg(t, a, a + 0.05, Curves.easeOutBack);
    final barsIn = seg(t, a + 0.025, a + 0.075, Curves.easeOutCubic);
    final pinDrop = seg(t, a + 0.05, a + 0.085, Curves.bounceOut);
    final tickPop = seg(t, a + 0.04, a + 0.065, Curves.easeOutBack);
    final followFill = seg(t, a + 0.08, a + 0.115, Curves.easeInOutCubic);
    final countT = seg(t, a + 0.08, a + 0.14);
    final lineIn = seg(t, a + 0.05, a + 0.10, Curves.easeOutCubic);
    final exit = seg(t, b - 0.025, b, Curves.easeInCubic);

    final followers = 1240 + (countT * 8).floor();

    if (cardIn == 0) return const SizedBox.shrink();

    return Opacity(
      opacity: (cardIn * (1 - exit)).clamp(0.0, 1.0),
      child: Transform.translate(
        // Enters rising from below; exits drifting up-left — into the
        // "feed" that Scene 2 continues.
        offset: Offset(-70 * exit, 70 * (1 - cardIn) - 60 * exit),
        child: Transform.scale(
          scale: (0.94 + 0.06 * cardIn) * (1 - 0.16 * exit),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MiniSurface(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // "Photo" block with the dropping map pin.
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              gradient: AppColors.appBarGradient,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.church,
                                color: AppColors.white,
                                size: 26,
                              ),
                            ),
                          ),
                          Positioned(
                            top: -14 + (1 - pinDrop) * -26,
                            right: -8,
                            child: Opacity(
                              opacity: pinDrop.clamp(0.0, 1.0),
                              child: const Icon(
                                Icons.location_on,
                                color: AppColors.red,
                                size: 22,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _TextBar(grow: barsIn, width: 110, height: 11),
                              const SizedBox(width: 6),
                              Transform.scale(
                                scale: tickPop,
                                child: const Icon(
                                  Icons.verified,
                                  color: AppColors.goldAccent,
                                  size: 16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          _TextBar(grow: barsIn, width: 76, height: 8),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(
                                Icons.people_outline,
                                size: 14,
                                color: AppColors.primaryBlue.withValues(
                                  alpha: 0.9,
                                ),
                              ),
                              const SizedBox(width: 4),
                              // Flexible: the count grows while the scene
                              // plays and the Follow pill's label widens
                              // from "Follow" to "Following", so this row
                              // outgrew its Expanded mid-shot and painted
                              // overflow stripes across the card. Caught
                              // by test/onboarding_film_test.dart.
                              Flexible(
                                child: Text(
                                  '$followers members',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: AppColors.primaryBlue,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Follow pill fills brand blue.
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Color.lerp(
                                    AppColors.primaryBlue.withValues(
                                      alpha: 0.10,
                                    ),
                                    AppColors.primaryBlue,
                                    followFill,
                                  ),
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                child: Text(
                                  followFill > 0.5 ? 'Following' : 'Follow',
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: Color.lerp(
                                      AppColors.primaryBlue,
                                      AppColors.white,
                                      followFill,
                                    ),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 34),
              SceneLine(
                // Was "2,600+ congregations" — the Zimbabwe-only row count,
                // and the one line in this reel that told a member in
                // Nairobi the app was not for them.
                //
                // "wherever you worship" replaced it and was still wrong,
                // just less obviously: outside Zimbabwe the directory is
                // EMPTY, so it promised a search that returns nothing at
                // the exact moment a new member is deciding whether this
                // app is real. Same mistake as the old "you can follow
                // other churches anytime" line.
                //
                // "or put it on the map" is true in both worlds — find
                // yours among the 2,600, or add it — and it primes the
                // member for the "Add my church" button that the picker's
                // empty state now offers them.
                text: 'Find your church —\nor put it on the map.',
                enter: lineIn,
                exit: exit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scene 2 — prayer wall
// ---------------------------------------------------------------------------

class ScenePrayer extends StatelessWidget {
  const ScenePrayer({super.key, required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    final (a, b) = FilmTimeline.s2;
    final cardIn = seg(t, a, a + 0.05, Curves.easeOutBack);
    final barsIn = seg(t, a + 0.03, a + 0.09, Curves.easeOutCubic);
    final countT = seg(t, a + 0.05, a + 0.13);
    // Linear 0→1 flight progress for each "+1" chip; opacity is a sine
    // of the progress so they rise steadily while fading in-then-out.
    final chip1 = seg(t, a + 0.055, a + 0.095);
    final chip2 = seg(t, a + 0.09, a + 0.13);
    final lineIn = seg(t, a + 0.05, a + 0.10, Curves.easeOutCubic);
    final exit = seg(t, b - 0.025, b, Curves.easeInCubic);

    final praying = 3 + (countT * 24).floor();
    // Heart beats gently as the count climbs.
    final beat =
        1 +
        0.10 *
            pulse(t, a + 0.05, a + 0.13) *
            (0.5 + 0.5 * math.sin(countT * math.pi * 6));

    if (cardIn == 0) return const SizedBox.shrink();

    return Opacity(
      opacity: (cardIn * (1 - exit)).clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(70 * (1 - cardIn) - 70 * exit, -60 * exit),
        child: Transform.scale(
          scale: (0.94 + 0.06 * cardIn) * (1 - 0.16 * exit),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 300,
                height: 128,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    // Second card peeking behind — the wall, not a lone card.
                    Positioned(
                      top: 16,
                      child: Transform.scale(
                        scale: 0.92,
                        child: Opacity(
                          opacity: 0.45,
                          child: _MiniSurface(
                            width: 280,
                            child: const SizedBox(height: 64),
                          ),
                        ),
                      ),
                    ),
                    _MiniSurface(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Transform.scale(
                            scale: beat,
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.primaryBlue.withValues(
                                  alpha: 0.10,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.volunteer_activism,
                                color: AppColors.primaryBlue,
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _TextBar(grow: barsIn, width: 130, height: 10),
                                const SizedBox(height: 7),
                                _TextBar(grow: barsIn, width: 170, height: 8),
                                const SizedBox(height: 6),
                                _TextBar(grow: barsIn, width: 96, height: 8),
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryBlue.withValues(
                                      alpha: 0.08,
                                    ),
                                    borderRadius: BorderRadius.circular(100),
                                  ),
                                  child: Text(
                                    '🙏  $praying praying',
                                    style: AppTextStyles.labelSmall.copyWith(
                                      color: AppColors.primaryBlue,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // "+1" chips float up off the pill and fade.
                    for (final (chip, dx) in [(chip1, 40.0), (chip2, 78.0)])
                      if (chip > 0 && chip < 1)
                        Positioned(
                          bottom: 6 + chip * 52,
                          left: dx,
                          child: Opacity(
                            opacity: math.sin(chip * math.pi),
                            child: Text(
                              '+1',
                              style: AppTextStyles.labelMedium.copyWith(
                                color: AppColors.goldAccent,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: 34),
              SceneLine(
                text: 'Carry each other\nin prayer.',
                enter: lineIn,
                exit: exit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scene 3 — chat + marketplace
// ---------------------------------------------------------------------------

class SceneChatMarket extends StatelessWidget {
  const SceneChatMarket({super.key, required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    final (a, b) = FilmTimeline.s3;
    final stageIn = seg(t, a, a + 0.030, Curves.easeOutCubic);
    final typing = pulse(
      t,
      a + 0.006,
      a + 0.042,
    ); // typing bubble lives then goes
    final bubble1 = seg(t, a + 0.034, a + 0.054, Curves.easeOutBack);
    final ticksBlue = seg(t, a + 0.064, a + 0.076);
    final bubble2 = seg(t, a + 0.050, a + 0.070, Curves.easeOutBack);
    // The call beat (founder, 25 Aug 2026). The conversation does not cut
    // to a second scene — the thread slides up and the call rises out from
    // under it, because chatting and calling ARE the same thread in the
    // app. Whole thing lives inside the window this scene already had.
    final callIn = seg(t, a + 0.068, a + 0.090, Curves.easeOutBack);
    final connected = seg(t, a + 0.086, a + 0.100, Curves.easeOutCubic);
    final lineIn = seg(t, a + 0.030, a + 0.062, Curves.easeOutCubic);
    final exit = seg(t, b - 0.025, b, Curves.easeInCubic);

    if (stageIn == 0) return const SizedBox.shrink();

    final dotPhase = (t - a) * 220; // fast local clock for the dots

    return Opacity(
      opacity: (stageIn * (1 - exit)).clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, 40 * (1 - stageIn) - 60 * exit),
        child: Transform.scale(
          scale: 1 - 0.16 * exit,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 300,
                // Width is fixed; HEIGHT is not. A hard 104 was a guess
                // at how tall two bubbles come out, and it is wrong the
                // moment a bubble wraps to a second line — which depends
                // on the font actually resolved and on the system text
                // scale, neither of which this file controls. Letting the
                // column size itself removes the guess entirely.
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Incoming: typing dots morph into the message bubble.
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        height: 44,
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            if (typing > 0 && bubble1 < 0.5)
                              Opacity(
                                opacity: typing.clamp(0.0, 1.0),
                                child: _ChatBubble(
                                  // Received bubble: it sits ON the mini
                                  // surface, so it needs its own fill that
                                  // separates from the card in both modes.
                                  color: byBrightness(
                                    context,
                                    light: AppColors.white,
                                    dark: context.palette.cardMuted,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (var i = 0; i < 3; i++)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 2.5,
                                          ),
                                          child: Transform.translate(
                                            offset: Offset(
                                              0,
                                              -3 *
                                                  math
                                                      .sin(
                                                        (dotPhase - i * 0.9)
                                                            .clamp(0, 100),
                                                      )
                                                      .abs(),
                                            ),
                                            child: Container(
                                              width: 7,
                                              height: 7,
                                              decoration: BoxDecoration(
                                                color: byBrightness(
                                                  context,
                                                  light: AppColors.darkNavy
                                                      .withValues(alpha: 0.35),
                                                  dark: Colors.white.withValues(
                                                    alpha: 0.45,
                                                  ),
                                                ),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            if (bubble1 > 0)
                              Transform.scale(
                                scale: bubble1,
                                alignment: Alignment.bottomLeft,
                                child: _ChatBubble(
                                  color: byBrightness(
                                    context,
                                    light: AppColors.white,
                                    dark: context.palette.cardMuted,
                                  ),
                                  child: Text(
                                    'Happy Sabbath! 🙏',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: context.palette.text,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Reply with ticks that turn read-blue.
                    Align(
                      alignment: Alignment.centerRight,
                      child: Transform.scale(
                        scale: bubble2,
                        alignment: Alignment.bottomRight,
                        child: _ChatBubble(
                          color: AppColors.primaryBlue,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Flexible: _ChatBubble puts no bound on its
                              // own width, so this Row could exceed the
                              // 300px stage and paint overflow stripes —
                              // which it did, by 18px, at the end of the
                              // scene. Text metrics vary with the font
                              // actually resolved on the device, so the
                              // bubble must be able to shrink rather than
                              // rely on the string measuring small enough.
                              Flexible(
                                child: Text(
                                  'Happy Sabbath, family!',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.done_all_rounded,
                                size: 14,
                                color: Color.lerp(
                                  AppColors.white.withValues(alpha: 0.6),
                                  const Color(0xFF9BE1FF),
                                  ticksBlue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // The call, rising out from under the thread. Sized
                    // by an AnimatedSize-free trick: the SizedBox is only
                    // as tall as the pill's own progress, so the column
                    // above it lifts smoothly instead of jumping.
                    if (callIn > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Opacity(
                          opacity: callIn.clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: Offset(0, 22 * (1 - callIn.clamp(0.0, 1.0))),
                            child: _CallPill(
                              phase: (t - a) * 190,
                              connected: connected,
                              ring: callIn,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              SceneLine(
                // Was "Chat freely with / your church family." Calling
                // shipped after that line was written, and the film is
                // the only place a new member is told what is in here.
                text: 'Chat and call\nyour church family.',
                enter: lineIn,
                exit: exit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The live-call pill: avatar with radar rings, name + timer, a waveform
/// that actually moves, and the call glyph.
///
/// Everything is Transform + Container on a handful of boxes — no blur, no
/// per-frame layout — so it costs the film nothing on a budget Android.
class _CallPill extends StatelessWidget {
  const _CallPill({
    required this.phase,
    required this.connected,
    required this.ring,
  });

  /// Fast local clock for the waveform and the radar rings.
  final double phase;

  /// 0 → 1 as the call connects: the waveform grows out of a flat line
  /// and the timer fades up.
  final double connected;

  /// The pill's own entrance, reused to size the radar rings so they
  /// bloom outward as it arrives.
  final double ring;

  @override
  Widget build(BuildContext context) {
    final pulseA = (math.sin(phase * 0.9) * 0.5 + 0.5);
    final pulseB = (math.sin(phase * 0.9 - 1.1) * 0.5 + 0.5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: byBrightness(
          context,
          light: AppColors.white,
          dark: context.palette.cardMuted,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: byBrightness(
              context,
              light: AppColors.darkNavy.withValues(alpha: 0.10),
              dark: Colors.black.withValues(alpha: 0.40),
            ),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar + two radar rings expanding out of it. Blue, not the
          // usual green "answer" circle: green is a status colour in this
          // app and this is not a status, it is a live call.
          SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                for (final p in [pulseA, pulseB])
                  Container(
                    width: 26 + 16 * p * ring,
                    height: 26 + 16 * p * ring,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primaryBlue.withValues(
                          alpha: 0.30 * (1 - p) * ring,
                        ),
                        width: 1.4,
                      ),
                    ),
                  ),
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.primaryGradient,
                  ),
                  child: Text(
                    'R',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      height: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Flexible, because the name and the timer are the only parts
          // of this pill whose width depends on the font the device
          // actually resolved — everything else is a fixed box. Without
          // it the row can exceed the 300px stage and paint overflow
          // stripes, which is exactly how the chat bubble beside it
          // broke once already.
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ruvimbo',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: context.palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  connected > 0.5 ? 'Voice call · 00:07' : 'Calling…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: context.palette.textMuted,
                    fontSize: 10.5,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // The waveform. Flat while it rings, alive once it connects.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 7; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Container(
                    width: 3,
                    height:
                        3 +
                        15 *
                            connected *
                            math.sin(phase * 0.7 - i * 0.8).abs(),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.primaryGradient,
            ),
            child: const Icon(
              Icons.call_rounded,
              size: 15,
              color: AppColors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.child, required this.color});
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: byBrightness(
              context,
              light: AppColors.darkNavy.withValues(alpha: 0.08),
              dark: Colors.black.withValues(alpha: 0.36),
            ),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Scene 4 — marketplace + jobs
// ---------------------------------------------------------------------------

class SceneMarketJobs extends StatelessWidget {
  const SceneMarketJobs({super.key, required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    final (a, b) = FilmTimeline.s4;
    final productIn = seg(t, a, a + 0.045, Curves.easeOutBack);
    final barsIn = seg(t, a + 0.03, a + 0.08, Curves.easeOutCubic);
    final heartPop = seg(t, a + 0.07, a + 0.095, Curves.easeOutBack);
    final jobIn = seg(t, a + 0.055, a + 0.10, Curves.easeOutBack);
    final salaryPop = seg(t, a + 0.10, a + 0.125, Curves.easeOutBack);
    final lineIn = seg(t, a + 0.04, a + 0.085, Curves.easeOutCubic);
    final exit = seg(t, b - 0.022, b, Curves.easeInCubic);

    if (productIn == 0) return const SizedBox.shrink();

    return Opacity(
      opacity: (productIn * (1 - exit)).clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, 50 * (1 - productIn) - 60 * exit),
        child: Transform.scale(
          scale: (0.94 + 0.06 * productIn) * (1 - 0.16 * exit),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Product card slides in from the right…
              Transform.translate(
                offset: Offset(70 * (1 - productIn), 0),
                child: _MiniSurface(
                  width: 270,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.shopping_bag_outlined,
                          color: AppColors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _TextBar(grow: barsIn, width: 110, height: 10),
                            const SizedBox(height: 7),
                            Text(
                              'USD 15.00',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: AppColors.primaryBlue,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Transform.scale(
                        scale: heartPop,
                        child: const Icon(
                          Icons.favorite,
                          size: 18,
                          color: AppColors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // …and a job card answers from the left.
              if (jobIn > 0)
                Transform.translate(
                  offset: Offset(-70 * (1 - jobIn), 0),
                  child: Opacity(
                    opacity: jobIn.clamp(0.0, 1.0),
                    child: _MiniSurface(
                      width: 270,
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: AppColors.goldAccent.withValues(
                                alpha: 0.16,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.work_outline,
                              color: AppColors.goldAccent,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _TextBar(grow: barsIn, width: 130, height: 10),
                                const SizedBox(height: 7),
                                Transform.scale(
                                  scale: salaryPop,
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryBlue.withValues(
                                        alpha: 0.10,
                                      ),
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                    child: Text(
                                      'HIRING',
                                      style: AppTextStyles.labelSmall.copyWith(
                                        color: AppColors.primaryBlue,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 9.5,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 28),
              SceneLine(
                text: 'Buy, sell & find work\nwithin the family.',
                enter: lineIn,
                exit: exit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scene 5 — watch (sermons, music & live services)
// ---------------------------------------------------------------------------

class SceneWatch extends StatelessWidget {
  const SceneWatch({super.key, required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    final (a, b) = FilmTimeline.s5;
    final cardIn = seg(t, a, a + 0.04, Curves.easeOutBack);
    final playPop = seg(t, a + 0.035, a + 0.06, Curves.easeOutBack);
    final liveIn = seg(t, a + 0.048, a + 0.07, Curves.easeOutBack);
    final playing = seg(t, a + 0.075, a + 0.09); // play btn hands off
    final progressT = seg(t, a + 0.085, a + 0.14, Curves.easeInOutCubic);
    final barsIn = seg(t, a + 0.025, a + 0.07, Curves.easeOutCubic);
    final lineIn = seg(t, a + 0.04, a + 0.08, Curves.easeOutCubic);
    final exit = seg(t, b - 0.025, b, Curves.easeInCubic);

    if (cardIn == 0) return const SizedBox.shrink();

    // LIVE dot blinks on a local clock while the scene is on stage.
    final blink = 0.55 + 0.45 * math.sin((t - a) * 260);

    return Opacity(
      opacity: (cardIn * (1 - exit)).clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, 70 * (1 - cardIn) - 60 * exit),
        child: Transform.scale(
          scale: (0.94 + 0.06 * cardIn) * (1 - 0.16 * exit),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 280,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  // Hand-rolled card rather than _MiniSurface (it clips a
                  // video thumbnail), so it needs the same treatment.
                  color: context.palette.card,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: byBrightness(
                        context,
                        light: AppColors.darkNavy.withValues(alpha: 0.12),
                        dark: Colors.black.withValues(alpha: 0.46),
                      ),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: AppColors.appBarGradient,
                            ),
                            child: SizedBox.expand(),
                          ),
                          // Play button pops in, then recedes as the
                          // "video" starts and the progress bar takes over.
                          Transform.scale(
                            scale: playPop * (1 - 0.35 * playing),
                            child: Opacity(
                              opacity: (playPop * (1 - playing)).clamp(
                                0.0,
                                1.0,
                              ),
                              child: Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: AppColors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.darkNavy.withValues(
                                        alpha: 0.25,
                                      ),
                                      blurRadius: 16,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: AppColors.primaryBlue,
                                  size: 32,
                                ),
                              ),
                            ),
                          ),
                          // LIVE badge — red is reserved for urgent/live.
                          Positioned(
                            top: 10,
                            left: 10,
                            child: Transform.scale(
                              scale: liveIn,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.red,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Opacity(
                                      opacity: blink.clamp(0.0, 1.0),
                                      child: Container(
                                        width: 6,
                                        height: 6,
                                        decoration: const BoxDecoration(
                                          color: AppColors.white,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      'LIVE',
                                      style: AppTextStyles.labelSmall.copyWith(
                                        color: AppColors.white,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Playback progress sweeps along the bottom.
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              height: 4,
                              color: AppColors.white.withValues(alpha: 0.25),
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: progressT,
                                child: Container(color: AppColors.goldAccent),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: const BoxDecoration(
                              gradient: AppColors.primaryGradient,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.church,
                              color: AppColors.white,
                              size: 15,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _TextBar(grow: barsIn, width: 150, height: 9),
                                const SizedBox(height: 6),
                                _TextBar(grow: barsIn, width: 92, height: 7),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              SceneLine(
                text: 'Watch sermons, music\n& live services.',
                enter: lineIn,
                exit: exit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scene 5 — sabbath finale (ring returns, then hands off to the CTA)
// ---------------------------------------------------------------------------

class SceneSabbathFinale extends StatelessWidget {
  const SceneSabbathFinale({super.key, required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    final (a, b) = FilmTimeline.s10;
    final ringIn = seg(t, a, a + 0.04, Curves.easeOutCubic);
    final sweep = seg(t, a + 0.02, a + 0.085, Curves.easeInOutCubic);
    final lineIn = seg(t, a + 0.05, a + 0.095, Curves.easeOutCubic);
    // The ring's send-off: shrinks + sinks toward the CTA button.
    final handoff = seg(t, b - 0.075, b - 0.02, Curves.easeInOutCubic);

    if (ringIn == 0) return const SizedBox.shrink();

    return Opacity(
      opacity: ringIn,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: 1 - handoff,
            child: Transform.translate(
              offset: Offset(0, 30 * (1 - ringIn) + 190 * handoff),
              child: Transform.scale(
                scale: (0.92 + 0.08 * ringIn) * (1 - 0.72 * handoff),
                child: SizedBox(
                  width: 158,
                  height: 158,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(158, 158),
                        painter: GoldRingPainter(sweep: sweep, strokeWidth: 4),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.wb_twilight_rounded,
                            color: AppColors.goldAccent,
                            size: 26,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'SABBATH',
                            style: AppTextStyles.overline.copyWith(
                              // Sits directly on the scaffold inside the
                              // gold ring — navy here vanished in dark mode
                              // exactly like the caption below it.
                              color: context.palette.text,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Fri 5:43 PM',
                            style: AppTextStyles.labelMedium.copyWith(
                              color: blueText(context),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 30 - 12 * handoff),
          SceneLine(
            text: 'Ready for Sabbath.\nReady for you.',
            enter: lineIn,
            exit: 0,
            emphasis: true,
          ),
        ],
      ),
    );
  }
}
