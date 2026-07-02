import 'package:flutter/material.dart';

/// Motion tokens — every animation in the app reads its timing from here
/// so the whole product moves with one voice. If a screen needs a custom
/// duration, add a named token instead of inlining a number.
///
/// Ground rules (from the redesign brief):
/// * every animation is interruptible — prefer implicit widgets or
///   controller-driven tweens, never chained Futures that can't reverse;
/// * always consult [AppMotion.enabled] so users with "remove
///   animations" (MediaQuery.disableAnimations) get instant states;
/// * smooth beats fancy — if an effect can't hold 60fps on a mid-range
///   Android, simplify it.
class AppMotion {
  AppMotion._();

  // ---- Durations ---------------------------------------------------------

  /// Micro feedback: press-in of a tappable surface.
  static const Duration pressIn = Duration(milliseconds: 90);

  /// Spring-back after release (the brief's ~180ms).
  static const Duration pressOut = Duration(milliseconds: 180);

  /// Small state flips — icon swaps, chip selection, checkmarks.
  static const Duration quick = Duration(milliseconds: 200);

  /// Standard UI motion — crossfades, reveals, sheet content.
  static const Duration standard = Duration(milliseconds: 320);

  /// Entrances of whole sections / screens.
  static const Duration entrance = Duration(milliseconds: 420);

  /// Celebration moments (success ticks, completion states).
  static const Duration celebrate = Duration(milliseconds: 600);

  /// Gap between successive items in a staggered reveal.
  static const Duration stagger = Duration(milliseconds: 70);

  // ---- Curves ------------------------------------------------------------

  /// Default ease for anything entering the screen.
  static const Curve easeOut = Curves.easeOutCubic;

  /// Default ease for anything leaving the screen.
  static const Curve easeIn = Curves.easeInCubic;

  /// Symmetric ease for in-place morphs (size / color changes).
  static const Curve ease = Curves.easeInOutCubic;

  /// Playful overshoot for release/spring-back moments.
  static const Curve spring = Curves.easeOutBack;

  // ---- Accessibility -----------------------------------------------------

  /// True when animations should play. Honour the OS "remove animations"
  /// accessibility setting: when it's on, jump straight to end states.
  static bool enabled(BuildContext context) =>
      !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  /// [duration], or [Duration.zero] when animations are disabled — handy
  /// for implicit animated widgets.
  static Duration maybe(BuildContext context, Duration duration) =>
      enabled(context) ? duration : Duration.zero;
}
