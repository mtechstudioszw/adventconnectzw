import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../theme/app_motion.dart';
import '../../../../theme/app_text_styles.dart';
import '../arena_theme.dart';

enum AnswerTileState {
  /// Not answered yet — tappable.
  idle,

  /// The player picked this and it was right.
  correct,

  /// The player picked this and it was wrong.
  wrong,

  /// The right answer, shown after the player picked a different one.
  revealed,

  /// A wrong option the player didn't pick.
  dimmed,
}

/// One tappable answer.
///
/// Every state change is felt, not just shown:
/// * **entrance** — rises and fades in on the [entrance] animation the
///   parent hands it (parent owns the stagger, so N tiles share one ticker);
/// * **press** — compresses under the finger;
/// * **correct** — pops, glows green, and a checkmark draws itself on;
/// * **wrong** — shakes on a decaying sine and turns red;
/// * **removed by 50/50** — collapses out of the list instead of vanishing.
class AnswerTile extends StatefulWidget {
  const AnswerTile({
    super.key,
    required this.label,
    required this.letter,
    required this.state,
    required this.entrance,
    this.onTap,
    this.hidden = false,
  });

  final String label;

  /// 'A'–'D'.
  final String letter;
  final AnswerTileState state;
  final Animation<double> entrance;

  /// Reports the tile's centre in global coordinates, so the caller can
  /// throw the spark burst and the "+points" label out of the thing the
  /// finger actually touched rather than from a fixed spot on screen.
  final void Function(Offset tileCentre)? onTap;

  /// Removed by the 50/50 hint.
  final bool hidden;

  @override
  State<AnswerTile> createState() => _AnswerTileState();
}

