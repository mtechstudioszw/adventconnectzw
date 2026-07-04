import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/youtube_channel.dart';
import '../../models/youtube_video.dart';
import '../../services/youtube_service.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/youtube/youtube_video_card.dart';
import '../../widgets/motion/brand_spinner.dart';

/// One channel's videos (reached from the Channels list).
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
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
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
      _loading = false;
      _loadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final c = _channel;
    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      appBar: AppBar(
        title: Text(c?.title ?? 'Channel'),
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: BrandSpinner(size: 30))
            : ListView(
                controller: _scroll,
                padding: const EdgeInsets.only(bottom: 28),
                children: [
                  if (c != null) _header(c, palette),
                  if (_videos.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(
                        child: Text(
                          'No videos yet.',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                      ),
                    ),
                  for (final v in _videos)
                    YoutubeVideoCard(
                      video: v,
                      onTap: () => context.pushNamed(
                        'watch_video',
                        pathParameters: {'id': v.videoId},
                        extra: v,
                      ),
                    ),
                  if (_loadingMore)
                    const Padding(
                      padding: EdgeInsets.all(18),
                      child: Center(child: BrandSpinner(size: 30)),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _header(YoutubeChannel c, AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          ClipOval(
            child: SizedBox(
              width: 56,
              height: 56,
              child: c.thumbnailUrl != null
                  ? CachedImage(c.thumbnailUrl!, fit: BoxFit.cover)
                  : Container(
                      color: palette.cardMuted,
                      child: Icon(Icons.tv_rounded, color: palette.textMuted),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        c.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleLarge.copyWith(
                          fontWeight: FontWeight.w800,
                          color: palette.text,
                        ),
                      ),
                    ),
                    if (c.isLive) ...[
                      const SizedBox(width: 8),
                      const LivePill(compact: true),
                    ],
                  ],
                ),
                if (c.subscriberCount != null)
                  Text(
                    _subs(c.subscriberCount!),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _subs(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M subscribers';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K subscribers';
    return '$n subscribers';
  }
}
