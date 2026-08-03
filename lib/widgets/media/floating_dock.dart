import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// A card that floats over the whole app, can be dragged, and parks itself at
/// the nearest allowed anchor when released.
///
/// Both media docks use it: the music card parks top / middle / bottom, and
/// the Watch player parks in a corner the way YouTube's does. Keeping one
/// implementation means the drag physics, the snap and the clearance rules
/// are debugged once.
///
/// ## Two things this widget deliberately does not do
///
/// **It never owns the parked position.** [anchor] is passed in as a
/// notifier held by the caller, because the docks are mounted inside a
/// rebuilding overlay and the music dock is unmounted entirely while the
/// full player is up. State inside this widget would be discarded on both,
/// and the card would jump back to its default the moment you navigated —
/// which is worse than not being draggable at all.
///
/// **It never uses a bare `Center` or `Align` to place the card.** The child
/// is laid out at an explicit size inside an explicit [Positioned]. An
/// `Align` shrink-wraps its height only when the incoming constraint is
/// unbounded, and inside an overlay it is bounded — the exact trap that
/// turned a 50dp ad banner into a full-screen one three times.
class FloatingDock extends StatefulWidget {
  const FloatingDock({
    super.key,
    required this.size,
    required this.anchors,
    required this.anchor,
    required this.child,
    this.margin = const EdgeInsets.all(12),
    this.onResize,
    this.minWidth = 140,
    this.maxWidth = 320,
  });

  /// The card's current size. The dock positions this exactly; the child is
  /// given these constraints tightly.
  final Size size;

  /// Where the card is allowed to come to rest, in [Alignment] coordinates
  /// over the draggable area (-1 = left/top, 1 = right/bottom).
  final List<Alignment> anchors;

  /// The parked anchor, owned by the caller so it survives this widget being
  /// rebuilt or unmounted. Written on drag end.
  final ValueNotifier<Alignment> anchor;

  /// Clearance from the screen edges. The bottom value is what keeps the
  /// card off the floating navigation island.
  final EdgeInsets margin;

  /// When non-null a resize grip is shown on the card's leading-bottom
  /// corner and this is called with the new width as it is dragged. The
  /// caller decides the aspect ratio and stores the value.
  final ValueChanged<double>? onResize;

  /// Bounds for [onResize].
  final double minWidth;
  final double maxWidth;

  final Widget child;

  @override
  State<FloatingDock> createState() => _FloatingDockState();
}

