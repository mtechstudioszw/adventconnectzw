import 'package:flutter/material.dart';

import '../../models/youtube_video.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../cached_image.dart';

/// A red "LIVE" pill with a gentle pulse — used on hero, banner and cards.
class LivePill extends StatefulWidget {
  const LivePill({super.key, this.label = 'LIVE', this.compact = false});
  final String label;
  final bool compact;

  @override
  State<LivePill> createState() => _LivePillState();
}

class _LivePillState extends State<LivePill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = widget.compact
        ? const EdgeInsets.symmetric(horizontal: 7, vertical: 3)
        : const EdgeInsets.symmetric(horizontal: 9, vertical: 4);
    return Container(
      padding: pad,
      decoration: BoxDecoration(
        color: AppColors.red,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween<double>(begin: 0.35, end: 1).animate(_c),
            child: Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: AppColors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            widget.label,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.white,
              fontWeight: FontWeight.w800,
              fontSize: widget.compact ? 9.5 : 11,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// 16:9 thumbnail with rounded corners, a bottom scrim, and either a
/// duration pill or a LIVE pill. Shared by every video surface.
class YoutubeThumbnail extends StatelessWidget {
  const YoutubeThumbnail({
    super.key,
    required this.video,
    this.radius = 16,
    this.showPlay = true,
  });

  final YoutubeVideo video;
  final double radius;
  final bool showPlay;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (video.thumbnailUrl != null)
              CachedImage(video.thumbnailUrl!, fit: BoxFit.cover)
            else
              Container(color: context.palette.cardMuted),
            // Bottom scrim for legibility of the pill.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0x73000000)],
                ),
              ),
            ),
            if (showPlay)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.42),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: AppColors.white, size: 26),
                ),
              ),
            Positioned(
              left: 8,
              top: 8,
              child: video.isLive
                  ? const LivePill()
                  : video.isUpcoming
                      ? _Pill(_scheduleLabel(video), icon: Icons.schedule)
                      : const SizedBox.shrink(),
            ),
            if (!video.isLive && video.durationLabel.isNotEmpty)
              Positioned(
                right: 8,
                bottom: 8,
                child: _Pill(video.durationLabel),
              ),
          ],
        ),
      ),
    );
  }

  static String _scheduleLabel(YoutubeVideo v) {
    final t = v.scheduledStartAt;
    if (t == null) return 'UPCOMING';
    final d = t.difference(DateTime.now());
    if (d.inDays >= 1) return 'In ${d.inDays}d';
    if (d.inHours >= 1) return 'In ${d.inHours}h';
    if (d.inMinutes >= 1) return 'In ${d.inMinutes}m';
    return 'Starting';
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.icon});
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.darkNavy.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: AppColors.white),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.white,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// Subtle press-scale wrapper for a premium tactile feel.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// The big, full-width feed card (Home feed, Watch infinite list, search).
class YoutubeVideoCard extends StatelessWidget {
  const YoutubeVideoCard({
    super.key,
    required this.video,
    required this.onTap,
    this.saved = false,
    this.onSaveToggle,
    this.thumbnailOverlay,
  });

  final YoutubeVideo video;
  final VoidCallback onTap;
  final bool saved;
  final VoidCallback? onSaveToggle;

  /// Optional overlay painted over the thumbnail (e.g. the in-feed
  /// auto-preview player). When null, the static thumbnail shows.
  final Widget? thumbnailOverlay;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return _Pressable(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            thumbnailOverlay ??
                YoutubeThumbnail(video: video, radius: 0),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 8, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ChannelAvatar(url: video.channelThumbUrl, size: 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          video.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.titleMedium.copyWith(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: palette.text,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _meta(video),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: palette.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onSaveToggle != null)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: saved ? 'Saved' : 'Save',
                      icon: Icon(
                        saved ? Icons.bookmark : Icons.bookmark_border,
                        color: saved ? AppColors.primaryBlue : palette.textMuted,
                        size: 22,
                      ),
                      onPressed: onSaveToggle,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _meta(YoutubeVideo v) {
    final parts = <String>[
      if (v.channelTitle.isNotEmpty) v.channelTitle,
      if (v.isLive) 'LIVE' else if (v.publishedLabel.isNotEmpty) v.publishedLabel,
      if (!v.isLive && v.viewsLabel.isNotEmpty) v.viewsLabel,
    ];
    return parts.join('  ·  ');
  }
}

/// Compact fixed-width card for horizontal rails (Continue watching,
/// Upcoming, Up next).
class YoutubeRailCard extends StatelessWidget {
  const YoutubeRailCard({
    super.key,
    required this.video,
    required this.onTap,
    this.width = 208,
    this.progress,
  });

  final YoutubeVideo video;
  final VoidCallback onTap;
  final double width;

  /// 0–1 resume progress bar (Continue watching). Null hides it.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return _Pressable(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                YoutubeThumbnail(video: video),
                if (progress != null)
                  Positioned(
                    left: 6,
                    right: 6,
                    bottom: 6,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress!.clamp(0, 1),
                        minHeight: 4,
                        backgroundColor: Colors.white.withValues(alpha: 0.35),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.primaryBlue,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              video.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleMedium.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: palette.text,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              video.channelTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall
                  .copyWith(color: palette.textMuted, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelAvatar extends StatelessWidget {
  const _ChannelAvatar({required this.url, this.size = 36});
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: url != null
            ? CachedImage(url!, fit: BoxFit.cover)
            : Container(
                color: context.palette.cardMuted,
                child: Icon(Icons.tv_rounded,
                    size: size * 0.5, color: context.palette.textMuted),
              ),
      ),
    );
  }
}
