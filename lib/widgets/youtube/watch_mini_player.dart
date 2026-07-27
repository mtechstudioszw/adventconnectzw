import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../config/router_config.dart';
import '../../services/mini_player_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../motion/pressable.dart';

/// The docked bar that keeps a sermon playing while you browse.
///
/// Mounted inside [GlobalMediaBars], which owns the bottom inset and the
/// stacking with the music bar. Swipe it down or tap the cross to close;
/// tap the body to go back to the full player at the exact second it
/// reached.
class WatchMiniPlayer extends StatelessWidget {
  const WatchMiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = MiniPlayerService.instance;
    return AnimatedBuilder(
      animation: svc,
      builder: (context, _) {
        final show = svc.isActive && !svc.isExpanding;
        return AnimatedSwitcher(
          duration: AppMotion.maybe(context, AppMotion.standard),
          switchInCurve: AppMotion.easeOut,
          switchOutCurve: AppMotion.easeIn,
          transitionBuilder: (child, animation) => SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(animation),
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: !show
              ? const SizedBox.shrink()
              : Padding(
                  key: ValueKey(svc.video?.videoId),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.md,
                  ),
                  child: _Bar(service: svc),
                ),
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.service});

  final MiniPlayerService service;

  Future<void> _expand() async {
    final video = service.video;
    if (video == null) return;
    // takeOver() persists the position and tears the bar down, so the
    // player screen's own resume read lands on the right second.
    await service.takeOver();
    appRouter.pushNamed(
      'watch_video',
      pathParameters: {'id': video.videoId},
      extra: video,
    );
  }

  @override
  Widget build(BuildContext context) {
    final video = service.video;
    final controller = service.controller;
    if (video == null || controller == null) return const SizedBox.shrink();

    final playing = controller.value.playerState == PlayerState.playing;

    return Dismissible(
      key: ValueKey('mini-${video.videoId}'),
      direction: DismissDirection.down,
      onDismissed: (_) => service.close(),
      child: Material(
        color: Colors.transparent,
        child: Pressable(
          onTap: _expand,
          pressedScale: 0.985,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.darkNavy,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: AppColors.white.withValues(alpha: 0.12),
              ),
              boxShadow: AppShadows.floating(context),
            ),
            child: Row(
              children: [
                // The live player itself, at thumbnail size.
                SizedBox(
                  width: 92,
                  height: 92 * 9 / 16,
                  child: IgnorePointer(
                    // Taps belong to the bar (expand), not to the embed.
                    child: YoutubePlayer(
                      controller: controller,
                      aspectRatio: 16 / 9,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        video.channelTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.white.withValues(alpha: 0.62),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: playing ? 'Pause' : 'Play',
                  onPressed: service.togglePlay,
                  icon: Icon(
                    playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: AppColors.white,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: service.close,
                  icon: Icon(
                    Icons.close_rounded,
                    color: AppColors.white.withValues(alpha: 0.7),
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