class _AnswerTileState extends State<AnswerTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _resolve = AnimationController(
    vsync: this,
    duration: AppMotion.celebrate,
  );

  bool _pressed = false;

  @override
  void didUpdateWidget(covariant AnswerTile old) {
    super.didUpdateWidget(old);
    final becameResolved = old.state == AnswerTileState.idle &&
        widget.state != AnswerTileState.idle;
    if (becameResolved && AppMotion.enabled(context)) {
      _resolve.forward(from: 0);
    } else if (widget.state == AnswerTileState.idle) {
      _resolve.value = 0;
    }
  }

  @override
  void dispose() {
    _resolve.dispose();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  void _handleTap() {
    final callback = widget.onTap;
    if (callback == null) return;
    final box = context.findRenderObject() as RenderBox?;
    final centre = (box != null && box.hasSize)
        ? box.localToGlobal(box.size.center(Offset.zero))
        : Offset.zero;
    callback(centre);
  }

  // ---- Per-state styling --------------------------------------------------

  Color get _borderColor => switch (widget.state) {
        AnswerTileState.correct => ArenaTheme.correctOnNavy,
        AnswerTileState.revealed =>
          ArenaTheme.correctOnNavy.withValues(alpha: 0.75),
        AnswerTileState.wrong => ArenaTheme.wrongOnNavy,
        AnswerTileState.dimmed => ArenaTheme.glassBorder,
        AnswerTileState.idle =>
          _pressed ? ArenaTheme.glassBorderActive : ArenaTheme.glassBorder,
      };

  Color get _fillColor => switch (widget.state) {
        AnswerTileState.correct =>
          ArenaTheme.correctOnNavy.withValues(alpha: 0.16),
        AnswerTileState.revealed =>
          ArenaTheme.correctOnNavy.withValues(alpha: 0.10),
        AnswerTileState.wrong => ArenaTheme.wrongOnNavy.withValues(alpha: 0.14),
        _ => ArenaTheme.glass,
      };

  double get _opacity => widget.state == AnswerTileState.dimmed ? 0.45 : 1.0;

  @override
  Widget build(BuildContext context) {
    final animate = AppMotion.enabled(context);
    final resolved = widget.state != AnswerTileState.idle;

    return AnimatedOpacity(
      opacity: widget.hidden ? 0 : 1,
      duration: AppMotion.maybe(context, AppMotion.quick),
      child: AnimatedSize(
        duration: AppMotion.maybe(context, AppMotion.standard),
        curve: AppMotion.ease,
        alignment: Alignment.topCenter,
        child: widget.hidden
            ? const SizedBox(width: double.infinity)
            : AnimatedBuilder(
                animation: Listenable.merge([widget.entrance, _resolve]),
                builder: (context, child) {
                  final enter = widget.entrance.value.clamp(0.0, 1.0);
                  final r = _resolve.value;

                  // Wrong answers shake; correct answers pop.
                  var dx = 0.0;
                  var scale = _pressed && !resolved ? 0.975 : 1.0;
                  if (animate && r > 0 && r < 1) {
                    if (widget.state == AnswerTileState.wrong) {
                      dx = math.sin(r * math.pi * 5) * 9 * (1 - r);
                    } else if (widget.state == AnswerTileState.correct) {
                      scale = 1 + 0.06 * math.sin(r * math.pi) * (1 - r * 0.35);
                    }
                  }

                  return Opacity(
                    opacity: enter * _opacity,
                    child: Transform.translate(
                      offset: Offset(dx, (1 - enter) * 22),
                      child: Transform.scale(scale: scale, child: child),
                    ),
                  );
                },
                child: _buildTile(context),
              ),
      ),
    );
  }

  Widget _buildTile(BuildContext context) {
    final resolved = widget.state != AnswerTileState.idle;
    final accent = switch (widget.state) {
      AnswerTileState.correct ||
      AnswerTileState.revealed =>
        ArenaTheme.correctOnNavy,
      AnswerTileState.wrong => ArenaTheme.wrongOnNavy,
      _ => ArenaTheme.textOnNavy,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Semantics(
        button: !resolved,
        label: '${widget.letter}. ${widget.label}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: resolved ? null : (_) => _setPressed(true),
          onTapUp: resolved ? null : (_) => _setPressed(false),
          onTapCancel: resolved ? null : () => _setPressed(false),
          onTap: resolved ? null : _handleTap,
          child: AnimatedContainer(
            duration: AppMotion.maybe(context, AppMotion.quick),
            curve: AppMotion.ease,
            padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
            decoration: BoxDecoration(
              color: _fillColor,
              borderRadius: ArenaTheme.tileRadius,
              border: Border.all(color: _borderColor, width: 1.5),
              boxShadow: switch (widget.state) {
                AnswerTileState.correct =>
                  ArenaTheme.glow(ArenaTheme.correctOnNavy),
                AnswerTileState.wrong =>
                  ArenaTheme.glow(ArenaTheme.wrongOnNavy, strength: 0.7),
                _ => null,
              },
            ),
            child: Row(
              children: [
                _LetterBadge(letter: widget.letter, state: widget.state),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: widget.state == AnswerTileState.dimmed
                          ? ArenaTheme.textMutedOnNavy
                          : ArenaTheme.textOnNavy,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
                if (widget.state == AnswerTileState.correct ||
                    widget.state == AnswerTileState.revealed) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: AnimatedBuilder(
                      animation: _resolve,
                      builder: (context, _) => CustomPaint(
                        painter: _CheckPainter(
                          progress: AppMotion.enabled(context)
                              ? Curves.easeOutCubic
                                  .transform(_resolve.value.clamp(0.0, 1.0))
                              : 1.0,
                          color: accent,
                        ),
                      ),
                    ),
                  ),
                ] else if (widget.state == AnswerTileState.wrong) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.close_rounded, size: 22, color: accent),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LetterBadge extends StatelessWidget {
  const _LetterBadge({required this.letter, required this.state});

  final String letter;
  final AnswerTileState state;

  @override
  Widget build(BuildContext context) {
    final active =
        state == AnswerTileState.correct || state == AnswerTileState.revealed;
    final wrong = state == AnswerTileState.wrong;
    final color = active
        ? ArenaTheme.correctOnNavy
        : wrong
            ? ArenaTheme.wrongOnNavy
            : ArenaTheme.textMutedOnNavy;

    return AnimatedContainer(
      duration: AppMotion.maybe(context, AppMotion.quick),
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: (active || wrong)
            ? color.withValues(alpha: 0.18)
            : ArenaTheme.glassStrong,
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        letter,
        style: AppTextStyles.labelMedium.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Draws a checkmark stroke on, rather than popping an icon in.
class _CheckPainter extends CustomPainter {
  const _CheckPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.20, h * 0.52)
      ..lineTo(w * 0.43, h * 0.74)
      ..lineTo(w * 0.80, h * 0.28);

    final metrics = path.computeMetrics().toList();
    final drawn = Path();
    for (final metric in metrics) {
      drawn.addPath(
        metric.extractPath(0, metric.length * progress.clamp(0.0, 1.0)),
        Offset.zero,
      );
    }

    canvas.drawPath(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _CheckPainter old) =>
      old.progress != progress || old.color != color;
}
