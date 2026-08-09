import 'package:flutter/material.dart';

import '../config/router_config.dart';
import '../screens/library/widgets/now_playing_bar.dart';
import '../services/music_player_service.dart';
import '../theme/app_tokens.dart';
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
/// ## The two windows behave differently on purpose
///
/// The Watch window is a floating, draggable, resizable 16:9 picture — you
/// are watching it, so it has to be movable out of the way of whatever you
/// are reading underneath.
///
/// The music bar is not. It is docked to the bottom edge, full width, above
/// the navigation island, the way YouTube Music and Spotify dock theirs.
/// Music has nothing to look at, so a window that can sit anywhere buys the
/// member nothing and costs them a chore: a 172dp card parked mid-screen
/// covers content on every screen until it is picked up and moved again.
/// One edge, always the same edge, covering nothing.
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

            return Stack(
              children: [
                // The Watch window manages its own dock, including its size.
                const WatchMiniPlayer(),
                // The music bar stands down while the full player is up, so
                // the two never render at once.
                if (!fullPlayerOpen)
                  Positioned(
                    left: AppSpace.md,
                    right: AppSpace.md,
                    bottom: inset,
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
