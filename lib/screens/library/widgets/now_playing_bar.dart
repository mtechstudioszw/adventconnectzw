import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../config/router_config.dart';
import '../../../models/library_item_model.dart';
import '../../../services/music_player_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_text_styles.dart';
import 'full_player_screen.dart';
import 'music_visuals.dart';

/// Mini player for the Music tab.
///
/// Renders nothing when no queue is loaded, so it can be dropped at the bottom
/// of a tab without a layout guard. Tap (or swipe up) opens the full player.
///
/// **Scope:** this card is mounted ONLY inside the Music tab. Away from it —
/// other Library tabs, Home, or with the app closed — playback is controlled
/// from the Android media notification and the iOS lock screen / Control
/// Centre, which is where a music player is supposed to put those controls.
///
/// Stopping playback has an explicit ✕ button. Swipe-down still works, but a
/// gesture is not an affordance: there was previously no visible way to end
/// playback from here at all.
class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({super.key});

  @override
  Widget build(BuildContext context) {
    final service = MusicPlayerService.instance;
    // Rebuild on both track changes AND queue teardown (stop() clears the
    // queue without emitting a new index).
    return ValueListenableBuilder<int>(
      valueListenable: service.revision,
      builder: (context, _, _) {
        return StreamBuilder<int?>(
          stream: service.player.currentIndexStream,
          builder: (context, _) {
            final item = service.current;
            // AnimatedSize keeps the bar from popping in and shoving the list.
            return AnimatedSize(
              duration: AppMotion.standard,
              curve: AppMotion.ease,
              child: item == null
                  ? const SizedBox(width: double.infinity)
                  : _bar(context, service, item),
            );
          },
        );
      },
    );
  }

  Widget _bar(
    BuildContext context,
    MusicPlayerService service,
    LibraryItem item,
  ) {
    return Dismissible(
      key: const ValueKey('now-playing-bar'),
      direction: DismissDirection.down,
      // Swiping the bar away should stop audio, not just hide the widget —
      // a hidden-but-playing player is the worst of both worlds.
      onDismissed: (_) => service.stop(),
      child: GestureDetector(
        onVerticalDragEnd: (d) {
          if ((d.velocity.pixelsPerSecond.dy) < -260) _open(context);
        },
        child: Material(
          color: AppColors.darkNavy,
          child: InkWell(
            onTap: () => _open(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _progressLine(service),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                  child: Row(
                    children: [
                      Hero(
                        tag: 'now-playing-art',
                        child: TrackArtwork(
                          coverUrl: item.coverUrl,
                          size: 44,
                          radius: 10,
                          icon: item.kind == 'audio_bible'
                              ? Icons.menu_book_rounded
                              : Icons.music_note_rounded,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.labelMedium.copyWith(
                                color: AppColors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              (item.author?.isNotEmpty ?? false)
                                  ? item.author!
                                  : 'Advent Connect ZW',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.labelSmall.copyWith(
                                color:
                                    AppColors.white.withValues(alpha: 0.62),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      StreamBuilder<PlayerState>(
                        stream: service.player.playerStateStream,
                        builder: (context, snap) {
                          final state = snap.data;
                          final playing = state?.playing ?? false;
                          final loading = state?.processingState ==
                                  ProcessingState.loading ||
                              state?.processingState ==
                                  ProcessingState.buffering;
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Previous',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.skip_previous_rounded,
                                    color: AppColors.white, size: 26),
                                onPressed: service.previous,
                              ),
                              SizedBox(
                                width: 40,
                                height: 40,
                                child: loading
                                    ? const Padding(
                                        padding: EdgeInsets.all(10),
                                        child: CircularProgressIndicator(
                                          color: AppColors.white,
                                          strokeWidth: 2.2,
                                        ),
                                      )
                                    : IconButton(
                                        tooltip: playing ? 'Pause' : 'Play',
                                        visualDensity: VisualDensity.compact,
                                        icon: AnimatedSwitcher(
                                          duration: AppMotion.quick,
                                          transitionBuilder: (child, anim) =>
                                              ScaleTransition(
                                            scale: anim,
                                            child: child,
                                          ),
                                          child: Icon(
                                            playing
                                                ? Icons.pause_rounded
                                                : Icons.play_arrow_rounded,
                                            key: ValueKey(playing),
                                            color: AppColors.white,
                                            size: 30,
                                          ),
                                        ),
                                        onPressed: service.togglePlayPause,
                                      ),
                              ),
                              IconButton(
                                tooltip: 'Next',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.skip_next_rounded,
                                    color: AppColors.white, size: 26),
                                onPressed: service.next,
                              ),
                              // Ends playback and dismisses the bar. Stop, not
                              // pause: pausing leaves the card sitting there
                              // with no way to get rid of it.
                              IconButton(
                                tooltip: 'Stop',
                                visualDensity: VisualDensity.compact,
                                icon: Icon(
                                  Icons.close_rounded,
                                  color:
                                      AppColors.white.withValues(alpha: 0.75),
                                  size: 21,
                                ),
                                onPressed: service.stop,
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Hairline progress across the top of the bar — the cheapest possible
  /// "where am I in this track" signal.
  Widget _progressLine(MusicPlayerService service) {
    return StreamBuilder<Duration>(
      stream: service.player.positionStream,
      builder: (context, snap) {
        final duration = service.player.duration ?? Duration.zero;
        final position = snap.data ?? Duration.zero;
        final value = duration.inMilliseconds <= 0
            ? 0.0
            : (position.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0);
        return SizedBox(
          height: 2,
          child: LinearProgressIndicator(
            value: value,
            minHeight: 2,
            backgroundColor: AppColors.white.withValues(alpha: 0.14),
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppColors.goldAccent),
          ),
        );
      },
    );
  }

  void _open(BuildContext context) {
    // NOT Navigator.of(context): this bar is mounted in MaterialApp.builder,
    // above the router's Navigator, so there is no Navigator to find and the
    // lookup throws. Push on the root navigator directly.
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;
    nav.push(
      PageRouteBuilder<void>(
        transitionDuration: AppMotion.entrance,
        reverseTransitionDuration: AppMotion.standard,
        opaque: false,
        pageBuilder: (_, _, _) => const FullPlayerScreen(),
        transitionsBuilder: (context, animation, _, child) {
          // Slide up from the bar — the gesture and the transition agree.
          final curved = CurvedAnimation(
            parent: animation,
            curve: AppMotion.easeOut,
            reverseCurve: AppMotion.easeIn,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      ),
    );
  }
}
