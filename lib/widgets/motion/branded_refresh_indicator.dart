import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';
import 'brand_spinner.dart';

/// Branded pull-to-refresh — drop-in replacement for Material's
/// [RefreshIndicator] (same `onRefresh` + `child` surface, accepts and
/// ignores `color` so existing call sites swap with a rename).
///
/// Instead of the stock grey-chip spinner: a floating brand chip slides
/// down with the pull, a blue arc draws in proportion to drag progress,
/// a gold comet head snaps on (with a haptic tick) the moment the pull
/// is armed, and the arc hands off to the indeterminate [BrandSpinner]
/// while [onRefresh] runs.
///
/// Implemented from scratch on scroll notifications — no new packages.
/// Works with both clamping (Android) and bouncing (iOS) physics. Drag
/// tracking is direct manipulation so it stays under "remove
/// animations"; only the decorative settle tweens collapse to zero.
class BrandedRefreshIndicator extends StatefulWidget {
  const BrandedRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.color, // ignored — kept for RefreshIndicator drop-in compatibility
    this.displacement = 64,
  });

  final Future<void> Function() onRefresh;
  final Widget child;
  final Color? color;

  /// Resting distance of the chip below the top edge while refreshing.
  final double displacement;

  @override
  State<BrandedRefreshIndicator> createState() =>
      _BrandedRefreshIndicatorState();
}

enum _Phase { idle, dragging, refreshing, settling }

class _BrandedRefreshIndicatorState extends State<BrandedRefreshIndicator>
    with SingleTickerProviderStateMixin {
  /// Damped pull distance in logical px; progress = _drag / _armExtent.
  static const double _armExtent = 88;
  static const double _dragDamping = 0.55;
  static const double _chipSize = 46;

  double _drag = 0;
  _Phase _phase = _Phase.idle;
  bool _armedHapticSent = false;

  late final AnimationController _settle;
  Animation<double>? _settleTween;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(
      vsync: this,
      duration: AppMotion.standard,
    )..addListener(() {
        final tween = _settleTween;
        if (tween != null) setState(() => _drag = tween.value);
      });
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  double get _progress => (_drag / _armExtent).clamp(0.0, 1.5);

  bool _handleNotification(ScrollNotification n) {
    if (n.depth != 0) return false;

    switch (_phase) {
      case _Phase.refreshing:
      case _Phase.settling:
        return false;
      case _Phase.idle:
      case _Phase.dragging:
        break;
    }

    if (n is OverscrollNotification) {
      // Clamping physics (Android): finger pulling past the top edge.
      if (n.overscroll < 0 &&
          n.metrics.extentBefore == 0 &&
          n.dragDetails != null) {
        _settle.stop();
        setState(() {
          _phase = _Phase.dragging;
          _drag += -n.overscroll * _dragDamping;
        });
        _maybeArmHaptic();
      }
    } else if (n is ScrollUpdateNotification) {
      if (n.metrics.pixels < 0 && n.dragDetails != null) {
        // Bouncing physics (iOS): position itself goes negative.
        _settle.stop();
        setState(() {
          _phase = _Phase.dragging;
          _drag = -n.metrics.pixels * (_dragDamping + 0.3);
        });
        _maybeArmHaptic();
      } else if (_phase == _Phase.dragging) {
        final delta = n.scrollDelta ?? 0;
        if (n.dragDetails != null && delta > 0) {
          // Finger reversed and content is scrolling again — bleed the
          // pull back out.
          setState(() {
            _drag = math.max(0, _drag - delta);
            if (_drag == 0) _phase = _Phase.idle;
          });
        } else if (n.dragDetails == null) {
          _onReleased();
        }
      }
    } else if (n is ScrollEndNotification) {
      if (_phase == _Phase.dragging) _onReleased();
    }
    return false;
  }

  void _maybeArmHaptic() {
    if (_progress >= 1.0 && !_armedHapticSent) {
      _armedHapticSent = true;
      HapticFeedback.lightImpact();
    } else if (_progress < 1.0) {
      _armedHapticSent = false;
    }
  }

  void _onReleased() {
    if (_progress >= 1.0) {
      _startRefresh();
    } else {
      _animateDragTo(0, then: _Phase.idle);
    }
  }

  Future<void> _startRefresh() async {
    setState(() => _phase = _Phase.refreshing);
    _animateDragTo(widget.displacement + _chipSize);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        setState(() => _phase = _Phase.settling);
        _animateDragTo(0, then: _Phase.idle);
      }
    }
  }

  void _animateDragTo(double target, {_Phase? then}) {
    _settleTween = Tween<double>(begin: _drag, end: target).animate(
      CurvedAnimation(parent: _settle, curve: AppMotion.easeOut),
    );
    _settle
      ..duration = AppMotion.maybe(context, AppMotion.standard)
      ..forward(from: 0).whenComplete(() {
        if (then != null && mounted) {
          setState(() {
            _phase = then;
            _armedHapticSent = false;
          });
        }
      });
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _handleNotification,
      child: Stack(
        children: [
          widget.child,
          if (_phase != _Phase.idle)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: _buildChip(context),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChip(BuildContext context) {
    // Chip rides just behind the fingertip: starts hidden above the edge
    // and eases toward the displacement line as the pull deepens.
    final travel = math.min(_drag, widget.displacement + _chipSize);
    final top = -_chipSize + travel;
    final appear = (_progress * 1.4).clamp(0.0, 1.0);

    return Align(
      alignment: Alignment.topCenter,
      child: Transform.translate(
        offset: Offset(0, top),
        child: Transform.scale(
          scale: 0.6 + 0.4 * Curves.easeOutCubic.transform(appear),
          child: Opacity(
            opacity: appear,
            child: Container(
              width: _chipSize,
              height: _chipSize,
              decoration: BoxDecoration(
                color: context.palette.card,
                shape: BoxShape.circle,
                boxShadow: AppShadows.floating(context),
              ),
              padding: const EdgeInsets.all(9),
              child: _phase == _Phase.refreshing
                  ? const BrandSpinner(size: _chipSize - 18)
                  : CustomPaint(
                      painter: _PullArcPainter(progress: _progress),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Determinate pull arc: draws with drag progress, gains its gold head
/// at 100%, and keeps winding slightly on overdrag so the surface always
/// answers the finger.
class _PullArcPainter extends CustomPainter {
  _PullArcPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final stroke = size.shortestSide / 9;
    final radius = (size.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final t = progress.clamp(0.0, 1.0);
    final overdrag = (progress - 1.0).clamp(0.0, 0.5);
    final start = -math.pi / 2 + overdrag * math.pi; // winds on overdrag
    final sweep = t * 2 * math.pi * 0.83;

    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = AppColors.primaryBlue
            .withValues(alpha: 0.35 + 0.65 * t),
    );

    if (progress >= 1.0) {
      final head = Offset(
        center.dx + radius * math.cos(start + sweep),
        center.dy + radius * math.sin(start + sweep),
      );
      canvas.drawCircle(
        head,
        stroke * 0.72,
        Paint()..color = AppColors.goldAccent,
      );
    }
  }

  @override
  bool shouldRepaint(_PullArcPainter old) => old.progress != progress;
}
