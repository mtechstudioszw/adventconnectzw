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
