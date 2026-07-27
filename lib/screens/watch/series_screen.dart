import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/youtube_playlist.dart';
import '../../models/youtube_video.dart';
import '../../services/youtube_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/youtube/watch_cards.dart';

/// One series (a YouTube playlist), as an episode list.
///
/// A sermon series is the most bingeable thing in the library and had no
/// screen at all — 1,424 playlists and 22,585 items have been syncing
/// since patch_154 without ever being rendered.
///
/// Episodes are numbered by their playlist position, and [fromPosition]
/// lets "Continue the series" land on the next episode rather than
/// episode one.
class SeriesScreen extends StatefulWidget {
  const SeriesScreen({
    super.key,
    required this.playlistId,
    this.initial,
    this.fromPosition = 0,
  });

  final String playlistId;
  final YoutubePlaylist? initial;

  /// Zero-based episode to scroll to on open.
  final int fromPosition;

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends State<SeriesScreen> {
  final ScrollController _scroll = ScrollController();
  final List<YoutubeVideo> _episodes = [];

  YoutubePlaylist? _playlist;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  static const _page = 25;

  /// Playlist position of the first row currently loaded.
  int _startPosition = 0;

  @override
  void initState() {
    super.initState();
    _playlist = widget.initial;
    // Start the window a little before the resume point so there's
    // context above it, rather than dropping the user onto a bare row.
    _startPosition = (widget.fromPosition - 2).clamp(0, 1 << 30);
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 600) {
        _loadMore();
      }
    });
    _bootstrap();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (_playlist == null) {
      final p = await YoutubeService.fetchPlaylist(widget.playlistId);
      if (mounted) setState(() => _playlist = p);
    }
    await _loadMore();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    _loadingMore = true;
    final rows = await YoutubeService.fetchByPlaylist(
      widget.playlistId,
      limit: _page,
      offset: _startPosition + _episodes.length,
    );
    if (!mounted) return;
    setState(() {
      _episodes.addAll(rows);
      _hasMore = rows.length == _page;
      _loadingMore = false;
    });
  }

  void _open(YoutubeVideo v) => context.pushNamed(
        'watch_video',
        pathParameters: {'id': v.videoId},
        extra: v,
      );

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final p = _playlist;

    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          _header(p, palette),
          if (_loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(AppSpace.xxl),
                child: Center(child: BrandSpinner(size: 30)),
              ),
            )
          else if (_episodes.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.xxl + 8),
                child: Center(
                  child: Text(
                    'No episodes in this series yet.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: _episodes.length,
              itemBuilder: (context, i) => _EpisodeRow(
                video: _episodes[i],
                episodeNumber: _startPosition + i + 1,
                highlighted: _startPosition + i == widget.fromPosition,
                onTap: () => _open(_episodes[i]),
              ),
            ),
          if (_loadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(AppSpace.lg),
                child: Center(child: BrandSpinner(size: 26)),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xxl)),
        ],
      ),
    );
  }

  Widget _header(YoutubePlaylist? p, AppPalette palette) {
    final thumb = p?.thumbnailUrl;
    return SliverAppBar(
      expandedHeight: 236,
      pinned: true,
      backgroundColor: AppColors.darkNavy,
      foregroundColor: AppColors.white,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg + 40,
          vertical: AppSpace.md,
        ),
        title: Text(
          p?.title ?? 'Series',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        background: Stack(
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
            const MediaScrim(topAlpha: 0x66, bottomAlpha: 0xE6),
            Positioned(
              left: AppSpace.lg,
              right: AppSpace.lg,
              bottom: AppSpace.xxl + AppSpace.sm,
              child: Row(
                children: [
                  if (p != null && p.itemCount > 0)
                    GlassChip(
                      label: '${p.itemCount} episodes',
                      icon: Icons.playlist_play_rounded,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One episode: number, still, title, runtime.
class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.video,
    required this.episodeNumber,
    required this.highlighted,
    required this.onTap,
  });

  final YoutubeVideo video;
  final int episodeNumber;

  /// The episode "Continue the series" sent us to.
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final thumb = video.thumbnailUrl;

    return Pressable(
      onTap: onTap,
      pressedScale: 0.985,
      child: Container(
        margin: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.sm - 2,
          AppSpace.lg,
          AppSpace.sm - 2,
        ),
        padding: const EdgeInsets.all(AppSpace.sm),
        decoration: BoxDecoration(
          color: highlighted
              ? AppColors.primaryBlue.withValues(alpha: 0.08)
              : palette.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: highlighted
                ? AppColors.primaryBlue.withValues(alpha: 0.35)
                : palette.divider,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text(
                '$episodeNumber',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: highlighted
                      ? AppColors.primaryBlue
                      : palette.textMuted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: SizedBox(
                width: 108,
                height: 108 * 9 / 16,
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
                    const MediaScrim(topAlpha: 0x1A, bottomAlpha: 0x8C),
                    if (video.durationLabel.isNotEmpty)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: GlassChip(label: video.durationLabel),
                      ),
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
                  const SizedBox(height: 3),
                  Text(
                    video.publishedLabel,
                    style: AppTextStyles.caption.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
