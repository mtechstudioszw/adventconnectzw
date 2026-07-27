import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';

import '../../models/library_item_model.dart';
import '../../services/music_download_service.dart';
import '../../services/music_player_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../cached_image.dart';
import '../motion/pressable.dart';

/// A SINGLE track in the home feed.
///
/// Replaces the old `_HomeMusicStrip`, which crowded ten tracks into one
/// horizontal rail that scrolled past as a blur. Interleaved one at a time —
/// the same treatment Watch videos get — each track gets room to be seen,
/// and tapping play starts it in place instead of bouncing you to the
/// Library first.
class HomeMusicCard extends StatelessWidget {
  const HomeMusicCard({super.key, required this.item});

  final LibraryItem item;

  Future<void> _play(BuildContext context) async {
    HapticFeedback.mediumImpact();
    // Queue of one: the NowPlayingBar takes over from here, and it's mounted
    // on Home, so playback stays controllable without leaving the feed.
    await MusicPlayerService.instance.setQueueAndPlay([item], 0);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final cover = item.coverUrl ?? '';
    final author = (item.author ?? '').trim();
    final downloaded = MusicDownloadService.isDownloaded(item.id);

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpace.lg,
        vertical: AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.card(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Pressable(
        // Tapping the body opens the Music tab; the play button starts it
        // here. Two intents, two targets.
        onTap: () => context.pushNamed('library', extra: 4),
        pressedScale: 0.985,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Row(
            children: [
              Container(
                width: 68,
                height: 68,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  gradient: cover.isEmpty ? AppColors.primaryGradient : null,
                ),
                child: cover.isEmpty
                    ? const Icon(
                        Icons.music_note_rounded,
                        color: AppColors.white,
                        size: 30,
                      )
                    : CachedImage(
                        cover,
                        fit: BoxFit.cover,
                        width: 68,
                        height: 68,
                        errorBuilder: (_, _, _) => const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                          ),
                          child: Icon(
                            Icons.music_note_rounded,
                            color: AppColors.white,
                            size: 30,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.headphones_rounded,
                          size: 12,
                          color: AppColors.primaryBlue,
                        ),
                        const SizedBox(width: AppSpace.xs + 1),
                        Text(
                          'MUSIC',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.primaryBlue,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                          ),
                        ),
                        if (downloaded) ...[
                          const SizedBox(width: AppSpace.sm),
                          Icon(
                            Icons.download_done_rounded,
                            size: 13,
                            color: AppColors.successGreen,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall.copyWith(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    if (author.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Semantics(
                button: true,
                label: 'Play ${item.title}',
                child: Pressable(
                  onTap: () => _play(context),
                  pressedScale: 0.88,
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryBlue.withValues(alpha: 0.32),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: AppColors.white,
                      size: 26,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
