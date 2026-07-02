import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// App-wide route transition: a fade-through with a gentle scale settle,
/// replacing the stock Material zoom so screen changes flow instead of
/// snapping.
///
/// Registered ONCE in `AppTheme` via `pageTransitionsTheme` — every
/// `GoRoute.builder` produces a `MaterialPage`, and `MaterialPage` reads
/// its transition from the theme, so all ~90 routes pick this up with no
/// per-route wiring.
///
/// iOS deliberately keeps `CupertinoPageTransitionsBuilder` (see
/// AppTheme): the edge-swipe back gesture is core iOS muscle memory and a
/// custom transition would break it. Android — our primary market — gets
/// the full custom motion.
///
/// Trade-off (documented for future-us): a custom builder opts out of
/// Android 14 predictive-back preview animations, which only the stock
/// zoom/fade-forwards builders support. Regular back navigation still
/// animates normally (this transition in reverse).
class BrandFadeThroughTransitionsBuilder extends PageTransitionsBuilder {
  const BrandFadeThroughTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (!AppMotion.enabled(context)) return child;

    // Incoming page: hold back briefly, then fade in while settling from
    // 96% scale — the "through" part of fade-through.
    final enter = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.30, 1.0, curve: Curves.easeOutCubic),
      reverseCurve: const Interval(0.60, 1.0, curve: Curves.easeInCubic),
    );

    // This page while it's being covered by the NEXT route: recede
    // slightly. Scale only, no fade — fading the page underneath an
    // incoming transparent route flashes the scaffold background.
    final exit = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeInOutCubic,
    );

    return AnimatedBuilder(
      animation: exit,
      builder: (context, page) => Transform.scale(
        scale: 1.0 - 0.03 * exit.value,
        filterQuality: FilterQuality.none,
        child: page,
      ),
      child: FadeTransition(
        opacity: enter,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(enter),
          filterQuality: FilterQuality.none,
          child: child,
        ),
      ),
    );
  }
}
