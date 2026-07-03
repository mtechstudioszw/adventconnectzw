import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../theme/app_motion.dart';

/// YouTube-style bottom-nav behaviour: scrolling DOWN collapses the nav
/// out of the way, any scroll UP brings it straight back.
///
/// [HideOnScroll] animates the child's height factor (a real layout
/// collapse, so the freed space goes to content — no blank strip), and
/// [NavVisibilityMixin] gives a screen the scroll-direction listener +
/// state with two lines of wiring:
///
/// ```dart
/// class _MyScreenState extends State<MyScreen> with NavVisibilityMixin {
///   Widget build(_) => Scaffold(
///     body: NotificationListener<UserScrollNotification>(
///       onNotification: handleNavScroll,
///       child: ...,
///     ),
///     bottomNavigationBar:
///         HideOnScroll(visible: navVisible, child: MainBottomNav(...)),
///   );
/// }
/// ```
class HideOnScroll extends StatelessWidget {
  const HideOnScroll({super.key, required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: visible ? 1.0 : 0.0),
        duration: AppMotion.maybe(context, const Duration(milliseconds: 230)),
        curve: AppMotion.easeOut,
        builder: (context, t, inner) => Align(
          alignment: Alignment.topCenter,
          heightFactor: t,
          child: inner,
        ),
        child: child,
      ),
    );
  }
}

/// Scroll-direction → nav visibility state. Cheap: only rebuilds when
/// visibility actually flips, never per scroll frame.
mixin NavVisibilityMixin<T extends StatefulWidget> on State<T> {
  bool navVisible = true;

  bool handleNavScroll(UserScrollNotification notification) {
    if (notification.depth != 0) return false;
    final direction = notification.direction;
    if (direction == ScrollDirection.reverse && navVisible) {
      setState(() => navVisible = false);
    } else if (direction == ScrollDirection.forward && !navVisible) {
      setState(() => navVisible = true);
    }
    return false;
  }
}
