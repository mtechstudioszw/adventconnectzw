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
/// ## Why this is a Stack and no longer a Column
///
/// Both windows are draggable now, so neither has a fixed slot to stack in.
/// Each owns its own parked anchor and floats independently. They can be live
/// at the same time (a docked sermon and a hymn), and they can be parked in
/// the same corner — that is the user's choice to make and undo, and forcing
/// them apart would mean one of them ignoring where it was put.
class GlobalMediaBars extends StatelessWidget {
  const GlobalMediaBars({super.key});

  /// Clears the floating island on the five tab destinations.
  static const double _islandInset = 96;

  /// Every other route has no island, so the windows sit near the edge.
  static const double _plainInset = AppSpace.md;

  static const _tabPaths = {
    '/home',
    '/watch',
    '/messages',
    '/marketplace',
    '/profile',
  };

  /// Where the music card is allowed to park. The founder asked for top,
  /// middle and bottom specifically; it stays horizontally centred because a
  /// 190dp card pinned to a side edge reads as something half off-screen.
  static final List<Alignment> _musicAnchors = [
    const Alignment(0, -1),
    const Alignment(0, 0),
    const Alignment(0, 1),
  ];

  /// Parked slot for the music card, held here rather than in State so it
  /// survives both the route-change rebuild below and the card being
  /// unmounted while the full player is open.
  static final ValueNotifier<Alignment> musicAnchor =
      ValueNotifier<Alignment>(const Alignment(0, 1));

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: MusicPlayerService.fullPlayerOpen,
      builder: (context, fullPlayerOpen, _) {
        return AnimatedBuilder(
          // The windows must re-inset when the route changes, otherwise one
          // parked at the bottom on Home keeps a 96dp gap on a screen with
          // no island.
          animation: appRouter.routerDelegate,
          builder: (context, _) {
            final path =
                appRouter.routerDelegate.currentConfiguration.uri.path;
            final inset =
                _tabPaths.contains(path) ? _islandInset : _plainInset;

            return Stack(
              children: [
                // The Watch window manages its own dock, including its size.
                const WatchMiniPlayer(),
                // The music card stands down while the full player is up, so
                // the two never render at once.
                if (!fullPlayerOpen)
                  FloatingDock(
                    size: NowPlayingBar.cardSize,
                    anchors: _musicAnchors,
                    anchor: musicAnchor,
                    margin: EdgeInsets.fromLTRB(
                      AppSpace.md,
                      // Clear of the status bar and of any header, so the
                      // top slot doesn't cover a screen title.
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
