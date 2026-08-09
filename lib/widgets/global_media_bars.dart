import 'package:flutter/material.dart';

import '../config/router_config.dart';
import '../screens/library/widgets/now_playing_bar.dart';
import '../services/music_player_service.dart';
import '../theme/app_tokens.dart';
import 'media/floating_dock.dart';
import 'youtube/watch_mini_player.dart';

/// The app-wide layer of "something is still playing" windows.
///
/// Music used to lose its mini player the moment you left the Music tab, on
/// the reasoning that the Android media notification and the iOS lock screen
/// are where a music player puts its transport controls. In practice people
/// don't leave the app to pause it — they look at the screen, find nothing,
/// and conclude the app has lost the track. The founder asked for it
/// everywhere; this is that.
///
/// ## Both windows float, and both can be moved
///
/// The Watch window is a draggable, resizable 16:9 picture — you are watching
/// it, so it has to be movable out of the way of whatever is underneath.
///
/// The music card is draggable too. It spent one release docked to the bottom
/// edge on the argument that music has nothing to look at, so a window that
/// can sit anywhere only creates a chore. The founder overruled that twice,
/// and they are right about their own app: the bottom edge is exactly where
/// this app puts its navigation island, its snackbars and its send buttons,
/// so "always the same edge" means "always in the way of the same things".
/// It parks at the nearest of nine slots and stays there across screens.
///
/// Neither window may sit on top of a full-screen player — see the early
/// return in `build`.
class GlobalMediaBars extends StatelessWidget {
  const GlobalMediaBars({super.key});

  /// Clears the floating island on the five tab destinations.
  static const double _islandInset = 96;

  /// Every other route has no island, so the bar sits near the edge.
  static const double _plainInset = AppSpace.md;

  static const _tabPaths = {
    '/home',
    '/watch',
    '/messages',
    '/marketplace',
    '/profile',
  };

  /// Every slot the music card may park in.
  ///
  /// It was three (top / middle / bottom, always centred) when the card could
  /// only move vertically. The founder asked for it to go anywhere on screen
  /// (9 Aug 2026), so the corners and sides are in as well — a card parked
  /// bottom-right leaves the middle of the page clear, which is the point of
  /// being able to move it at all.
  static final List<Alignment> _musicAnchors = [
    for (final y in const [-1.0, 0.0, 1.0])
      for (final x in const [-1.0, 0.0, 1.0]) Alignment(x, y),
  ];

  /// Parked slot, held statically rather than in State so it survives both
  /// the route-change rebuild below and the card being unmounted while the
  /// full player is open. Put it somewhere and it stays there.
  static final ValueNotifier<Alignment> musicAnchor =
      ValueNotifier<Alignment>(const Alignment(0, 1));

  /// The card's size.
  ///
  /// A dragged window has to be a card, not a full-bleed bar: a bar spanning
  /// the whole width has nowhere left to go horizontally, so "drag it out of
  /// the way" can only ever mean up or down. Capped at 380 so it stays a
  /// window on a tablet instead of a stripe.
  static Size cardSize(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width - AppSpace.md * 2;
    return Size(width.clamp(240.0, 380.0), NowPlayingBar.barHeight + 4);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: MusicPlayerService.fullPlayerOpen,
      builder: (context, fullPlayerOpen, _) {
        return AnimatedBuilder(
          // The bar must re-inset when the route changes, otherwise it keeps
          // a 96dp gap under it on a screen with no navigation island.
          animation: appRouter.routerDelegate,
          builder: (context, _) {
            final path = appRouter.routerDelegate.currentConfiguration.uri.path;
            final inset = _tabPaths.contains(path)
                ? _islandInset
                : _plainInset + MediaQuery.paddingOf(context).bottom;

            // BOTH windows stand down while the full music player is up.
            //
            // The music bar always did. The Watch window did not, and this
            // whole layer paints ABOVE the router's Navigator — so a docked
            // video floated over the full-screen player, which is what the
            // founder reported as "the mini player is still there in the full
            // player" (9 Aug 2026). It was the video window, not the music
            // bar. Nothing may sit on top of a deliberately full-screen
            // player; it comes back when you leave.
            if (fullPlayerOpen) return const SizedBox.shrink();

            return Stack(
              children: [
                // The Watch window manages its own dock, including its size.
                const WatchMiniPlayer(),
                // Draggable again. It parks at the nearest slot on release
                // and keeps that slot across screens, so moving it off
                // something is a decision you make once.
                FloatingDock(
                  size: cardSize(context),
                  anchors: _musicAnchors,
                  anchor: musicAnchor,
                  margin: EdgeInsets.fromLTRB(
                    AppSpace.md,
                    // Clear of the status bar and any screen header, so the
                    // top slots do not cover a title.
                    MediaQuery.paddingOf(context).top + AppSpace.sm,
                    AppSpace.md,
                    inset,
                  ),
                  child: const NowPlayingBar(),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
