import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../theme/app_colors.dart';
import '../../../../theme/app_motion.dart';
import '../arena_theme.dart';

/// The living navy canvas every arena screen sits on.
///
/// Three slow drifting light pools and a field of faint stars. It's the
/// cheapest possible "this screen is alive" signal — no blur filters, no
/// shaders rebuilt per frame:
///
/// * each light pool's radial shader is built ONCE per size (they're drawn
///   at the origin and moved with `canvas.translate`), so a frame costs
///   three `drawCircle`s and a handful of dots;
/// * the whole thing sits behind a [RepaintBoundary], so the drifting
///   never marks the question card dirty;
/// * with the OS "remove animations" setting on, it paints one static
///   frame and stops the controller entirely.
class ArenaBackdrop extends StatefulWidget {
  const ArenaBackdrop({
    super.key,
    this.flash,
    this.flashColor = ArenaTheme.correctOnNavy,
    this.intensity = 1.0,
  });

  /// Drives a full-screen tint when an answer resolves. 0 = none.
  final Animation<double>? flash;
  final Color flashColor;

  /// Scales how visible the light pools are. The round screen dims them a
  /// little so they never compete with the question.
  final double intensity;

  @override
  State<ArenaBackdrop> createState() => _ArenaBackdropState();
}

class _ArenaBackdropState extends State<ArenaBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  @override
  void initState() {
    super.initState();
    // Started in didChangeDependencies — AppMotion.enabled needs context.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.enabled(context)) {
      if (!_drift.isAnimating) _drift.repeat();
    } else {
      _drift.stop();
      _drift.value = 0.18; // a pleasant static arrangement
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flash = widget.flash;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _BackdropPainter(
          drift: _drift,
          flash: flash,
          flashColor: widget.flashColor,
          intensity: widget.intensity,
          repaint: flash == null
              ? _drift
              : Listenable.merge(<Listenable>[_drift, flash]),
        ),
        size: Size.infinite,
      ),
    );
  }
}

/// A light pool: where it sits, how big, what colour, and how it drifts.
class _Orb {
  const _Orb(this.x, this.y, this.radius, this.color, this.dx, this.dy,
      this.phase, this.alpha);

  /// Fractions of the canvas.
  final double x, y, radius, dx, dy;
  final double phase;
  final double alpha;
  final Color color;
}

const List<_Orb> _orbs = [
  _Orb(0.18, 0.16, 0.62, AppColors.primaryBlue, 0.06, 0.04, 0.0, 0.26),
  _Orb(0.86, 0.34, 0.50, Color(0xFF2B7FE0), 0.05, 0.06, 0.42, 0.18),
  _Orb(0.52, 0.92, 0.58, ArenaTheme.gold, 0.04, 0.03, 0.71, 0.10),
];

class _BackdropPainter extends CustomPainter {
  _BackdropPainter({
    required this.drift,
    required this.flash,
    required this.flashColor,
    required this.intensity,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Animation<double> drift;
  final Animation<double>? flash;
  final Color flashColor;
  final double intensity;

  /// Shaders are rebuilt only when the canvas size changes.
  static Size? _shaderSize;
  static final Map<int, Paint> _orbPaints = {};

  /// Stable star field — generated once, never per frame.
  static final List<_Star> _stars = _buildStars();

  static List<_Star> _buildStars() {
    final rng = math.Random(20260725);
    return [
      for (var i = 0; i < 34; i++)
        _Star(
          rng.nextDouble(),
          rng.nextDouble(),
          0.6 + rng.nextDouble() * 1.3,
          rng.nextDouble(),
        ),
    ];
  }

  void _ensurePaints(Size size) {
    if (_shaderSize == size && _orbPaints.length == _orbs.length) return;
    _shaderSize = size;
    _orbPaints.clear();
    final shortest = size.shortestSide;
    for (var i = 0; i < _orbs.length; i++) {
      final orb = _orbs[i];
      final radius = orb.radius * shortest;
      _orbPaints[i] = Paint()
        ..shader = RadialGradient(
          colors: [
            orb.color.withValues(alpha: orb.alpha),
            orb.color.withValues(alpha: 0),
          ],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Base canvas.
    canvas.drawRect(
      rect,
      Paint()..shader = ArenaTheme.canvas.createShader(rect),
    );

    if (size.isEmpty) return;
    _ensurePaints(size);

    final t = drift.value;
    final shortest = size.shortestSide;

    // Drifting light pools.
    canvas.saveLayer(rect, Paint()..blendMode = BlendMode.plus);
    for (var i = 0; i < _orbs.length; i++) {
      final orb = _orbs[i];
      final paint = _orbPaints[i];
      if (paint == null) continue;
      final angle = (t + orb.phase) * 2 * math.pi;
      final cx = (orb.x + math.cos(angle) * orb.dx) * size.width;
      final cy = (orb.y + math.sin(angle * 0.8) * orb.dy) * size.height;
      canvas.save();
      canvas.translate(cx, cy);
      canvas.drawCircle(
        Offset.zero,
        orb.radius * shortest,
        Paint()
          ..shader = paint.shader
          ..color = Colors.white.withValues(alpha: intensity.clamp(0.0, 1.0)),
      );
      canvas.restore();
    }
    canvas.restore();

    // Stars — a slow twinkle keeps the canvas from ever looking frozen.
    final starPaint = Paint()..color = Colors.white;
    for (final star in _stars) {
      final twinkle =
          0.35 + 0.65 * (0.5 + 0.5 * math.sin((t + star.phase) * 2 * math.pi));
      starPaint.color =
          Colors.white.withValues(alpha: 0.22 * twinkle * intensity);
      canvas.drawCircle(
        Offset(star.x * size.width, star.y * size.height),
        star.radius,
        starPaint,
      );
    }

    // Answer flash.
    final flashValue = flash?.value ?? 0;
    if (flashValue > 0) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              flashColor.withValues(alpha: 0.30 * flashValue),
              flashColor.withValues(alpha: 0.04 * flashValue),
              flashColor.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.55, 1.0],
            center: Alignment.center,
            radius: 0.95,
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter old) =>
      old.intensity != intensity || old.flashColor != flashColor;
}

class _Star {
  const _Star(this.x, this.y, this.radius, this.phase);
  final double x, y, radius, phase;
}
