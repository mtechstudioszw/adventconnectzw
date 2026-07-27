import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../models/youtube_video.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../cached_image.dart';
import '../motion/pressable.dart';

/// "LIVE now" hero for the top of Home. Renders nothing (zero height) when no
/// monitored channel is streaming. Tap → opens the stream in the player.
///
/// This replaced a 56dp strip that showed a 72×40 thumbnail next to two lines
/// of text. A service going out live is the single most time-critical thing
/// Home ever has to say, and that strip said it in the visual language of a
/// list row — so it read as chrome and got scrolled past.
///
/// It is now a full-bleed 16:9 card: the broadcast's own frame, a scrim, and
/// the title over it. When several channels are live at once it becomes a
/// swipeable deck rather than silently picking one and hiding the rest —
/// which is what the old single-video API did.
class LiveBanner extends StatefulWidget {
  const LiveBanner({super.key, required this.live, required this.onTap});

  /// Every currently-live broadcast. Empty → the banner takes no space.
  final List<YoutubeVideo> live;
  final void Function(YoutubeVideo) onTap;

  @override
  State<LiveBanner> createState() => _LiveBannerState();
}

class _LiveBannerState extends State<LiveBanner> {
  final PageController _pc = PageController(viewportFraction: 0.94);
  int _page = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.live;
    if (live.isEmpty) return const SizedBox.shrink();

    // One stream doesn't need a pager — and a full-width card looks better
    // than one inset to 94% with nothing beside it.
    if (live.length == 1) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.md,
          AppSpace.lg,
          0,
        ),
        child: _LiveCard(video: live.first, onTap: () => widget.onTap(live.first)),
      );
    }

    return Column(
      children: [
        const SizedBox(height: AppSpace.md),
        SizedBox(
          // 16:9 media + the caption block that sits under it.
          height: _LiveCard.height(context),
          child: PageView.builder(
            controller: _pc,
            itemCount: live.length,
            onPageChanged: (i) {
              HapticFeedback.selectionClick();
              setState(() => _page = i);
            },
            itemBuilder: (context, i) => Padding(
              // Half the island gutter each side so neighbouring cards peek,
              // which is what tells you the deck is swipeable at all.
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm - 2),
              child: _LiveCard(
                video: live[i],
                onTap: () => widget.onTap(live[i]),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        _Dots(count: live.length, index: _page),
      ],
    );
  }
}

class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.video, required this.onTap});

  final YoutubeVideo video;
  final VoidCallback onTap;

  /// Media at 16:9 plus the caption strip, so the pager can be given a fixed
  /// height without measuring children.
  static double height(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width - AppSpace.lg * 2;
    return width * 9 / 16 + _captionHeight;
  }

  static const double _captionHeight = 62;

  @override
  Widget build(BuildContext context) {
    final thumb = video.thumbnailUrl;
    final views = video.viewsLabel;

    return Semantics(
      button: true,
      label: 'Live now: ${video.title}, ${video.channelTitle}',
      child: Pressable(
        onTap: onTap,
        pressedScale: 0.985,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.darkNavy,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: AppShadows.card(context),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (thumb != null && thumb.isNotEmpty)
                      CachedImage(
                        thumb,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const _ThumbFallback(),
                      )
                    else
                      const _ThumbFallback(),
                    // Scrim: dark at the top so the LIVE pill reads, dark at
                    // the bottom so the play glyph does, clear through the
                    // middle so the broadcast is actually visible.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x730D1B3E),
                            Color(0x1A0D1B3E),
                            Color(0x8C0D1B3E),
                          ],
                          stops: [0, 0.45, 1],
                        ),
                      ),
                    ),
                    const Positioned(
                      top: AppSpace.md,
                      left: AppSpace.md,
                      child: _LivePill(),
                    ),
                    if (views.isNotEmpty)
                      Positioned(
                        top: AppSpace.md,
                        right: AppSpace.md,
                        child: _GlassChip(
                          icon: Icons.visibility_outlined,
                          label: views.replaceAll(' views', ' watching'),
                        ),
                      ),
                    const Center(child: _PlayGlyph()),
                  ],
                ),
              ),
              SizedBox(
                height: _captionHeight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.md,
                    AppSpace.sm,
                    AppSpace.md,
                    AppSpace.sm,
                  ),
                  child: Row(
                    children: [
                      _ChannelAvatar(video: video),
                      const SizedBox(width: AppSpace.sm + 2),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              video.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.white,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              video.channelTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.white.withValues(alpha: 0.72),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.white,
                        size: 20,
                      ),
                    ],
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

/// Pulsing LIVE badge. The pulse is the point — a static red chip is
/// indistinguishable from a category label, and "this is happening right now"
/// is the entire message.
class _LivePill extends StatefulWidget {
  const _LivePill();

  @override
  State<_LivePill> createState() => _LivePillState();
}

class _LivePillState extends State<_LivePill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect "remove animations" — the badge still reads as live from its
    // colour and label, it just stops breathing.
    //
    // This check lives here, not in initState: AppMotion.enabled reads
    // MediaQuery, and taking an inherited-widget dependency before initState
    // finishes throws.
    final animate = AppMotion.enabled(context);
    if (animate && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!animate && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.red,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: [
          BoxShadow(
            color: AppColors.red.withValues(alpha: 0.45),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween<double>(begin: 1, end: 0.25).animate(_c),
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: AppColors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'LIVE',
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassChip extends StatelessWidget {
  const _GlassChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.darkNavy.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.white),
          const SizedBox(width: 4),
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

class _PlayGlyph extends StatelessWidget {
  const _PlayGlyph();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.white.withValues(alpha: 0.55)),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.play_arrow_rounded,
        color: AppColors.white,
        size: 32,
      ),
    );
  }
}

class _ChannelAvatar extends StatelessWidget {
  const _ChannelAvatar({required this.video});

  final YoutubeVideo video;

  @override
  Widget build(BuildContext context) {
    final url = video.channelThumbUrl;
    final letter = video.channelTitle.trim().isEmpty
        ? '?'
        : video.channelTitle.trim().substring(0, 1).toUpperCase();
    final fallback = Text(
      letter,
      style: AppTextStyles.labelMedium.copyWith(
        color: AppColors.white,
        fontWeight: FontWeight.w800,
      ),
    );

    return Container(
      width: 34,
      height: 34,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.primaryGradient,
        border: Border.all(color: AppColors.white.withValues(alpha: 0.28)),
      ),
      child: url == null || url.isEmpty
          ? fallback
          : CachedImage(
              url,
              fit: BoxFit.cover,
              width: 34,
              height: 34,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback();

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

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: AppMotion.maybe(context, AppMotion.quick),
            width: i == index ? 18 : 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: i == index
                  ? AppColors.red
                  : AppColors.red.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}
