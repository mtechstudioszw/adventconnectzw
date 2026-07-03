import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/youtube_video.dart';
import '../../services/youtube_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../services/ads/interstitial_ad_manager.dart';
import '../../widgets/ads/native_ad_card.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/shimmer_loaders.dart';
import '../../widgets/youtube/youtube_video_card.dart';
import '../widgets/main_bottom_nav.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/motion/content_reveal.dart';
import '../../widgets/motion/hide_on_scroll.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/motion/staggered_reveal.dart';

/// The Watch tab — a faith-safe media home. Hero (live/featured) + contextual
/// rails (Continue watching, Upcoming) + playlist category chips + an endless
/// feed of big individual video cards.
class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key});

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> with NavVisibilityMixin {
  final ScrollController _scroll = ScrollController();

  YoutubeVideo? _live;
  YoutubeVideo? _hero;
  List<YoutubeVideo> _liveNow =
      const []; // all currently-live (multi-live rail)
  List<ResumeItem> _continue = [];
  List<YoutubeVideo> _upcoming = [];
  Set<String> _saved = {};

  final List<YoutubeVideo> _feed = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  static const _page = 20;

  /// null = All, 'saved' = Saved, otherwise a playlistId.
  String? _category;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _bootstrap();
    // Interstitial on entering Watch — best-effort + globally capped (2-min
    // gap) so re-entering the tab doesn't spam. The player itself stays
    // ad-free.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      InterstitialAdManager.maybeShow();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    // Cache-first: paint the cached feed instantly (no shimmer on a warm
    // cache / slow network), then refresh in the background.
    if (_category == null && _feed.isEmpty) {
      _live ??= YoutubeService.cachedLive();
      final cached = YoutubeService.cachedFeed();
      if (cached.isNotEmpty) {
        _feed.addAll(cached);
        _hero = _live ?? cached.first;
        _loading = false;
      }
    }
    // Rails hydrate from cache too — previously they started empty and
    // "popped in" a couple of seconds after the tab opened.
    if (_liveNow.isEmpty) _liveNow = YoutubeService.cachedLiveNow();
    if (_continue.isEmpty) _continue = YoutubeService.cachedContinueWatching();
    if (_upcoming.isEmpty) _upcoming = YoutubeService.cachedUpcoming();
    if (_saved.isEmpty) _saved = YoutubeService.cachedBookmarkIds();
    if (mounted) setState(() => _loading = _feed.isEmpty);

    final results = await Future.wait<Object?>([
      YoutubeService.fetchLiveNow(),
      YoutubeService.fetchContinueWatching(),
      YoutubeService.fetchUpcoming(),
      YoutubeService.fetchBookmarkIds(),
    ]);
    _liveNow = results[0] as List<YoutubeVideo>;
    _live = _liveNow.isNotEmpty ? _liveNow.first : null;
    _continue = results[1] as List<ResumeItem>;
    _upcoming = results[2] as List<YoutubeVideo>;
    _saved = results[3] as Set<String>;
    _feed.clear();
    _offset = 0;
    _hasMore = true;
    await _loadMore(reset: true);
    _hero = _live ?? (_feed.isNotEmpty ? _feed.first : _hero);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMore({bool reset = false}) async {
    if (_loadingMore || (!_hasMore && !reset)) return;
    _loadingMore = true;
    final cat = _category;
    List<YoutubeVideo> rows;
    if (cat == 'saved') {
      rows = _offset == 0 ? await YoutubeService.fetchBookmarks() : const [];
    } else if (cat != null) {
      // SDA category chips filter the library by keyword (zero new tables).
      rows = await YoutubeService.search(cat, limit: _page, offset: _offset);
    } else {
      rows = await YoutubeService.fetchFeed(limit: _page, offset: _offset);
    }
    if (!mounted) return;
    setState(() {
      _feed.addAll(rows);
      _offset += rows.length;
      _hasMore = rows.length == _page;
      _loadingMore = false;
    });
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 700) {
      _loadMore();
    }
  }

  void _selectCategory(String? cat) {
    if (_category == cat) return;
    setState(() {
      _category = cat;
      _feed.clear();
      _offset = 0;
      _hasMore = true;
    });
    _loadMore(reset: true);
  }

  void _open(YoutubeVideo v) => context.pushNamed(
    'watch_video',
    pathParameters: {'id': v.videoId},
    extra: v,
  );

  Future<void> _toggleSave(YoutubeVideo v) async {
    final saved = !_saved.contains(v.videoId);
    setState(() => saved ? _saved.add(v.videoId) : _saved.remove(v.videoId));
    await YoutubeService.setBookmarked(v.videoId, saved);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.appBarGradient),
        ),
        foregroundColor: AppColors.white,
        title: Text('Watch', style: AppTextStyles.appBarTitle),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            // Reuse the premium global search (it now includes a Videos
            // section), instead of a separate bespoke search screen.
            onPressed: () => context.pushNamed('search'),
          ),
          IconButton(
            tooltip: 'Channels',
            icon: const Icon(Icons.subscriptions_outlined),
            onPressed: () => context.pushNamed('watch_channels'),
          ),
          IconButton(
            tooltip: 'Saved',
            icon: const Icon(Icons.bookmark_border),
            onPressed: () => context.pushNamed('watch_saved'),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'submit') _openSubmitSheet();
              if (v == 'channels') context.pushNamed('watch_channels');
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'channels', child: Text('Browse channels')),
              PopupMenuItem(
                value: 'submit',
                child: Text('Submit your channel'),
              ),
            ],
          ),
        ],
      ),
      body: NotificationListener<UserScrollNotification>(
        onNotification: handleNavScroll,
        child: SafeArea(
          top: false,
          // Video-shaped shimmer crossfades into the feed.
          child: ContentReveal(
            loading: _loading,
            skeleton: ShimmerLoaders.watchList(),
            child: BrandedRefreshIndicator(
              color: AppColors.primaryBlue,
              onRefresh: _bootstrap,
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.only(bottom: 28),
                children: [
                  if (_hero != null) _heroCard(_hero!, palette),
                  // When several channels are live at once, a "Live now"
                  // rail lists them all (hero shows the first).
                  if (_liveNow.length > 1) _liveNowRail(palette),
                  if (_continue.isNotEmpty) _continueRail(palette),
                  if (_upcoming.isNotEmpty) _upcomingRail(palette),
                  _categoryChips(palette),
                  if (_feed.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(
                        child: Text(
                          _category == 'saved'
                              ? 'Nothing saved yet.'
                              : 'No videos yet.',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                      ),
                    ),
                  for (int i = 0; i < _feed.length; i++) ...[
                    if (i < 5)
                      StaggeredReveal(
                        index: i,
                        rise: 18,
                        child: YoutubeVideoCard(
                          video: _feed[i],
                          onTap: () => _open(_feed[i]),
                          saved: _saved.contains(_feed[i].videoId),
                          onSaveToggle: () => _toggleSave(_feed[i]),
                        ),
                      )
                    else
                      YoutubeVideoCard(
                        video: _feed[i],
                        onTap: () => _open(_feed[i]),
                        saved: _saved.contains(_feed[i].videoId),
                        onSaveToggle: () => _toggleSave(_feed[i]),
                      ),
                    // Native ad every ~8 videos in the browse feed.
                    if ((i + 1) % 8 == 0) const NativeAdCard(),
                  ],
                  if (_loadingMore)
                    const Padding(
                      padding: EdgeInsets.all(18),
                      child: Center(child: BrandSpinner(size: 28)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: HideOnScroll(
        visible: navVisible,
        child: const MainBottomNav(currentIndex: 1),
      ),
    );
  }

  // ------------------------------- Hero ------------------------------
  Widget _heroCard(YoutubeVideo v, AppPalette palette) {
    return PressEffect(
      child: GestureDetector(
        onTap: () => _open(v),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
          child: Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: v.thumbnailUrl != null
                    ? CachedImage(v.thumbnailUrl!, fit: BoxFit.cover)
                    : Container(color: palette.cardMuted),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        AppColors.darkNavy.withValues(alpha: 0.88),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (v.isLive)
                      const LivePill()
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.goldAccent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'FEATURED',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.darkNavy,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      v.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleMedium.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.play_arrow_rounded,
                                color: AppColors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                v.isLive ? 'Watch live' : 'Watch now',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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

  // ------------------------------- Rails -----------------------------
  Widget _railHeader(
    String title,
    AppPalette palette, {
    VoidCallback? onAction,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w800,
                color: palette.text,
              ),
            ),
          ),
          if (onAction != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                'See all',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _continueRail(AppPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _railHeader('Continue watching', palette),
        SizedBox(
          height: 168,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _continue.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final r = _continue[i];
              return YoutubeRailCard(
                video: r.video,
                progress: r.progress,
                onTap: () => _open(r.video),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _liveNowRail(AppPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _railHeader('Live now', palette),
        SizedBox(
          height: 168,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _liveNow.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => YoutubeRailCard(
              video: _liveNow[i],
              onTap: () => _open(_liveNow[i]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _upcomingRail(AppPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _railHeader('Upcoming live', palette),
        SizedBox(
          height: 168,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _upcoming.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => YoutubeRailCard(
              video: _upcoming[i],
              onTap: () => _open(_upcoming[i]),
            ),
          ),
        ),
      ],
    );
  }

  // ----------------------------- Category chips ----------------------
  // Five fixed SDA-themed filters (keyword-backed via youtube_search).
  static const _chips = <_Chip>[
    _Chip(label: 'All', value: null),
    _Chip(label: 'Sermons', value: 'sermon'),
    _Chip(label: 'Bible Study', value: 'bible study'),
    _Chip(label: 'Music', value: 'music'),
    _Chip(label: 'Prophecy', value: 'prophecy'),
  ];

  Widget _categoryChips(AppPalette palette) {
    const chips = _chips;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: chips.map((c) {
            final selected = _category == c.value;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(c.label),
                selected: selected,
                onSelected: (_) => _selectCategory(c.value),
                showCheckmark: false,
                labelStyle: AppTextStyles.bodySmall.copyWith(
                  color: selected ? AppColors.white : palette.text,
                  fontWeight: FontWeight.w700,
                ),
                backgroundColor: palette.chipBg,
                selectedColor: AppColors.primaryBlue,
                side: BorderSide(color: palette.divider),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // --------------------------- Submit channel ------------------------
  Future<void> _openSubmitSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _SubmitChannelSheet(),
    );
  }
}

class _Chip {
  const _Chip({required this.label, required this.value});
  final String label;
  final String? value;
}

/// "Submit your Adventist channel" form. Goes to the super-admin approval
/// queue (anyone can submit; you approve).
class _SubmitChannelSheet extends StatefulWidget {
  const _SubmitChannelSheet();

  @override
  State<_SubmitChannelSheet> createState() => _SubmitChannelSheetState();
}

class _SubmitChannelSheetState extends State<_SubmitChannelSheet> {
  final _link = TextEditingController();
  final _name = TextEditingController();
  final _contact = TextEditingController();
  final _note = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _link.dispose();
    _name.dispose();
    _contact.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final link = _link.text.trim();
    if (link.isEmpty) {
      setState(() => _error = 'Paste your YouTube channel link or @handle.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await YoutubeService.submitChannel(
        link: link,
        name: _name.text.trim(),
        contact: _contact.text.trim(),
        note: _note.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks! Your channel is under review.')),
      );
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    InputDecoration deco(String hint) => InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: palette.inputFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.divider),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Submit your channel',
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.w800,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Adventist creator? Send your channel for review. Approved channels '
            'appear in Watch.',
            style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _link,
            decoration: deco('YouTube channel link or @handle'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _name,
            decoration: deco('Your name (optional)'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _contact,
            decoration: deco('WhatsApp / email (so we can verify)'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            decoration: deco('A short note (optional)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.red),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _sending ? null : _submit,
              child: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    )
                  : const Text('Submit for review'),
            ),
          ),
        ],
      ),
    );
  }
}
