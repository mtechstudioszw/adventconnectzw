import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// Entrance animation for sections and list items: fade in + rise from
/// slightly below, with successive [index]es starting ~70ms apart so a
/// screen builds itself instead of popping in fully formed.
///
/// One reusable widget — the controller lives in here, never copy-pasted
/// into screens:
///
/// ```dart
/// // Sections of a screen:
/// StaggeredReveal(index: 0, child: _greeting()),
/// StaggeredReveal(index: 1, child: _quickActions()),
///
/// // Or map a whole list in one call:
/// Column(children: StaggeredReveal.list(children: sections)),
/// ```
///
/// * Plays once per mount; rebuilds don't replay it.
/// * The delay is capped so item 40 of a long feed doesn't wait seconds
///   — everything is settled within ~[_maxDelay].
/// * Honours "remove animations": content appears immediately.
class StaggeredReveal extends StatefulWidget {
  const StaggeredReveal({
    super.key,
    required this.child,
    this.index = 0,
    this.duration = AppMotion.entrance,
    this.interval = AppMotion.stagger,
    this.rise = 24,
    this.curve = AppMotion.easeOut,
  });

  final Widget child;

  /// Position within the stagger sequence — drives the start delay.
  final int index;

  final Duration duration;

  /// Delay between successive indexes.
  final Duration interval;

  /// How far below its resting position the child starts, in logical px.
  final double rise;

  final Curve curve;

  /// Wraps every child in a [StaggeredReveal] with ascending indexes —
  /// for `Column`/`ListView(children: ...)` call sites.
  static List<Widget> list({
    required List<Widget> children,
    int startIndex = 0,
    Duration duration = AppMotion.entrance,
    Duration interval = AppMotion.stagger,
    double rise = 24,
  }) {
    return [
      for (var i = 0; i < children.length; i++)
        StaggeredReveal(
          index: startIndex + i,
          duration: duration,
          interval: interval,
          rise: rise,
          child: children[i],
        ),
    ];
  }

  /// Everything settles within this window regardless of index, so long
  /// feeds don't trickle in forever.
  static const Duration _maxDelay = Duration(milliseconds: 560);

  @override
  State<StaggeredReveal> createState() => _StaggeredRevealState();
}

class _StaggeredRevealState extends State<StaggeredReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curved;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _curved = CurvedAnimation(parent: _controller, curve: widget.curve);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) return;
    _scheduled = true;
    if (!AppMotion.enabled(context)) {
      _controller.value = 1.0;
      return;
    }
    final delayMs = (widget.interval.inMilliseconds * widget.index)
        .clamp(0, StaggeredReveal._maxDelay.inMilliseconds);
    if (delayMs == 0) {
      _controller.forward();
    } else {
      Future.delayed(Duration(milliseconds: delayMs), () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _curved.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curved,
      builder: (context, child) {
        final t = _curved.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, widget.rise * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
