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
/// What must NOT become transparent: modal sheets, dialogs, and headers
/// that content actually scrolls **under**. A sheet you can see the app
/// through reads as a rendering fault, and a pinned header that stops
/// occluding turns every list into a smear.
///
/// **That test is about pinning, not about being a header** (23 Aug 2026).
/// The rule was originally written as "headers stay opaque", and taken at
/// face value it produced a real bug: `ScreenHero` — and four hand-rolled
/// copies of it — painted an opaque `scaffoldBg` slab across the top of
/// every screen. The field underneath was full-screen the whole time; it
/// was simply covered, so the drifting particles appeared to begin 120-160px
/// down the page. Members reported it as "the background is cut off at the
/// top / not full screen like the splash".
///
/// So the question to ask of any surface is not "is this a header?" but
/// **"does anything scroll beneath it?"**:
///
///   - `SliverPersistentHeaderDelegate` / `AppBar` / anything stacked over a
///     list → **opaque**. Marketplace's category strip and Watch's pinned
///     header are the live examples; they were checked and left alone.
///   - An ordinary widget in the normal flow above a scroll view →
///     **transparent**. It occludes nothing, so the fill only ever hid the
///     field. `ScreenHero` now defaults this way and takes `opaque: true`
///     for the pinned case.
///
/// Only the *Scaffold* background was changed by the original migration.
/// Five screens keep their opaque Scaffold because they already paint this
/// same field themselves — the auth shell, both onboarding screens,
/// maintenance and chat (via `ChatWallpaper`); making those transparent
/// would stack two fields.
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

  /// The field's position in its cycle, shared so other surfaces can paint
  /// a matching one.
  ///
  /// A PINNED header cannot be transparent — content scrolls under it and
  /// would smear (see the class doc). But it does not have to paint flat
  /// `scaffoldBg` either, and that flat slab is why the founder still saw
  /// the field "cut off at the top" on Home after the ScreenHero fix: Home's
  /// header is a floating `SliverPersistentHeaderDelegate`, so it was
  /// correctly left opaque and correctly still looked like a lid.
  ///
  /// [AmbientFill] paints the same field, sized to the whole screen and
  /// clipped to whatever box it is given, so the strip behind the header is
  /// literally the top strip of the field behind the page. Driving both from
  /// this one notifier is what keeps them in step — two independent timers
  /// would drift apart within seconds and the seam would be worse than the
  /// slab it replaced.
  static final ValueNotifier<double> loop = ValueNotifier<double>(0);

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground> {
  /// Drives the painter. A ValueNotifier + ValueListenableBuilder rather
  /// than setState so only the CustomPaint rebuilds, never [widget.child]
  /// — which is the entire app.
  ///
  /// This is [AmbientBackground.loop], not a private instance field, so
  /// [AmbientFill] can paint a field that stays in step with this one.
  ValueNotifier<double> get _loop => AmbientBackground.loop;
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
    // NOT disposed: [AmbientBackground.loop] is static and shared with
    // AmbientFill. This widget is installed once in MaterialApp.builder and
    // lives for the whole session, but disposing a static notifier would
    // leave any surviving listener calling a dead object.
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

/// An opaque surface that paints the app's ambient field instead of a flat
/// colour, aligned to the field behind the page.
///
/// ## Why this exists
///
/// The particle field sits behind the whole app, and the fix for "the
/// background is cut off at the top" was to stop headers painting an opaque
/// `scaffoldBg` slab over it. That works for headers in the normal flow.
///
/// It does NOT work for a pinned or floating `SliverPersistentHeaderDelegate`
/// — Home's header is one — because content genuinely scrolls underneath and
/// a transparent header would smear the feed through itself. So those were
/// left opaque, and on Home the field still stopped dead below the header.
///
/// This resolves the conflict rather than trading one bug for the other: the
/// surface stays fully opaque, so it occludes exactly as before, but what it
/// paints is the field itself.
///
/// ## The alignment trick
///
/// [AmbientPainter] lays its blobs out relative to the canvas it is given, so
/// painting it into a 160px-tall header would show the *whole* field squashed
/// into that strip — a visibly different image from the one behind the page,
/// which is worse than the slab.
///
/// Instead the painter is given the FULL SCREEN height, top-aligned, and the
/// whole thing is clipped to this widget's own box. What shows is therefore
/// the literal top strip of the same field, in the same place, at the same
/// scale — so the header reads as a window onto the background rather than a
/// separate surface sitting on it.
///
/// Both are driven by [AmbientBackground.loop], so they never drift apart.
class AmbientFill extends StatelessWidget {
  const AmbientFill({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // The screen, not this widget's box — see the alignment note above.
    final screen = MediaQuery.sizeOf(context);

    return ClipRect(
      child: Stack(
        children: [
          // The opaque ground, so this surface still occludes whatever
          // scrolls beneath it. Without this the ClipRect would show the
          // feed through the gaps between blobs.
          Positioned.fill(child: ColoredBox(color: palette.scaffoldBg)),
          Positioned(
            top: 0,
            left: 0,
            width: screen.width,
            height: screen.height,
            child: IgnorePointer(
              child: RepaintBoundary(
                child: ValueListenableBuilder<double>(
                  valueListenable: AmbientBackground.loop,
                  builder: (context, loop, _) => CustomPaint(
                    painter: AmbientPainter(loop: loop, film: 0, dark: dark),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
          ?child,
        ],
      ),
    );
  }
}
