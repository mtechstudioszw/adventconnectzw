import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/youtube_video.dart';
import '../../services/youtube_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/youtube/youtube_video_card.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/brand_spinner.dart';

/// The user's saved (bookmarked) Watch videos — a clear, dedicated screen
/// (reached from the Watch tab's bookmark icon) instead of a hidden feed
/// filter.
class SavedVideosScreen extends StatefulWidget {
  const SavedVideosScreen({super.key});

  @override
  State<SavedVideosScreen> createState() => _SavedVideosScreenState();
}

class _SavedVideosScreenState extends State<SavedVideosScreen> {
  List<YoutubeVideo> _videos = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await YoutubeService.fetchBookmarks();
    if (!mounted) return;
    setState(() {
      _videos = v;
      _loading = false;
    });
  }

  Future<void> _unsave(YoutubeVideo v) async {
    setState(
      () => _videos = _videos.where((x) => x.videoId != v.videoId).toList(),
    );
    await YoutubeService.setBookmarked(v.videoId, false);
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
        title: Text('Saved', style: AppTextStyles.appBarTitle),
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: BrandSpinner(size: 30))
            : _videos.isEmpty
            ? _empty(palette)
            : BrandedRefreshIndicator(
                color: AppColors.primaryBlue,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.only(top: 8, bottom: 28),
                  children: [
                    for (final v in _videos)
                      YoutubeVideoCard(
                        video: v,
                        saved: true,
                        onSaveToggle: () => _unsave(v),
                        onTap: () => context.pushNamed(
                          'watch_video',
                          pathParameters: {'id': v.videoId},
                          extra: v,
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _empty(AppPalette palette) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bookmark_border, size: 56, color: palette.textMuted),
          const SizedBox(height: 14),
          Text(
            'No saved videos yet',
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.w700,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap the bookmark on any video to save it here.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    ),
  );
}
