import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// The app's loading mark: a sweeping brand-blue arc with a gold comet
/// head — replaces the stock Material spinner everywhere a branded
/// in-progress state is needed (buttons, refresh, inline loads).
///
/// Pure CustomPaint on one repeating controller: no layers, no shaders,
/// trivially 60fps on entry-level Android.
///
/// Note: this keeps animating under "remove animations" — a progress
/// indicator that freezes reads as a hang, and rotation conveys
/// *status*, not decoration.
class BrandSpinner extends StatefulWidget {
  const BrandSpinner({
    super.key,
    this.size = 28,
    this.color,
    this.strokeWidth,
  });

  final double size;

  /// Arc colour — defaults to brand blue; pass white on blue/navy fills.
  final Color? color;

  final double? strokeWidth;

  @override
  State<BrandSpinner> createState() => _BrandSpinnerState();
}

class _BrandSpinnerState extends State<BrandSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _SpinnerPainter(
            t: _controller.value,
            color: widget.color ?? AppColors.primaryBlue,
            strokeWidth: widget.strokeWidth ?? widget.size / 9,
          ),
        ),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter({
    required this.t,
    required this.color,
    required this.strokeWidth,
  });

  final double t; // 0 → 1, repeating
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // The arc "breathes": its sweep grows and shrinks while the whole
    // thing rotates, like the Material indeterminate ring but calmer.
    final rotation = t * 2 * math.pi;
    final breathe = 0.5 - 0.5 * math.cos(t * 2 * math.pi); // 0→1→0
    final sweep = (0.20 + 0.55 * breathe) * 2 * math.pi;
    final start = rotation - sweep;

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      // Tail fades out so the arc reads as motion, not a static ring.
      ..shader = SweepGradient(
        colors: [color.withValues(alpha: 0.0), color],
        stops: const [0.0, 1.0],
        startAngle: 0,
        endAngle: sweep,
        transform: GradientRotation(start),
      ).createShader(rect);
    canvas.drawArc(rect, start, sweep, false, arcPaint);

    // Gold comet head — the one gold element of any loading state.
    final head = Offset(
      center.dx + radius * math.cos(start + sweep),
      center.dy + radius * math.sin(start + sweep),
    );
    canvas.drawCircle(
      head,
      strokeWidth * 0.72,
      Paint()..color = AppColors.goldAccent,
    );
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) =>
      old.t != t || old.color != color || old.strokeWidth != strokeWidth;
}
