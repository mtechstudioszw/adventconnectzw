import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
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

  static const s0 = (0.000, 0.165); // brand open
  static const s1 = (0.140, 0.380); // churches
  static const s2 = (0.355, 0.590); // prayer
  static const s3 = (0.565, 0.800); // chat + marketplace
  static const s4 = (0.775, 1.000); // sabbath finale + CTA

  /// Tap-to-skip-ahead targets.
  static const boundaries = <double>[0.165, 0.380, 0.590, 0.800, 1.0];

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
  AmbientPainter({required this.loop, required this.film});

  final double loop; // 0→1 repeating (~14s)
  final double film; // master film position, for parallax drift

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
      AppColors.primaryBlue,
      0.07,
    );
    blob(
      Offset(w * 0.05 - pan * 0.6 + math.sin(a * 0.8) * 26, h * 0.62),
      w * 0.48,
      AppColors.primaryBlue,
      0.05,
    );
    blob(
      Offset(w * 0.55 - pan * 0.8, h * 0.88 + math.cos(a * 0.7) * 18),
      w * 0.42,
      AppColors.goldAccent,
      0.06,
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
      ghost.color = AppColors.primaryBlue.withValues(alpha: 0.05 + 0.03 * d);
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
      dust.color = (i.isEven ? AppColors.goldAccent : AppColors.primaryBlue)
          .withValues(alpha: 0.10 + 0.08 * d);
      canvas.drawCircle(Offset(x, y), 1.2 + 1.6 * d, dust);
    }
  }

  @override
  bool shouldRepaint(AmbientPainter old) =>
      old.loop != loop || old.film != film;
}

// ---------------------------------------------------------------------------
// Shared mini-UI pieces (fake data, pure visuals)
// ---------------------------------------------------------------------------

/// Soft white "app surface" used by every miniature demo card.
class _MiniSurface extends StatelessWidget {
  const _MiniSurface({required this.child, this.width = 280, this.padding});
  final Widget child;
  final double width;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.darkNavy.withValues(alpha: 0.05),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkNavy.withValues(alpha: 0.10),
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
  const _TextBar({
    required this.grow,
    required this.width,
    this.height = 9,
    this.color,
  });
  final double grow; // 0→1
  final double width;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width * grow,
      height: height,
      decoration: BoxDecoration(
        color: color ?? AppColors.darkNavy.withValues(alpha: 0.10),
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
                    color: AppColors.darkNavy,
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
    final logoIn = seg(t, a, a + 0.045, Curves.easeOutCubic);
    final ringSweep = seg(t, a + 0.035, a + 0.095, Curves.easeInOutCubic);
    final lineIn = seg(t, a + 0.075, a + 0.125, Curves.easeOutCubic);
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
                text: 'Zimbabwe’s SDA family,\nin your pocket.',
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
    final barsIn = seg(t, a + 0.03, a + 0.09, Curves.easeOutCubic);
    final pinDrop = seg(t, a + 0.06, a + 0.10, Curves.bounceOut);
    final tickPop = seg(t, a + 0.045, a + 0.075, Curves.easeOutBack);
    final followFill = seg(t, a + 0.11, a + 0.15, Curves.easeInOutCubic);
    final countT = seg(t, a + 0.11, a + 0.20);
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
                              Text(
                                '$followers members',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.primaryBlue,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                              const Spacer(),
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
                text: 'Find your church —\n2,600+ congregations.',
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
    final countT = seg(t, a + 0.07, a + 0.19);
    // Linear 0→1 flight progress for each "+1" chip; opacity is a sine
    // of the progress so they rise steadily while fading in-then-out.
    final chip1 = seg(t, a + 0.075, a + 0.135);
    final chip2 = seg(t, a + 0.125, a + 0.185);
    final lineIn = seg(t, a + 0.05, a + 0.10, Curves.easeOutCubic);
    final exit = seg(t, b - 0.025, b, Curves.easeInCubic);

    final praying = 3 + (countT * 24).floor();
    // Heart beats gently as the count climbs.
    final beat =
        1 +
        0.10 *
            pulse(t, a + 0.07, a + 0.19) *
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
    final stageIn = seg(t, a, a + 0.04, Curves.easeOutCubic);
    final typing = pulse(
      t,
      a + 0.01,
      a + 0.075,
    ); // typing bubble lives then goes
    final bubble1 = seg(t, a + 0.065, a + 0.095, Curves.easeOutBack);
    final ticksBlue = seg(t, a + 0.105, a + 0.125);
    final bubble2 = seg(t, a + 0.115, a + 0.145, Curves.easeOutBack);
    final productIn = seg(t, a + 0.145, a + 0.185, Curves.easeOutBack);
    final lineIn = seg(t, a + 0.05, a + 0.10, Curves.easeOutCubic);
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
                height: 150,
                child: Column(
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
                                  color: AppColors.white,
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
                                                color: AppColors.darkNavy
                                                    .withValues(alpha: 0.35),
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
                                  color: AppColors.white,
                                  child: Text(
                                    'Happy Sabbath! 🙏',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.darkNavy,
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
                              Text(
                                'Happy Sabbath, family!',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.white,
                                  fontWeight: FontWeight.w600,
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
                    const SizedBox(height: 12),
                    // Mini product card glides through below the chat.
                    if (productIn > 0)
                      Transform.translate(
                        offset: Offset(120 * (1 - productIn), 0),
                        child: Opacity(
                          opacity: productIn.clamp(0.0, 1.0),
                          child: _MiniSurface(
                            width: 230,
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    gradient: AppColors.primaryGradient,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.shopping_bag_outlined,
                                    color: AppColors.white,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _TextBar(
                                        grow: productIn,
                                        width: 90,
                                        height: 8,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'USD 15.00',
                                        style: AppTextStyles.labelSmall
                                            .copyWith(
                                              color: AppColors.darkNavy,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 11,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.favorite,
                                  size: 16,
                                  color: AppColors.red.withValues(
                                    alpha: seg(productIn, 0.6, 1.0),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              SceneLine(
                text: 'Chat, buy & sell\nwithin the family.',
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
            color: AppColors.darkNavy.withValues(alpha: 0.08),
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
// Scene 4 — sabbath finale (ring returns, then hands off to the CTA)
// ---------------------------------------------------------------------------

class SceneSabbathFinale extends StatelessWidget {
  const SceneSabbathFinale({super.key, required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    final (a, b) = FilmTimeline.s4;
    final ringIn = seg(t, a, a + 0.04, Curves.easeOutCubic);
    final sweep = seg(t, a + 0.02, a + 0.12, Curves.easeInOutCubic);
    final lineIn = seg(t, a + 0.06, a + 0.11, Curves.easeOutCubic);
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
                              color: AppColors.darkNavy,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Fri 5:43 PM',
                            style: AppTextStyles.labelMedium.copyWith(
                              color: AppColors.primaryBlue,
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