class _FloatingDockState extends State<FloatingDock>
    with SingleTickerProviderStateMixin {
  /// Built in [initState], never lazily. A `late final` controller created on
  /// first use gets CONSTRUCTED during `dispose()` when disposal is the first
  /// thing to touch it, which aborts teardown part-way through.
  late final AnimationController _snap = AnimationController(
    vsync: this,
    duration: AppMotion.quick,
  );

  /// Free position while a drag is in flight, in the same pixel space as the
  /// resolved anchor offset. Null when parked.
  Offset? _dragAt;

  /// Endpoints of the settle animation.
  Offset _from = Offset.zero;
  Offset _to = Offset.zero;

  @override
  void initState() {
    super.initState();
    _snap.addListener(() {
      if (!mounted) return;
      setState(() => _dragAt = Offset.lerp(_from, _to, _curved) ?? _to);
    });
    _snap.addStatusListener((status) {
      // Hand control back to the anchor once settled, so a rotation or a
      // size change re-resolves the position instead of holding a stale
      // pixel offset.
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _dragAt = null);
      }
    });
  }

  double get _curved => Curves.easeOutCubic.transform(_snap.value);

  @override
  void dispose() {
    _snap.dispose();
    super.dispose();
  }

  /// Pixel offset of [alignment] within the area the card may occupy.
  Offset _offsetFor(Alignment alignment, Size area) {
    final free = Size(
      (area.width - widget.margin.horizontal - widget.size.width)
          .clamp(0.0, double.infinity),
      (area.height - widget.margin.vertical - widget.size.height)
          .clamp(0.0, double.infinity),
    );
    return Offset(
      widget.margin.left + (alignment.x + 1) / 2 * free.width,
      widget.margin.top + (alignment.y + 1) / 2 * free.height,
    );
  }

  /// The anchor whose resting place is closest to where the finger left the
  /// card, biased along the fling direction so a deliberate flick reaches the
  /// far edge instead of falling back to the nearest one.
  Alignment _nearest(Offset at, Offset velocity, Size area) {
    // 90ms of travel is enough to express intent without letting a fast
    // flick shoot past every anchor.
    final projected = at + velocity * 0.09;
    var best = widget.anchors.first;
    var bestDistance = double.infinity;
    for (final candidate in widget.anchors) {
      final distance = (_offsetFor(candidate, area) - projected).distanceSquared;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = candidate;
      }
    }
    return best;
  }

  void _settleTo(Alignment target, Size area) {
    widget.anchor.value = target;
    _from = _dragAt ?? _offsetFor(target, area);
    _to = _offsetFor(target, area);
    if (_from == _to) {
      setState(() => _dragAt = null);
      return;
    }
    _snap
      ..duration = AppMotion.maybe(context, AppMotion.quick)
      ..forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = Size(constraints.maxWidth, constraints.maxHeight);
        return ValueListenableBuilder<Alignment>(
          valueListenable: widget.anchor,
          builder: (context, anchor, child) {
            final at = _dragAt ?? _offsetFor(anchor, area);
            return Stack(
              children: [
                Positioned(
                  left: at.dx,
                  top: at.dy,
                  width: widget.size.width,
                  height: widget.size.height,
                  child: GestureDetector(
                    behavior: HitTestBehavior.deferToChild,
                    onPanStart: (_) {
                      _snap.stop();
                      setState(() => _dragAt = at);
                    },
                    onPanUpdate: (d) {
                      final next = (_dragAt ?? at) + d.delta;
                      setState(() {
                        // Let the card overhang a little so dragging feels
                        // direct, but never far enough to lose it.
                        _dragAt = Offset(
                          next.dx.clamp(
                            -widget.size.width / 3,
                            area.width - widget.size.width * 2 / 3,
                          ),
                          next.dy.clamp(
                            0.0,
                            (area.height - widget.size.height / 2)
                                .clamp(0.0, double.infinity),
                          ),
                        );
                      });
                    },
                    onPanEnd: (d) => _settleTo(
                      _nearest(
                        _dragAt ?? at,
                        d.velocity.pixelsPerSecond,
                        area,
                      ),
                      area,
                    ),
                    onPanCancel: () => _settleTo(widget.anchor.value, area),
                    child: child,
                  ),
                ),
              ],
            );
          },
          child: widget.onResize == null
              ? widget.child
              : _withResizeGrip(widget.child),
        );
      },
    );
  }

  /// A grip in the corner nearest the screen centre, so resizing pulls the
  /// card open rather than pushing it off the edge.
  Widget _withResizeGrip(Widget child) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          left: 0,
          bottom: 0,
          child: GestureDetector(
            // The grip must claim the gesture before the dock's own pan
            // handler sees it, or resizing would drag the card instead.
            onPanStart: (_) {},
            onPanUpdate: (d) {
              final next = (widget.size.width - d.delta.dx)
                  .clamp(widget.minWidth, widget.maxWidth);
              widget.onResize!(next);
            },
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.bottomLeft,
              padding: const EdgeInsets.all(6),
              // Transparent, not nothing: an empty Container has no size to
              // hit-test against and the grip would be dead.
              color: Colors.transparent,
              child: Transform.rotate(
                angle: 1.5708, // 90°, so the chevron points down-left
                child: Icon(
                  Icons.open_in_full_rounded,
                  size: 15,
                  color: Colors.white.withValues(alpha: 0.85),
                  shadows: const [
                    Shadow(color: Colors.black54, blurRadius: 4),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
