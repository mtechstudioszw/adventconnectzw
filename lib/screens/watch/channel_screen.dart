import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/youtube_channel.dart';
import '../../models/youtube_playlist.dart';
import '../../models/youtube_video.dart';
import '../../services/youtube_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/youtube/watch_cards.dart';
import '../../widgets/youtube/youtube_video_card.dart';

/// One channel: a proper header over its own artwork, and its series
/// alongside its videos.
///
/// This used to be a plain list under a 56dp avatar — the same treatment
/// a settings row gets. A channel with a million subscribers deserves the
/// screen to open with its own frame.
class ChannelScreen extends StatefulWidget {
  const ChannelScreen({super.key, required this.channelId, this.initial});

  final String channelId;
  final YoutubeChannel? initial;

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  final ScrollController _scroll = ScrollController();
  final List<YoutubeVideo> _videos = [];

  YoutubeChannel? _channel;
  List<YoutubePlaylist> _series = const [];
  YoutubeVideo? _live;
  bool _subscribed = false;

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  static const _page = 20;

  @override
  void initState() {
    super.initState();
    _channel = widget.initial;
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
    // The channel's own series, and whether it is on air right now.
    final results = await Future.wait<Object?>([
      YoutubeService.fetchChannelSeries(widget.channelId),
      YoutubeService.fetchLiveNow(),
      YoutubeService.fetchSubscriptionIds(),
    ]);
    if (mounted) {
      final live = (results[1] as List<YoutubeVideo>)
          .where((v) => v.channelId == widget.channelId);
      setState(() {
        _series = results[0] as List<YoutubePlaylist>;
        _live = live.isEmpty ? null : live.first;
        _subscribed =
            (results[2] as Set<String>).contains(widget.channelId);
      });
    }
    await _loadMore();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    _loadingMore = true;
    final rows = await YoutubeService.fetchByChannel(
      widget.channelId,
      limit: _page,
      offset: _offset,
    );
    if (!mounted) return;
    setState(() {
      _videos.addAll(rows);
      _offset += rows.length;
      _hasMore = rows.length == _page;
      _loadingMore = false;
    });
  }

  Future<void> _toggleSubscribe() async {
    final next = !_subscribed;
    setState(() => _subscribed = next);
    await YoutubeService.setSubscribed(widget.channelId, next);
  }

  void _open(YoutubeVideo v) => context.pushNamed(
        'watch_video',
        pathParameters: {'id': v.videoId},
        extra: v,
      );

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final c = _channel;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          _header(c, palette),
          if (_live != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.lg,
                  AppSpace.lg,
                  AppSpace.lg,
                  0,
                ),
                child: _LiveNowStrip(
                  video: _live!,
                  onTap: () => _open(_live!),
                ),
              ),
            ),
          if (_series.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: WatchSectionHeader(
                title: 'Series',
                icon: Icons.video_library_rounded,
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 138 + 46,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
                  itemCount: _series.length,
                  separatorBuilder: (_, _) => const SizedBox(width: AppSpace.md),
                  itemBuilder: (_, i) => SeriesCard(
                    playlist: _series[i],
                    onTap: () => context.pushNamed(
                      'watch_series',
                      pathParameters: {'playlistId': _series[i].playlistId},
                      extra: _series[i],
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (_videos.isNotEmpty)
            const SliverToBoxAdapter(
              child: WatchSectionHeader(
                title: 'Videos',
                icon: Icons.ondemand_video_rounded,
              ),
            ),
          if (_loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(AppSpace.xxl),
                child: Center(child: BrandSpinner(size: 30)),
              ),
            )
          else if (_videos.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.xxl + 8),
                child: Center(
                  child: Text(
                    'No videos yet.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: _videos.length,
              itemBuilder: (context, i) => YoutubeVideoCard(
                video: _videos[i],
                onTap: () => _open(_videos[i]),
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

  Widget _header(YoutubeChannel? c, AppPalette palette) {
    final thumb = c?.thumbnailUrl;
    final isLive = _live != null || (c?.isLive ?? false);

    return SliverAppBar(
      expandedHeight: 208,
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
          c?.title ?? 'Channel',
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
            // The channel's avatar, blown up and blurred behind its own
            // header — the only artwork the sync gives us for a channel.
            if (thumb != null && thumb.isNotEmpty)
              CachedImage(
                thumb,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ThumbFallback(),
              )
            else
              const ThumbFallback(),
            const MediaScrim(topAlpha: 0x73, bottomAlpha: 0xE6),
            Positioned(
              left: AppSpace.lg,
              right: AppSpace.lg,
              bottom: AppSpace.xxl + AppSpace.md,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isLive
                            ? AppColors.red
                            : AppColors.white.withValues(alpha: 0.5),
                        width: isLive ? 2.4 : 1.4,
                      ),
                    ),
                    child: ClipOval(
                      child: thumb != null && thumb.isNotEmpty
                          ? CachedImage(
                              thumb,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const ThumbFallback(),
                            )
                          : const ThumbFallback(),
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isLive) ...[
                          const LivePill(compact: true),
                          const SizedBox(height: AppSpace.xs + 2),
                        ],
                        if (c?.subscriberCount != null)
                          Text(
                            _subs(c!.subscriberCount!),
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.white.withValues(alpha: 0.82),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  SubscribeButton(
                    subscribed: _subscribed,
                    onTap: _toggleSubscribe,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subs(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M subscribers';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K subscribers';
    return '$n subscribers';
  }
}

/// "On air now" banner at the top of a channel that is streaming.
class _LiveNowStrip extends StatelessWidget {
  const _LiveNowStrip({required this.video, required this.onTap});

  final YoutubeVideo video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final thumb = video.thumbnailUrl;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
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
              const MediaScrim(),
              const Positioned(
                top: AppSpace.md,
                left: AppSpace.md,
                child: LivePill(),
              ),
              const Center(child: PlayGlyph(size: 52)),
              Positioned(
                left: AppSpace.md,
                right: AppSpace.md,
                bottom: AppSpace.md,
                child: Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium.copyWith(
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
    );
  }
}
