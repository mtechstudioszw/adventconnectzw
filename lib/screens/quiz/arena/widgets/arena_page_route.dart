import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../theme/app_motion.dart';
import '../arena_theme.dart';

/// The transition that opens the Quiz Arena.
///
/// Every other route in the app uses the shared fade-through from
/// `AppTheme.pageTransitionsTheme`. The arena gets its own on purpose: this
/// is the moment that has to read as *launching something*, not pushing a
/// screen. The navy canvas washes in first and the content expands up
/// behind it, so the app you were in is gone before the arena arrives.
///
/// Trade-off, stated plainly: this overrides the Cupertino transition on
/// iOS, so the edge-swipe-back gesture doesn't apply to this route. That's
/// acceptable here — and only here — because the arena has a permanent back
/// button in its header, and a round deliberately intercepts back anyway to
/// confirm before you abandon it.
Page<T> arenaPage<T>({required LocalKey key, required Widget child}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 520),
    reverseTransitionDuration: const Duration(milliseconds: 340),
    transitionsBuilder: (context, animation, secondary, child) {
      if (!AppMotion.enabled(context)) return child;

      // The canvas arrives ahead of the content.
      final wash = CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
        reverseCurve: const Interval(0.4, 1.0, curve: Curves.easeIn),
      );
      final content = CurvedAnimation(
        parent: animation,
        curve: const Interval(0.22, 1.0, curve: Curves.easeOutCubic),
        reverseCurve: const Interval(0.0, 0.8, curve: Curves.easeInCubic),
      );

      return Stack(
        fit: StackFit.expand,
        children: [
          FadeTransition(
            opacity: wash,
            child: const ColoredBox(color: ArenaTheme.canvasTop),
          ),
          FadeTransition(
            opacity: content,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.88, end: 1.0).animate(content),
              filterQuality: FilterQuality.none,
              child: child,
            ),
          ),
        ],
      );
    },
  );
}
