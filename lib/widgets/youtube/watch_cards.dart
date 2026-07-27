import 'package:flutter/material.dart';

import '../../models/youtube_channel.dart';
import '../../models/youtube_playlist.dart';
import '../../models/youtube_video.dart';
import '../../services/youtube_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../cached_image.dart';
import '../motion/pressable.dart';

/// The Watch tab's card family.
///
/// The old tab drew Continue watching, Live now and Upcoming as three
/// identical 168dp rails of the same card. They are three different
/// ideas — progress, urgency, anticipation — and looking alike is what
/// made the screen read as one undifferentiated scroll. Each one now has
/// its own shape:
///
/// * [ResumeCard]      — wide, with a progress bar and time REMAINING.
/// * [SeriesCard]      — square artwork, because a series is a box set.
/// * [ContinueSeriesCard] — a banner: "Episode 4 of 36".
/// * [ShortCard]       — 9:16, the format's own aspect ratio.
/// * [ChannelRing]     — a circle, red-ringed when that channel is live.
/// * [UpcomingCard]    — a date block and a countdown.
///
/// All of them share the visual vocabulary set by the Home LIVE deck
/// (lib/widgets/home/live_banner.dart): full-bleed media, a scrim that
/// darkens only where text sits, glass chips, and a glass play glyph.

// ---------------------------------------------------------------- shared

/// Translucent navy chip with a hairline border — the same treatment the
/// Home LIVE deck uses for its viewer count.
class GlassChip extends StatelessWidget {
  const GlassChip({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.darkNavy.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: AppColors.white),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.white,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// The glass play glyph from the Home LIVE deck, sized for rail cards.
class PlayGlyph extends StatelessWidget {
  const PlayGlyph({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.white.withValues(alpha: 0.55)),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.play_arrow_rounded,
        color: AppColors.white,
        size: size * 0.58,
      ),
    );
  }
}

/// Media placeholder that keeps the brand's navy instead of flashing grey.
class ThumbFallback extends StatelessWidget {
  const ThumbFallback({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.darkNavy, Color(0xFF1A2F5A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }
}

/// Scrim used over every piece of thumbnail art: dark at the top so a
/// pill reads, clear through the middle so the frame is visible, dark at
/// the bottom so a label reads.
class MediaScrim extends StatelessWidget {
  const MediaScrim({super.key, this.topAlpha = 0x59, this.bottomAlpha = 0x9E});

  final int topAlpha;
  final int bottomAlpha;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color((topAlpha << 24) | 0x0D1B3E),
            const Color(0x140D1B3E),
            Color((bottomAlpha << 24) | 0x0D1B3E),
          ],
          stops: const [0, 0.45, 1],
        ),
      ),
    );
  }
}

