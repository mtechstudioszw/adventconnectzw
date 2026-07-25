import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../../theme/app_motion.dart';
import '../../../../theme/app_text_styles.dart';
import '../arena_theme.dart';

/// Fires particle bursts. Owned by a screen, handed to a [BurstLayer].
///
/// Kept separate from the layer widget so a screen can trigger a burst from
/// anywhere (an answer handler, a level-up) without a GlobalKey dance.
class BurstController extends ChangeNotifier {
  final List<_Burst> _bursts = [];

  /// Hard cap. Mid-range Androids are the primary market — a runaway
  /// particle count is the fastest way to drop frames in this whole design.
  static const int _maxConcurrent = 4;
  static const int _maxParticlesPerBurst = 26;

  bool get hasActive => _bursts.isNotEmpty;

  /// Throw [count] sparks out of [origin] (in the layer's local coords).
  void fire(
    Offset origin, {
    int count = 18,
    Color color = ArenaTheme.gold,
    double speed = 1.0,
  }) {
    if (_bursts.length >= _maxConcurrent) _bursts.removeAt(0);
    final rng = math.Random();
    final n = count.clamp(1, _maxParticlesPerBurst);
    _bursts.add(
      _Burst(
        origin: origin,
        bornAt: null,
        particles: [
          for (var i = 0; i < n; i++)
            _Particle(
              // Bias upward — sparks that fall look like debris, sparks
              // that rise look like celebration.
              angle: -math.pi / 2 +
                  (rng.nextDouble() - 0.5) * math.pi * 1.35,
              speed: (90 + rng.nextDouble() * 190) * speed,
              size: 1.8 + rng.nextDouble() * 2.8,
              life: 0.65 + rng.nextDouble() * 0.5,
              spin: (rng.nextDouble() - 0.5) * 6,
              color: rng.nextDouble() < 0.25
                  ? Colors.white
                  : Color.lerp(color, ArenaTheme.goldBright,
                      rng.nextDouble() * 0.6)!,
            ),
        ],
      ),
    );
    notifyListeners();
  }

  void _prune(Duration now) {
    _bursts.removeWhere((b) {
      final born = b.bornAt;
      if (born == null) return false;
      return (now - born).inMilliseconds / 1000 > b.maxLife;
    });
  }

  @override
  void dispose() {
    _bursts.clear();
    super.dispose();
  }
}

class _Burst {
  _Burst({required this.origin, required this.particles, this.bornAt});

  final Offset origin;
  final List<_Particle> particles;
  Duration? bornAt;

  double get maxLife =>
      particles.fold(0.0, (m, p) => math.max(m, p.life)) + 0.1;
}

class _Particle {
  const _Particle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.life,
    required this.spin,
    required this.color,
  });

  final double angle, speed, size, life, spin;
  final Color color;
}

/// Paints whatever [controller] has fired. Drop it in a [Stack] above the
/// content and below anything interactive — it never takes hits.
class BurstLayer extends StatefulWidget {
  const BurstLayer({super.key, required this.controller});

  final BurstController controller;

  @override
  State<BurstLayer> createState() => _BurstLayerState();
}

class _BurstLayerState extends State<BurstLayer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  Duration _now = Duration.zero;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onFire);
  }

  @override
  void didUpdateWidget(covariant BurstLayer old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onFire);
      widget.controller.addListener(_onFire);
    }
  }

  void _onFire() {
    // Only burn a ticker while there's something to draw.
    if (widget.controller.hasActive && !_ticker.isActive) {
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    _now = elapsed;
    for (final burst in widget.controller._bursts) {
      burst.bornAt ??= elapsed;
    }
    widget.controller._prune(elapsed);
    if (!widget.controller.hasActive) {
      _ticker.stop();
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onFire);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppMotion.enabled(context)) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _BurstPainter(
            bursts: List.of(widget.controller._bursts),
            now: _now,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  const _BurstPainter({required this.bursts, required this.now});

  final List<_Burst> bursts;
  final Duration now;

  /// Downward pull, px/s². Light — these are sparks, not gravel.
  static const double _gravity = 320;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final burst in bursts) {
      final born = burst.bornAt;
      if (born == null) continue;
      final t = (now - born).inMicroseconds / 1e6;
      if (t < 0) continue;

      for (final p in burst.particles) {
        final life = (t / p.life).clamp(0.0, 1.0);
        if (life >= 1) continue;
        // Ease-out travel so sparks decelerate instead of flying flat.
        final travel = p.speed * t * (1 - 0.42 * life);
        final dx = math.cos(p.angle) * travel;
        final dy = math.sin(p.angle) * travel + 0.5 * _gravity * t * t;
        final pos = burst.origin + Offset(dx, dy);

        paint.color = p.color.withValues(alpha: (1 - life) * 0.95);
        final radius = p.size * (1 - life * 0.55);

        // A touch of streak on the fastest sparks reads as speed.
        if (p.speed > 200) {
          canvas.save();
          canvas.translate(pos.dx, pos.dy);
          canvas.rotate(p.angle + p.spin * t);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset.zero, width: radius * 3.4, height: radius),
              Radius.circular(radius),
            ),
            paint,
          );
          canvas.restore();
        } else {
          canvas.drawCircle(pos, radius, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) => true;
}

/// The "+240" that flies off a correct answer toward the score.
///
/// Rebuild it with a new [key] to replay; it animates once and stops.
class FloatingPoints extends StatefulWidget {
  const FloatingPoints({
    super.key,
    required this.points,
    this.multiplier = 1,
  });

  final int points;
  final int multiplier;

  @override
  State<FloatingPoints> createState() => _FloatingPointsState();
}

class _FloatingPointsState extends State<FloatingPoints>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1050),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppMotion.enabled(context) || widget.points <= 0) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final rise = Curves.easeOutCubic.transform(t);
          final fade = t < 0.16
              ? t / 0.16
              : t > 0.66
                  ? (1 - (t - 0.66) / 0.34).clamp(0.0, 1.0)
                  : 1.0;
          final pop = t < 0.2
              ? 0.6 + 0.4 * Curves.easeOutBack.transform(t / 0.2)
              : 1.0;

          return Transform.translate(
            offset: Offset(0, -46 * rise),
            child: Opacity(
              opacity: fade,
              child: Transform.scale(
                scale: pop,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '+${widget.points}',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: ArenaTheme.goldBright,
                        fontWeight: FontWeight.w800,
                        shadows: const [
                          BoxShadow(color: Colors.black54, blurRadius: 12),
                        ],
                      ),
                    ),
                    if (widget.multiplier > 1) ...[
                      const SizedBox(width: 4),
                      Text(
                        '×${widget.multiplier}',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: ArenaTheme.gold,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
