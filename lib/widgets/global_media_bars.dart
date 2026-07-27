import 'package:flutter/material.dart';

import '../config/router_config.dart';
import '../screens/library/widgets/now_playing_bar.dart';
import '../services/music_player_service.dart';
import '../theme/app_tokens.dart';
import 'youtube/watch_mini_player.dart';

/// The app-wide stack of "something is still playing" bars, pinned to the
/// bottom above the navigation island.
///
/// Music used to lose its mini player the moment you left the Music tab,
/// on the reasoning that the Android media notification and the iOS lock
/// screen are where a music player puts its transport controls. In
/// practice people don't leave the app to pause it — they look at the
/// bottom of the screen, find nothing, and conclude the app has lost the
/// track. The founder asked for it everywhere; this is that.
///
/// Two bars can be live at once (a docked sermon and a hymn), so they
/// stack rather than competing for one slot.
class GlobalMediaBars extends StatelessWidget {
  const GlobalMediaBars({super.key});

  /// Clears the floating island on the five tab destinations.
  static const double _islandInset = 96;

  /// Every other route has no island, so the bars sit near the edge.
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
          // The bars must re-inset when the route changes, otherwise a bar
          // opened on Home keeps a 96dp gap on a screen with no island.
          animation: appRouter.routerDelegate,
          builder: (context, _) {
            final path =
                appRouter.routerDelegate.currentConfiguration.uri.path;
            final inset =
                _tabPaths.contains(path) ? _islandInset : _plainInset;

            return Padding(
              padding: EdgeInsets.only(bottom: inset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const WatchMiniPlayer(),
                  if (!fullPlayerOpen)
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpace.md,
                      ),
                      child: NowPlayingBar(),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
