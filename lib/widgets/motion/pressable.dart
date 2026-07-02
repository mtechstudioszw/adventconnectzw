import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_motion.dart';

/// Press feedback for any tappable surface — the card/button compresses
/// slightly on touch-down and springs back on release, so every touch in
/// the app visibly responds (redesign brief, Phase 1).
///
/// Usage: wrap the OUTERMOST decorated box of a card/button and move the
/// tap handler here:
///
/// ```dart
/// Pressable(
///   onTap: _open,
///   child: Container(decoration: ..., child: ...),
/// )
/// ```
///
/// * Interruptible: driven by [AnimatedScale], so a finger that taps
///   mid-spring simply retargets the scale.
/// * Accessibility: no scaling when the OS "remove animations" setting is
///   on; taps still work. Adds button semantics automatically.
/// * If neither [onTap] nor [onLongPress] is provided the child is
///   returned untouched — nothing should *look* pressable but be dead.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.96,
    this.haptics = false,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// How far the surface compresses while held. 0.96 for cards; use
  /// ~0.94 for small elements (chips, icons) so the response stays
  /// visible at their size.
  final double pressedScale;

  /// Light haptic tick on tap-down. Reserve for primary actions —
  /// buzzing every list card feels cheap.
  final bool haptics;

  final HitTestBehavior behavior;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null && widget.onLongPress == null) {
      return widget.child;
    }

    final animate = AppMotion.enabled(context);

    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: widget.behavior,
        onTapDown: (_) {
          if (widget.haptics) HapticFeedback.selectionClick();
          _setPressed(true);
        },
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                _setPressed(false);
                widget.onLongPress!.call();
              },
        onLongPressDown:
            widget.onLongPress == null ? null : (_) => _setPressed(true),
        onLongPressCancel:
            widget.onLongPress == null ? null : () => _setPressed(false),
        child: AnimatedScale(
          scale: !animate
              ? 1.0
              : _pressed
                  ? widget.pressedScale
                  : 1.0,
          duration: _pressed ? AppMotion.pressIn : AppMotion.pressOut,
          curve: _pressed ? Curves.easeOutCubic : AppMotion.spring,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Retrofit press feedback: purely VISUAL compress-on-touch for widgets
/// that already own their tap handling (an existing `InkWell` /
/// `GestureDetector` keeps working untouched — ripple, busy-guards,
/// semantics and all).
///
/// Built on [Listener] raw pointer events, so it never competes in the
/// gesture arena. Two guards keep it honest inside scrollables:
/// * the press visual waits ~70ms before showing, and
/// * any pointer travel beyond the slop cancels it,
/// so flick-scrolling a list never squeezes the card under the finger.
/// A tap released faster than the delay still gets a quick pulse — every
/// real touch gets a response.
///
/// ```dart
/// PressEffect(child: Card(child: InkWell(onTap: ..., child: ...)))
/// ```
class PressEffect extends StatefulWidget {
  const PressEffect({
    super.key,
    required this.child,
    this.pressedScale = 0.96,
  });

  final Widget child;
  final double pressedScale;

  @override
  State<PressEffect> createState() => _PressEffectState();
}

class _PressEffectState extends State<PressEffect> {
  static const Duration _showDelay = Duration(milliseconds: 70);
  static const double _touchSlop = 12;

  Timer? _delay;
  Timer? _pulse;
  Offset? _downAt;
  bool _pressed = false;

  @override
  void dispose() {
    _delay?.cancel();
    _pulse?.cancel();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  void _onDown(PointerDownEvent event) {
    _downAt = event.position;
    _pulse?.cancel();
    _delay?.cancel();
    _delay = Timer(_showDelay, () => _setPressed(true));
  }

  void _onMove(PointerMoveEvent event) {
    final downAt = _downAt;
    if (downAt == null) return;
    if ((event.position - downAt).distance > _touchSlop) _cancel();
  }

  void _onUp(PointerUpEvent event) {
    final tapWasQuick = _delay?.isActive ?? false;
    _delay?.cancel();
    _downAt = null;
    if (tapWasQuick) {
      // Released before the press visual appeared — flash a quick pulse
      // so even the fastest tap is acknowledged.
      _setPressed(true);
      _pulse = Timer(AppMotion.pressIn, () => _setPressed(false));
    } else {
      _setPressed(false);
    }
  }

  void _cancel() {
    _delay?.cancel();
    _downAt = null;
    _setPressed(false);
  }

  @override
  Widget build(BuildContext context) {
    if (!AppMotion.enabled(context)) return widget.child;
    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: (_) => _cancel(),
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: _pressed ? AppMotion.pressIn : AppMotion.pressOut,
        curve: _pressed ? Curves.easeOutCubic : AppMotion.spring,
        child: widget.child,
      ),
    );
  }
}
