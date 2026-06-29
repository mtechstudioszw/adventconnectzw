import 'package:flutter/material.dart';

import '../../models/youtube_video.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../cached_image.dart';
import '../youtube/youtube_video_card.dart';

/// Compact, collapsible "LIVE now" banner for the top of Home. Sits between
/// the header and the composer; renders nothing (zero height) when no
/// monitored channel is live. Tap → opens the live stream in the player.
class LiveBanner extends StatelessWidget {
  const LiveBanner({super.key, required this.live, required this.onTap});

  /// The currently-live video, or null (banner hides).
  final YoutubeVideo? live;
  final void Function(YoutubeVideo) onTap;

  @override
  Widget build(BuildContext context) {
    final v = live;
    if (v == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onTap(v),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.darkNavy, Color(0xFF1A2F5A)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 72,
                    height: 40,
                    child: v.thumbnailUrl != null
                        ? CachedImage(v.thumbnailUrl!, fit: BoxFit.cover)
                        : Container(color: Colors.black26),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const LivePill(compact: true),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              v.channelTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.labelSmall.copyWith(
                                color: AppColors.white.withValues(alpha: 0.8),
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        v.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.play_circle_fill,
                    color: AppColors.white, size: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
