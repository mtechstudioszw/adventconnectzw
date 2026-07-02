import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// Skeleton → content handoff: while [loading] is true the shimmer
/// skeleton shows; when data lands the real content crossfades in with a
/// small rise, so screens never pop from blank to full (redesign brief:
/// "skeletons crossfade into real content").
///
/// ```dart
/// ContentReveal(
///   loading: _loading,
///   skeleton: ShimmerLoaders.cardList(),
///   child: _buildList(),
/// )
/// ```
class ContentReveal extends StatelessWidget {
  const ContentReveal({
    super.key,
    required this.loading,
    required this.skeleton,
    required this.child,
    this.duration = AppMotion.standard,
  });

  final bool loading;
  final Widget skeleton;
  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.maybe(context, duration),
      switchInCurve: AppMotion.easeOut,
      switchOutCurve: AppMotion.easeIn,
      transitionBuilder: (incoming, animation) {
        final isContent = incoming.key == const ValueKey('content');
        return FadeTransition(
          opacity: animation,
          child: isContent
              ? SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.02),
                    end: Offset.zero,
                  ).animate(animation),
                  child: incoming,
                )
              : incoming,
        );
      },
      // Skeleton and content usually have different heights; pin both to
      // the top so the crossfade doesn't jump vertically mid-flight.
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topCenter,
        children: [...previousChildren, ?currentChild],
      ),
      child: loading
          ? KeyedSubtree(key: const ValueKey('skeleton'), child: skeleton)
          : KeyedSubtree(key: const ValueKey('content'), child: child),
    );
  }
}
