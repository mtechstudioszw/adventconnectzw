import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, SystemUiOverlayStyle;
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../models/youtube_video.dart';
import '../../services/youtube_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/youtube/watch_cards.dart';

/// Route arguments for the vertical Shorts feed.
class ShortsArgs {
  const ShortsArgs({required this.shorts, this.initialIndex = 0});

  final List<YoutubeVideo> shorts;
  final int initialIndex;
}

/// Full-screen vertical Shorts feed.
///
/// ~4.7k of the synced videos are a minute or under and were previously
/// flattened into the same 16:9 cards as a 47-minute sermon. This gives
/// them the format they were shot in.
///
/// Only ONE player exists — it is moved to whichever page is centred,
/// rather than one controller per page. A YouTube IFrame player is a
/// WebView; a PageView of them will exhaust memory on a mid-range Android
/// within a dozen swipes. Neighbouring pages show their thumbnail, which
/// is what the player is about to cover anyway.
class ShortsScreen extends StatefulWidget {
  const ShortsScreen({super.key, required this.args});

  final ShortsArgs args;

  @override
  State<ShortsScreen> createState() => _ShortsScreenState();
}

class _ShortsScreenState extends State<ShortsScreen> {
  late final PageController _pager;
  late final YoutubePlayerController _player;

  final List<YoutubeVideo> _shorts = [];
  late int _index;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    _shorts.addAll(widget.args.shorts);
    _index = widget.args.initialIndex.clamp(
      0,
      _shorts.isEmpty ? 0 : _shorts.length - 1,
    );
    _pager = PageController(initialPage: _index);
    _player = YoutubePlayerController(
      params: const YoutubePlayerParams(
        showControls: false,
        showFullscreenButton: false,
        showVideoAnnotations: false,
        enableCaption: false,
        // Shorts loop — the format's defining behaviour.
        loop: true,
        mute: false,
      ),
    );
    if (_shorts.isNotEmpty) _cue(_shorts[_index]);
    _maybeLoadMore();
  }

  @override
  void dispose() {
    _pager.dispose();
    _player.close();
    super.dispose();
  }

  void _cue(YoutubeVideo v) {
    _player.loadVideoById(videoId: v.videoId);
    // Shorts are watched to the end far more often than long videos, so
    // history is recorded on open rather than on a progress tick.
    YoutubeService.recordProgress(
      v.videoId,
      positionSeconds: 0,
      durationSeconds: v.durationSeconds,
      completed: true,
    );
  }

  Future<void> _maybeLoadMore() async {
    if (_loadingMore || !_hasMore) return;
    if (_index < _shorts.length - 4) return;
    _loadingMore = true;
    final rows = await YoutubeService.fetchShorts(
      limit: 20,
      offset: _shorts.length,
    );
    if (!mounted) return;
    setState(() {
      final existing = {for (final v in _shorts) v.videoId};
      _shorts.addAll(rows.where((v) => existing.add(v.videoId)));
      _hasMore = rows.length == 20;
      _loadingMore = false;
    });
  }

  void _onPageChanged(int i) {
    HapticFeedback.selectionClick();
    setState(() => _index = i);
    _cue(_shorts[i]);
    _maybeLoadMore();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _muted ? _player.mute() : _player.unMute();
  }

  Future<void> _share(YoutubeVideo v) async {
    await Share.share(
      '${v.title}\n\nWatch on Advent Connect ZW:\n'
      'https://www.youtube.com/watch?v=${v.videoId}',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_shorts.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text('No shorts yet.', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            PageView.builder(
              controller: _pager,
              scrollDirection: Axis.vertical,
              itemCount: _shorts.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, i) => _ShortPage(
                video: _shorts[i],
                // Only the centred page gets the live player.
                player: i == _index ? _player : null,
                muted: _muted,
                onToggleMute: _toggleMute,
                onShare: () => _share(_shorts[i]),
                onOpenFull: () => context.pushNamed(
                  'watch_video',
                  pathParameters: {'id': _shorts[i].videoId},
                  extra: _shorts[i],
                ),
              ),
            ),
            // Close affordance, clear of the status bar.
            Positioned(
              top: MediaQuery.paddingOf(context).top + AppSpace.sm,
              left: AppSpace.sm,
              child: Pressable(
                onTap: () => Navigator.of(context).maybePop(),
                pressedScale: 0.9,
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.darkNavy.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    color: AppColors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortPage extends StatelessWidget {
  const _ShortPage({
    required this.video,
    required this.player,
    required this.muted,
    required this.onToggleMute,
    required this.onShare,
    required this.onOpenFull,
  });

  final YoutubeVideo video;
  final YoutubePlayerController? player;
  final bool muted;
  final VoidCallback onToggleMute;
  final VoidCallback onShare;
  final VoidCallback onOpenFull;

  @override
  Widget build(BuildContext context) {
    final thumb = video.thumbnailUrl;

    return Stack(
      fit: StackFit.expand,
      children: [
        // The still sits under the player so a swipe never flashes black
        // while the WebView cues the next clip.
        if (thumb != null && thumb.isNotEmpty)
          CachedImage(
            thumb,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const ThumbFallback(),
          )
        else
          const ThumbFallback(),

        if (player != null)
          Center(
            child: YoutubePlayer(
              controller: player!,
              aspectRatio: 9 / 16,
            ),
          ),

        // Scrim only where the caption and buttons sit.
        const IgnorePointer(
          child: MediaScrim(topAlpha: 0x40, bottomAlpha: 0xC0),
        ),

        // Caption block.
        Positioned(
          left: AppSpace.lg,
          right: 76,
          bottom: AppSpace.xl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                video.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      video.channelTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.white.withValues(alpha: 0.78),
                      ),
                    ),
                  ),
                  if (video.viewsLabel.isNotEmpty) ...[
                    const SizedBox(width: AppSpace.sm),
                    Text(
                      '· ${video.viewsLabel}',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),

        // Action rail.
        Positioned(
          right: AppSpace.md,
          bottom: AppSpace.xl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RailButton(
                icon: muted
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                label: muted ? 'Muted' : 'Sound',
                onTap: onToggleMute,
              ),
              const SizedBox(height: AppSpace.lg),
              _RailButton(
                icon: Icons.ios_share_rounded,
                label: 'Share',
                onTap: onShare,
              ),
              const SizedBox(height: AppSpace.lg),
              _RailButton(
                icon: Icons.open_in_full_rounded,
                label: 'Full',
                onTap: onOpenFull,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      pressedScale: 0.88,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.darkNavy.withValues(alpha: 0.42),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.white.withValues(alpha: 0.22),
              ),
            ),
            child: Icon(icon, color: AppColors.white, size: 22),
          ),
          const SizedBox(height: AppSpace.xs + 1),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
