import 'dart:async';

import 'package:flutter/material.dart';

import '../screens/onboarding/widgets/film_scenes.dart' show AmbientPainter;
import '../theme/app_palette.dart';

/// The drifting particle field from the splash, behind the whole app.
///
/// Installed once in `MaterialApp.builder` (see main.dart) so it sits under
/// the router's Navigator: pages slide over a field that stays put, which is
/// what makes it read as the app's ground rather than as decoration on one
/// screen. Founder's call, 18 Aug 2026 — the splash background was the look
/// they wanted everywhere.
///
/// **This widget paints the opaque ground.** [AmbientPainter] draws only
/// translucent blobs, ghost rectangles and dust; it has no base of its own.
/// That is why every Scaffold above it is `Colors.transparent` — the colour
/// those Scaffolds used to paint (`palette.scaffoldBg`) is painted here
/// instead, once, for the whole app.
///
/// What must NOT become transparent: headers, modal sheets and dialogs.
/// `ScreenHero` and friends rely on `palette.scaffoldBg` to occlude content
/// scrolling underneath them (CLAUDE.md's flat-header rule), and a sheet you
/// can see the app through reads as a rendering fault. Only the *Scaffold*
/// background was changed. Five screens keep their opaque Scaffold because
/// they already paint this same field themselves — the auth shell, both
/// onboarding screens, maintenance and chat (via `ChatWallpaper`); making
/// those transparent would stack two fields.
class AmbientBackground extends StatefulWidget {
  const AmbientBackground({super.key, required this.child});

  final Widget child;

  /// How often the field is re-drawn.
  ///
  /// **Not 60fps, on purpose.** `ChatWallpaper` pins its copy of this
  /// painter to a single frame with the note that a full-screen animated
  /// CustomPaint under a flung list repaints the viewport every frame — and
  /// that objection applies far harder here, where the field is under
  /// *every* screen for the whole session. Much of this app's audience is
  /// on mid-range Android.
  ///
  /// The drift is a 14-second loop of soft blobs, so ~15fps is
  /// indistinguishable from 60 and costs a quarter as much. If the motion
  /// ever looks steppy, raise this before reaching for a shorter loop.
  static const Duration frameInterval = Duration(milliseconds: 66);

  /// One full drift cycle. Matches the splash's own loop so a cold start
  /// hands over without the motion changing speed.
  static const Duration loopDuration = Duration(seconds: 14);

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground> {
  /// Drives the painter. A ValueNotifier + ValueListenableBuilder rather
  /// than setState so only the CustomPaint rebuilds, never [widget.child]
  /// — which is the entire app.
  final ValueNotifier<double> _loop = ValueNotifier<double>(0);
  Timer? _timer;

  /// Frozen for "reduce motion". Read in [didChangeDependencies], not in
  /// `build` — starting and stopping a Timer from build is a side effect
  /// that fires again on every unrelated rebuild.
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still == _still && (_timer != null || still)) return;
    _still = still;
    _timer?.cancel();
    _timer = null;
    if (!still) _start();
  }

  void _start() {
    final steps =
        AmbientBackground.loopDuration.inMilliseconds /
        AmbientBackground.frameInterval.inMilliseconds;
    _timer = Timer.periodic(AmbientBackground.frameInterval, (_) {
      // Wraps at 1.0 — AmbientPainter treats `loop` as 0→1 repeating.
      _loop.value = (_loop.value + 1 / steps) % 1.0;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        // The opaque ground the painter needs, and the colour every
        // Scaffold used to paint for itself.
        Positioned.fill(child: ColoredBox(color: palette.scaffoldBg)),
        // RepaintBoundary is load-bearing, not a micro-optimisation:
        // without it a repaint of this always-animating painter walks up
        // into the whole app tree.
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: ValueListenableBuilder<double>(
                valueListenable: _loop,
                builder: (context, loop, _) => CustomPaint(
                  painter: AmbientPainter(
                    // A fixed, pleasant frame when motion is off — the same
                    // field, just not moving.
                    loop: _still ? 0.22 : loop,
                    // No film here. `film` is the onboarding reel's master
                    // position, used to pan the lights with the story;
                    // outside that reel there is no story to follow, so
                    // the field just breathes in place.
                    film: 0,
                    dark: dark,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}
