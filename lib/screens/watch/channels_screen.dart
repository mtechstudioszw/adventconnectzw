import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/youtube_channel.dart';
import '../../services/youtube_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/youtube/youtube_video_card.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/brand_spinner.dart';

/// Browse all monitored channels — tap one to see its videos.
class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key});

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  List<YoutubeChannel> _channels = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await YoutubeService.fetchChannels();
    if (!mounted) return;
    setState(() {
      _channels = c;
      _loading = false;
    });
  }

  String _subs(int? n) {
    if (n == null) return '';
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M subscribers';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K subscribers';
    return '$n subscribers';
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.appBarGradient),
        ),
        foregroundColor: AppColors.white,
        title: Text('Channels', style: AppTextStyles.appBarTitle),
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: BrandSpinner(size: 30))
            : _channels.isEmpty
            ? Center(
                child: Text(
                  'No channels yet.',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              )
            : BrandedRefreshIndicator(
                color: AppColors.primaryBlue,
                onRefresh: _load,
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _channels.length,
                  separatorBuilder: (_, _) =>
                      Divider(color: palette.divider, height: 1),
                  itemBuilder: (_, i) {
                    final c = _channels[i];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      leading: ClipOval(
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: c.thumbnailUrl != null
                              ? CachedImage(c.thumbnailUrl!, fit: BoxFit.cover)
                              : Container(
                                  color: palette.cardMuted,
                                  child: Icon(
                                    Icons.tv_rounded,
                                    color: palette.textMuted,
                                  ),
                                ),
                        ),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              c.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.titleMedium.copyWith(
                                fontWeight: FontWeight.w700,
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
                      subtitle: _subs(c.subscriberCount).isEmpty
                          ? null
                          : Text(
                              _subs(c.subscriberCount),
                              style: AppTextStyles.bodySmall.copyWith(
                                color: palette.textMuted,
                              ),
                            ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: palette.textMuted,
                      ),
                      onTap: () => context.pushNamed(
                        'watch_channel',
                        pathParameters: {'channelId': c.channelId},
                        extra: c,
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
