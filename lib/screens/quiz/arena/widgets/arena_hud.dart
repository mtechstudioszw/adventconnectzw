import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../models/quiz_round.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/app_text_styles.dart';
import '../arena_theme.dart';

/// The draining question clock.
///
/// Deliberately a *bonus* meter, not a guillotine: emptying it costs the
/// speed points and nothing else. The colour walks blue → gold → red as it
/// drains so the pressure is felt peripherally, without a number to stare at.
class TimerRing extends StatelessWidget {
  const TimerRing({
    super.key,
    required this.remaining,
    required this.totalSeconds,
    this.size = 46,
    this.frozen = false,
  });

  /// 1.0 = full clock, 0.0 = empty.
  final Animation<double> remaining;
  final int totalSeconds;
  final double size;

  /// True once the question is answered — the ring stops reacting.
  final bool frozen;

  static Color colorFor(double fraction) {
    if (fraction > 0.5) {
      return Color.lerp(
        ArenaTheme.gold,
        const Color(0xFF57A6F0),
        ((fraction - 0.5) / 0.5).clamp(0.0, 1.0),
      )!;
    }
    return Color.lerp(
      ArenaTheme.wrongOnNavy,
      ArenaTheme.gold,
      (fraction / 0.5).clamp(0.0, 1.0),
    )!;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: remaining,
      builder: (context, _) {
        final value = remaining.value.clamp(0.0, 1.0);
        final seconds = (value * totalSeconds).ceil();
        final color = frozen ? ArenaTheme.textFaintOnNavy : colorFor(value);
        // Gentle urgency pulse in the last quarter.
        final urgent = !frozen && value <= 0.25 && value > 0;
        final pulse = urgent
            ? 1 + 0.06 * math.sin(value * totalSeconds * math.pi * 2)
            : 1.0;

        return Transform.scale(
          scale: pulse,
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _RingPainter(value: value, color: color),
              child: Center(
                child: Text(
                  frozen ? '—' : '$seconds',
                  style: AppTextStyles.titleSmall.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: size * 0.34,
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

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 3;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..color = Colors.white.withValues(alpha: 0.12),
    );

    if (value <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3.5
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.color != color;
}

/// The streak meter. Appears at 2 in a row, and punches every time the
/// multiplier steps up — the "one more round" hook.
class ComboMeter extends StatelessWidget {
  const ComboMeter({super.key, required this.combo});

  final int combo;

  @override
  Widget build(BuildContext context) {
    final multiplier = QuizScoring.multiplierFor(combo);
    final next = QuizScoring.nextComboThreshold(combo);
    final visible = combo >= 2;
    final animate = AppMotion.enabled(context);

    // Fill toward the next multiplier step (full when capped).
    final previousStep = multiplier == 1
        ? 0
        : multiplier == 2
            ? 3
            : multiplier == 3
                ? 5
                : 8;
    final progress = next == null
        ? 1.0
        : ((combo - previousStep) / (next - previousStep)).clamp(0.0, 1.0);

    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: AppMotion.maybe(context, AppMotion.quick),
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, -0.4),
        duration: AppMotion.maybe(context, AppMotion.standard),
        curve: AppMotion.spring,
        child: TweenAnimationBuilder<double>(
          // Rebuilds with a punch whenever the multiplier changes.
          key: ValueKey(multiplier),
          tween: Tween(begin: animate && multiplier > 1 ? 1.35 : 1.0, end: 1.0),
          duration: AppMotion.maybe(context, AppMotion.celebrate),
          curve: Curves.elasticOut,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
            decoration: BoxDecoration(
              color: ArenaTheme.glass,
              borderRadius: BorderRadius.circular(ArenaTheme.radiusPill),
              border: Border.all(
                color: multiplier > 1
                    ? ArenaTheme.gold.withValues(alpha: 0.55)
                    : ArenaTheme.glassBorder,
              ),
              boxShadow: multiplier > 1
                  ? ArenaTheme.glow(ArenaTheme.gold, strength: 0.5)
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.local_fire_department_rounded,
                  size: 16 + (multiplier - 1) * 2.0,
                  color: ArenaTheme.gold,
                ),
                const SizedBox(width: 6),
                Text(
                  multiplier > 1 ? '×$multiplier' : '$combo',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: multiplier > 1
                        ? ArenaTheme.gold
                        : ArenaTheme.textOnNavy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 26,
                  height: 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.white.withValues(alpha: 0.14),
                      valueColor:
                          const AlwaysStoppedAnimation(ArenaTheme.gold),
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

/// The running score. Counts up rather than jumping, so points *land*.
class ScorePill extends StatelessWidget {
  const ScorePill({super.key, required this.points, this.compact = false});

  final int points;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: points.toDouble()),
      duration: AppMotion.maybe(context, const Duration(milliseconds: 620)),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14,
            vertical: compact ? 5 : 7,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                ArenaTheme.gold.withValues(alpha: 0.22),
                ArenaTheme.gold.withValues(alpha: 0.10),
              ],
            ),
            borderRadius: BorderRadius.circular(ArenaTheme.radiusPill),
            border:
                Border.all(color: ArenaTheme.gold.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.stars_rounded,
                  size: 15, color: ArenaTheme.gold),
              const SizedBox(width: 6),
              Text(
                _format(value.round()),
                style: AppTextStyles.labelMedium.copyWith(
                  color: ArenaTheme.goldBright,
                  fontWeight: FontWeight.w800,
                  fontSize: compact ? 13 : 14,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _format(int value) {
    final text = value.toString();
    if (text.length <= 3) return text;
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
      buffer.write(text[i]);
    }
    return buffer.toString();
  }
}

/// Progress across the questions of a round.
///
/// Segmented for the short modes (you can see "two to go"), but Survival
/// and Speed pull a 40–60 question buffer, and 60 two-pixel slivers is
/// noise — those fall back to a continuous bar.
class RoundProgress extends StatelessWidget {
  const RoundProgress({
    super.key,
    required this.index,
    required this.total,
  });

  final int index;
  final int total;

  /// Above this many questions, segments stop being readable.
  static const int _maxSegments = 12;

  @override
  Widget build(BuildContext context) {
    if (total > _maxSegments) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: total == 0 ? 0 : (index / total).clamp(0.0, 1.0),
          minHeight: 4,
          backgroundColor: Colors.white.withValues(alpha: 0.14),
          valueColor: const AlwaysStoppedAnimation(ArenaTheme.gold),
        ),
      );
    }
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: AnimatedContainer(
              duration: AppMotion.maybe(context, AppMotion.standard),
              curve: AppMotion.easeOut,
              height: 4,
              decoration: BoxDecoration(
                color: i < index
                    ? ArenaTheme.gold
                    : i == index
                        ? ArenaTheme.gold.withValues(alpha: 0.55)
                        : Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
