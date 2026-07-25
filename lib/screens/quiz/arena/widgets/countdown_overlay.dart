import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../theme/app_motion.dart';
import '../../../../theme/app_text_styles.dart';
import '../arena_theme.dart';

/// The 3 · 2 · 1 · GO that runs before the first question.
///
/// This is the single detail that sells "you opened a game": the round
/// doesn't just appear, it *starts*. Each beat punches in from 2.4× scale,
/// a ring sweeps around it, and [onBeat] fires so the caller can play the
/// countdown sound and pulse the haptic in sync.
///
/// Honours the OS "remove animations" setting by skipping straight to
/// [onDone] — nobody who asked for less motion wants a forced 2.2s wait.
class CountdownOverlay extends StatefulWidget {
  const CountdownOverlay({
    super.key,
    required this.onDone,
    this.onBeat,
    this.beats = 3,
  });

  final VoidCallback onDone;

  /// Called at the start of each beat. `index` counts 0..beats, where the
  /// final index is the "GO" beat.
  final void Function(int index)? onBeat;
  final int beats;

  @override
  State<CountdownOverlay> createState() => _CountdownOverlayState();
}

class _CountdownOverlayState extends State<CountdownOverlay>
    with SingleTickerProviderStateMixin {
  static const Duration _beat = Duration(milliseconds: 560);

  late final int _steps = widget.beats + 1; // + the GO beat
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _beat * _steps,
  );

  int _lastBeat = -1;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_tick);
    _c.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finish();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!AppMotion.enabled(context)) {
      // Reduced motion: no theatre, just start the round.
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
      return;
    }
    if (!_c.isAnimating && _c.value == 0) _c.forward();
  }

  void _tick() {
    final index = (_c.value * _steps).floor().clamp(0, _steps - 1);
    if (index != _lastBeat) {
      _lastBeat = index;
      widget.onBeat?.call(index);
    }
  }

  void _finish() {
    if (_done) return;
    _done = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _c.removeListener(_tick);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppMotion.enabled(context)) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final raw = _c.value * _steps;
        final index = raw.floor().clamp(0, _steps - 1);
        final local = (raw - index).clamp(0.0, 1.0);
        final isGo = index == _steps - 1;
        final label = isGo ? 'GO' : '${widget.beats - index}';

        // Punch in fast, hold, then release upward.
        final scale = local < 0.32
            ? 2.4 - 1.4 * Curves.easeOutCubic.transform(local / 0.32)
            : 1.0 + 0.16 * Curves.easeInCubic.transform((local - 0.32) / 0.68);
        final opacity = local < 0.14
            ? local / 0.14
            : local > 0.74
                ? (1 - (local - 0.74) / 0.26).clamp(0.0, 1.0)
                : 1.0;

        return IgnorePointer(
          child: Container(
            color: ArenaTheme.canvasBottom.withValues(alpha: 0.55),
            alignment: Alignment.center,
            child: Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                child: SizedBox(
                  width: 190,
                  height: 190,
                  child: CustomPaint(
                    painter: _BeatRingPainter(
                      progress: local,
                      color: isGo ? ArenaTheme.gold : ArenaTheme.textOnNavy,
                    ),
                    child: Center(
                      child: Text(
                        label,
                        style: AppTextStyles.headlineLarge.copyWith(
                          fontSize: isGo ? 54 : 78,
                          height: 1.0,
                          fontWeight: FontWeight.w800,
                          color: isGo
                              ? ArenaTheme.gold
                              : ArenaTheme.textOnNavy,
                          letterSpacing: isGo ? 4 : 0,
                          shadows: [
                            BoxShadow(
                              color: (isGo
                                      ? ArenaTheme.gold
                                      : Colors.black)
                                  .withValues(alpha: 0.45),
                              blurRadius: 26,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BeatRingPainter extends CustomPainter {
  const _BeatRingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 6;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color.withValues(alpha: 0.16),
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * (1 - progress),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 4
        ..color = color.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(covariant _BeatRingPainter old) =>
      old.progress != progress || old.color != color;
}