/// Section heading for a rail. One weight, one rhythm, everywhere.
class WatchSectionHeader extends StatelessWidget {
  const WatchSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.icon,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.xl,
        AppSpace.lg,
        AppSpace.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: AppColors.primaryBlue),
            const SizedBox(width: AppSpace.sm),
          ],
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w800,
                color: palette.text,
                letterSpacing: -0.2,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            Pressable(
              onTap: onAction,
              pressedScale: 0.94,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.xs,
                  vertical: 2,
                ),
                child: Row(
                  children: [
                    Text(
                      actionLabel!,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.primaryBlue,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ keep watching

/// A part-watched video. Leads with **time remaining**, not runtime —
/// "18 min left" is the number that decides whether you tap; "47:09"
/// isn't. Swipe up to drop it from the rail.
class ResumeCard extends StatelessWidget {
  const ResumeCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onDismiss,
    this.width = 210,
    this.showProgress = true,
  });

  final ResumeItem item;
  final VoidCallback onTap;
  final VoidCallback? onDismiss;
  final double width;

  /// False when the card is a recommendation rather than a resume — the
  /// Sabbath lineup borrows this shape but has no position to report, and
  /// "47 min left" on something you have never opened is a lie.
  final bool showProgress;

  /// "18 min left" / "40 sec left" while resuming; plain runtime otherwise.
  String get _label {
    if (!showProgress) return item.video.durationLabel;
    final left = item.durationSeconds - item.positionSeconds;
    if (item.durationSeconds <= 0 || left <= 0) return 'Resume';
    if (left < 60) return '$left sec left';
    final mins = (left / 60).round();
    if (mins < 60) return '$mins min left';
    final h = left ~/ 3600;
    final m = (left % 3600) ~/ 60;
    return m == 0 ? '${h}h left' : '${h}h ${m}m left';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final video = item.video;
    final thumb = video.thumbnailUrl;

    final card = Pressable(
      onTap: onTap,
      pressedScale: 0.97,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (thumb != null && thumb.isNotEmpty)
                      CachedImage(
                        thumb,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const ThumbFallback(),
                      )
                    else
                      const ThumbFallback(),
                    const MediaScrim(topAlpha: 0x33),
                    const Center(child: PlayGlyph(size: 34)),
                    if (_label.isNotEmpty)
                      Positioned(
                        left: AppSpace.sm,
                        bottom: showProgress ? AppSpace.md : AppSpace.sm,
                        child: GlassChip(
                          label: _label,
                          icon: showProgress
                              ? Icons.play_circle_outline_rounded
                              : null,
                        ),
                      ),
                    // The resume bar sits flush to the bottom edge, the
                    // way a scrubber does — it reads as position in the
                    // video rather than as decoration on the card.
                    if (showProgress)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _ProgressBar(value: item.progress),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              video.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w700,
                color: palette.text,
                height: 1.25,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              video.channelTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(color: palette.textMuted),
            ),
          ],
        ),
      ),
    );

    if (onDismiss == null) return card;
    return Dismissible(
      key: ValueKey('resume-${video.videoId}'),
      direction: DismissDirection.up,
      onDismissed: (_) => onDismiss!(),
      child: card,
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 4,
      child: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: AppColors.white.withValues(alpha: 0.30),
            ),
          ),
          FractionallySizedBox(
            widthFactor: value.clamp(0.02, 1.0),
            child: const ColoredBox(color: AppColors.red),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ series

/// A series as a box set: square artwork, episode count, title beneath.
class SeriesCard extends StatelessWidget {
  const SeriesCard({
    super.key,
    required this.playlist,
    required this.onTap,
    this.width = 138,
  });

  final YoutubePlaylist playlist;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final thumb = playlist.thumbnailUrl;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.97,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: AspectRatio(
                // Square, so a series never gets mistaken for a video.
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (thumb != null && thumb.isNotEmpty)
                      CachedImage(
                        thumb,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const ThumbFallback(),
                      )
                    else
                      const ThumbFallback(),
                    const MediaScrim(topAlpha: 0x1A),
                    if (playlist.itemCount > 0)
                      Positioned(
                        left: AppSpace.sm,
                        bottom: AppSpace.sm,
                        child: GlassChip(
                          label: '${playlist.itemCount} parts',
                          icon: Icons.playlist_play_rounded,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              playlist.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w700,
                color: palette.text,
                height: 1.25,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Episode 4 of 36" — the single most bingeable thing the library can
/// say. Full-width banner so it outranks the rails around it.
class ContinueSeriesCard extends StatelessWidget {
  const ContinueSeriesCard({
    super.key,
    required this.progress,
    required this.onTap,
  });

  final SeriesProgress progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final playlist = progress.playlist;
    final thumb = playlist.thumbnailUrl;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
      child: Pressable(
        onTap: onTap,
        pressedScale: 0.98,
        child: Container(
          padding: const EdgeInsets.all(AppSpace.sm + 2),
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: AppColors.primaryBlue.withValues(alpha: 0.20),
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: SizedBox(
                  width: 92,
                  height: 92 * 9 / 16,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (thumb != null && thumb.isNotEmpty)
                        CachedImage(
                          thumb,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const ThumbFallback(),
                        )
                      else
                        const ThumbFallback(),
                      const MediaScrim(topAlpha: 0x1A, bottomAlpha: 0x66),
                      const Center(child: PlayGlyph(size: 26)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      playlist.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w800,
                        color: palette.text,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      progress.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress.progress,
                        minHeight: 4,
                        backgroundColor:
                            AppColors.primaryBlue.withValues(alpha: 0.18),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.primaryBlue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ shorts

/// A one-minute clip at its own aspect ratio. 9:16 is the whole point —
/// squeezing a short into a 16:9 rail is what makes other apps' shorts
/// feel like an afterthought.
class ShortCard extends StatelessWidget {
  const ShortCard({
    super.key,
    required this.video,
    required this.onTap,
    this.width = 116,
  });

  final YoutubeVideo video;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final thumb = video.thumbnailUrl;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.96,
      child: SizedBox(
        width: width,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: AspectRatio(
            aspectRatio: 9 / 16,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (thumb != null && thumb.isNotEmpty)
                  CachedImage(
                    thumb,
                    // Shorts thumbnails are delivered 16:9 with the clip
                    // letterboxed inside, so cover-cropping to 9:16 is
                    // what recovers the vertical frame.
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ThumbFallback(),
                  )
                else
                  const ThumbFallback(),
                const MediaScrim(topAlpha: 0x26, bottomAlpha: 0xB3),
                Positioned(
                  left: AppSpace.sm,
                  right: AppSpace.sm,
                  bottom: AppSpace.sm,
                  child: Text(
                    video.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
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

// ---------------------------------------------------------------- channels

/// A channel as a circle, ringed in red while it is live. Borrowed from
/// the story-ring pattern because it does the same job: it tells you at a
/// glance which of these has something happening right now.
class ChannelRing extends StatelessWidget {
  const ChannelRing({
    super.key,
    required this.channel,
    required this.onTap,
    this.size = 58,
  });

  final YoutubeChannel channel;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final url = channel.thumbnailUrl;
    final letter = channel.title.trim().isEmpty
        ? '?'
        : channel.title.trim().substring(0, 1).toUpperCase();

    final fallback = Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
      child: Text(
        letter,
        style: AppTextStyles.titleMedium.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    return Pressable(
      onTap: onTap,
      pressedScale: 0.94,
      child: SizedBox(
        width: size + 12,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: size,
              height: size,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: channel.isLive
                      ? AppColors.red
                      : palette.divider,
                  width: channel.isLive ? 2.2 : 1,
                ),
              ),
              child: ClipOval(
                child: url == null || url.isEmpty
                    ? fallback
                    : CachedImage(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => fallback,
                      ),
              ),
            ),
            const SizedBox(height: AppSpace.xs + 1),
            Text(
              channel.isLive ? 'LIVE' : channel.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTextStyles.labelSmall.copyWith(
                color: channel.isLive ? AppColors.red : palette.textMuted,
                fontWeight: channel.isLive ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: channel.isLive ? 0.6 : 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Follow / following toggle for a channel (patch_164).
///
/// Filled while not following, outlined once you are — the same
/// inversion every subscribe control uses, because the loud state is the
/// call to action, not the confirmation.
class SubscribeButton extends StatelessWidget {
  const SubscribeButton({
    super.key,
    required this.subscribed,
    required this.onTap,
    this.compact = false,
  });

  final bool subscribed;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      haptics: true,
      pressedScale: 0.94,
      child: AnimatedContainer(
        duration: AppMotion.maybe(context, AppMotion.quick),
        curve: AppMotion.ease,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? AppSpace.md : AppSpace.lg,
          vertical: compact ? AppSpace.xs + 2 : AppSpace.sm,
        ),
        decoration: BoxDecoration(
          color: subscribed ? Colors.transparent : AppColors.primaryBlue,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: subscribed
                ? AppColors.white.withValues(alpha: 0.55)
                : AppColors.primaryBlue,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (subscribed) ...[
              const Icon(
                Icons.check_rounded,
                size: 15,
                color: AppColors.white,
              ),
              const SizedBox(width: AppSpace.xs + 1),
            ],
            Text(
              subscribed ? 'Following' : 'Follow',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- upcoming

/// A scheduled broadcast: a date block, the title, a live countdown and
/// a reminder bell.
class UpcomingCard extends StatelessWidget {
  const UpcomingCard({
    super.key,
    required this.video,
    required this.onTap,
    this.reminderSet = false,
    this.onToggleReminder,
  });

  final YoutubeVideo video;
  final VoidCallback onTap;

  final bool reminderSet;

  /// Null hides the bell — used where a reminder makes no sense.
  final VoidCallback? onToggleReminder;

  static const _months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];
  static const _days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  String _countdown(DateTime start) {
    final d = start.difference(DateTime.now());
    if (d.isNegative) return 'starting now';
    if (d.inDays >= 1) return 'in ${d.inDays}d';
    if (d.inHours >= 1) return 'in ${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes >= 1) return 'in ${d.inMinutes}m';
    return 'starting now';
  }

  String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final start = video.scheduledStartAt;

    return Pressable(
      onTap: onTap,
      pressedScale: 0.98,
      child: Container(
        width: 268,
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: palette.divider),
        ),
        child: Row(
          children: [
            if (start != null) ...[
              SizedBox(
                width: 42,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _days[start.weekday - 1],
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.red,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                    Text(
                      start.day.toString().padLeft(2, '0'),
                      style: AppTextStyles.titleLarge.copyWith(
                        color: palette.text,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                      ),
                    ),
                    Text(
                      _months[start.month - 1],
                      style: AppTextStyles.labelSmall.copyWith(
                        color: palette.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Container(width: 1, height: 44, color: palette.divider),
              const SizedBox(width: AppSpace.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: palette.text,
                      height: 1.25,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    start == null
                        ? video.channelTitle
                        : '${_countdown(start)} · ${_clock(start)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (onToggleReminder != null && start != null) ...[
              const SizedBox(width: AppSpace.sm),
              Pressable(
                onTap: onToggleReminder,
                haptics: true,
                pressedScale: 0.88,
                child: AnimatedContainer(
                  duration: AppMotion.maybe(context, AppMotion.quick),
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: reminderSet
                        ? AppColors.primaryBlue
                        : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: reminderSet
                          ? AppColors.primaryBlue
                          : palette.divider,
                    ),
                  ),
                  child: Icon(
                    reminderSet
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_none_rounded,
                    size: 19,
                    color: reminderSet ? AppColors.white : palette.textMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- filter chip

/// Pill filter for the sticky rail under the app bar.
class WatchFilterChip extends StatelessWidget {
  const WatchFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.94,
      child: AnimatedContainer(
        duration: AppMotion.maybe(context, AppMotion.quick),
        curve: AppMotion.ease,
        padding: EdgeInsets.symmetric(
          horizontal: icon == null ? AppSpace.md + 2 : AppSpace.md,
          vertical: AppSpace.sm - 1,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryBlue : palette.chipBg,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? AppColors.primaryBlue : palette.divider,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: selected ? AppColors.white : palette.textMuted,
              ),
              const SizedBox(width: AppSpace.xs + 1),
            ],
            Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: selected ? AppColors.white : palette.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
