import 'package:flutter/material.dart';

import '../screens/onboarding/widgets/film_scenes.dart' show AmbientPainter;
import '../theme/app_palette.dart';

/// The chat's background — the *same* light the splash screen opens on.
///
/// This used to be a bespoke doodle field (rings, crosses, sparkles) drawn
/// only behind the message list, so it began under the header and ended
/// above the composer: two hard seams across the screen, which is the
/// reported "cut off". It is now [AmbientPainter] — the field the splash,
/// the onboarding film, AuthShell, maintenance and the create sheet all
/// share — painted edge to edge behind the entire chat, header and
/// composer included.
///
/// `film: 0` is the painter's opening position, which is exactly the frame
/// the splash holds while the gold ring closes. Opening a chat therefore
/// lands on light the member has already seen on this launch.
///
/// **Deliberately static.** The other five surfaces drive `loop` from a
/// ~14s controller, but they are all short-lived or have nothing scrolling
/// over them. A chat stays open for minutes with a list being flung above
/// it, and a full-screen animated CustomPaint underneath that is a repaint
/// of the whole viewport every frame. One fixed frame is visually identical
/// to the splash's and costs nothing — the `shouldRepaint` below is `false`
/// except on a theme flip.
class ChatWallpaper extends StatelessWidget {
  const ChatWallpaper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      // The painter draws light ONTO a ground; it has no opaque base of
      // its own. Without this the field would sit on whatever is behind
      // the Scaffold and read as washed-out grey.
      decoration: BoxDecoration(color: context.palette.scaffoldBg),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _ChatAmbient(dark: dark),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Thin wrapper that pins [AmbientPainter] to a single frame and reports
/// `shouldRepaint` only when the palette flips.
class _ChatAmbient extends CustomPainter {
  _ChatAmbient({required this.dark});

  final bool dark;

  late final AmbientPainter _inner = AmbientPainter(
    loop: 0,
    film: 0,
    dark: dark,
  );

  @override
  void paint(Canvas canvas, Size size) => _inner.paint(canvas, size);

  @override
  bool shouldRepaint(_ChatAmbient old) => old.dark != dark;
}
