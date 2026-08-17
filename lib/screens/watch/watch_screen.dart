import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:go_router/go_router.dart';

import '../../models/youtube_channel.dart';
import '../../models/youtube_playlist.dart';
import '../../models/youtube_video.dart';
import '../../services/sabbath_service.dart';
import '../../services/watch_reminder_service.dart';
import '../../services/youtube_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/ads/feed_ad_card.dart';
import '../../widgets/home/live_banner.dart';
import '../../widgets/shimmer_loaders.dart';
import '../../widgets/youtube/watch_cards.dart';
import '../../widgets/youtube/youtube_video_card.dart';
import 'shorts_screen.dart' show ShortsArgs;
import '../widgets/main_bottom_nav.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/motion/content_reveal.dart';
import '../../widgets/motion/hide_on_scroll.dart';
import '../../widgets/motion/staggered_reveal.dart';

/// Which slice of the library the feed below the chips is showing.
enum _Filter {
  all('All'),
  following('Following'),
  shorts('Shorts'),
  series('Series'),
  sermons('Sermons', query: 'sermon'),
  bibleStudy('Bible Study', query: 'bible study'),
  music('Music', query: 'music'),
  prophecy('Prophecy', query: 'prophecy'),
  saved('Saved');

  const _Filter(this.label, {this.query});

  final String label;

  /// Keyword filters run through the youtube_search RPC.
  final String? query;
}

/// The Watch tab.
///
/// Rebuilt from a flat `ListView` into a sliver shell so the tab has an
/// actual hierarchy: a floating app bar, the Home LIVE deck, a filter
/// rail that PINS under the bar, then contextual shelves and the feed.
///
/// Three things drove the redesign:
///
/// 1. Everything used to be drawn at one visual weight — three identical
///    168dp rails — so nothing read as more important than anything else.
///    Each shelf now has its own card shape (see watch_cards.dart).
/// 2. 1,424 playlists and 22,585 playlist items had been syncing since
///    patch_154 and were shown on no screen at all. They are the library's
///    most bingeable asset, and they are now the Series shelf.
/// 3. ~4.7k of the synced videos are a minute or under. They get a proper
///    9:16 rail and a full-screen vertical feed instead of being flattened
///    into the same 16:9 cards as a 47-minute sermon.
class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key});

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> with NavVisibilityMixin {
  final ScrollController _scroll = ScrollController();

  // Shelves.
  List<YoutubeVideo> _liveNow = const [];
  List<ResumeItem> _continue = const [];
  List<YoutubeVideo> _upcoming = const [];
  List<YoutubeVideo> _shorts = const [];
  List<YoutubeChannel> _channels = const [];
  List<YoutubePlaylist> _series = const [];
  List<SeriesProgress> _continueSeries = const [];
  List<YoutubeVideo> _sabbath = const [];
  Set<String> _saved = <String>{};
  Set<String> _reminders = WatchReminderService.all();

  // The paged feed under the chips.
  final List<YoutubeVideo> _feed = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  static const _page = 20;

  _Filter _filter = _Filter.all;

  bool get _isSabbath => SabbathService.isSabbathNow();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _bootstrap();
    // The interstitial that used to fire here has moved to the player
    // (every third video). A full-screen ad on tab entry landed on the
    // exact moment Watch needs to feel instant, and nothing this tab is
    // measured against does that.
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // ------------------------------ loading -----------------------------
  Future<void> _bootstrap() async {
    // Cache-first: paint everything we already know synchronously so a
    // warm cache never shows a shimmer, then correct from the network.
    if (_feed.isEmpty && _filter == _Filter.all) {
      _liveNow = YoutubeService.cachedLiveNow();
      _continue = YoutubeService.cachedContinueWatching();
      _upcoming = YoutubeService.cachedUpcoming();
      _shorts = YoutubeService.cachedShorts();
      _series = YoutubeService.cachedSeries();
      _saved = YoutubeService.cachedBookmarkIds();
      final cached = YoutubeService.cachedFeed();
      if (cached.isNotEmpty) {
        _feed.addAll(cached);
        _loading = false;
      }
    }
    if (mounted) setState(() => _loading = _feed.isEmpty);

    // The feed is the tab's primary content, so it goes out NOW, next to
    // the shelves rather than behind them. It used to be awaited AFTER
    // this Future.wait, which meant it could not even be requested until
    // the slowest of nine shelf calls had come back — and one of those,
    // fetchContinueSeries, is itself three sequential round trips
    // (history -> playlist_items -> playlists). On a slow mobile
    // connection that stacked four round trips ahead of the first video
    // appearing. Every query behind these is indexed and runs in 3-5ms;
    // the wait was never the database, it was the queueing.
    final feedFuture = _loadMore(reset: true);

    final results = await Future.wait<Object?>([
      YoutubeService.fetchLiveNow(),
      YoutubeService.fetchContinueWatching(),
      YoutubeService.fetchUpcoming(),
      YoutubeService.fetchBookmarkIds(),
      YoutubeService.fetchShorts(limit: 12),
      YoutubeService.fetchChannels(),
      YoutubeService.fetchSeries(limit: 20),
      YoutubeService.fetchContinueSeries(),
      if (_isSabbath) YoutubeService.fetchSabbathLineup(),
    ]);
    if (!mounted) return;

    _liveNow = results[0] as List<YoutubeVideo>;
    _continue = results[1] as List<ResumeItem>;
    _upcoming = results[2] as List<YoutubeVideo>;
    _saved = results[3] as Set<String>;
    _shorts = results[4] as List<YoutubeVideo>;
    _channels = results[5] as List<YoutubeChannel>;
    _series = results[6] as List<YoutubePlaylist>;
    _continueSeries = results[7] as List<SeriesProgress>;
    _sabbath = results.length > 8
        ? results[8] as List<YoutubeVideo>
        : const <YoutubeVideo>[];

    // Live channels sort to the front of the channel row so the red ring
    // is the first thing the eye lands on.
    final live = {for (final v in _liveNow) v.channelId};
    _channels = [
      ..._channels.where((c) => c.isLive || live.contains(c.channelId)),
      ..._channels.where((c) => !c.isLive && !live.contains(c.channelId)),
    ];

    // Broadcasts that have been and gone shouldn't keep a pending
    // notification or a lit bell.
    await WatchReminderService.prune(_upcoming);
    _reminders = WatchReminderService.all();

    await feedFuture;
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMore({bool reset = false}) async {
    if (_loadingMore || (!_hasMore && !reset)) return;
    _loadingMore = true;
    if (reset) {
      // Paging state resets now, but `_feed` is deliberately NOT cleared
      // here — see the setState below. Clearing before the request goes
      // out would blank the cached page for the whole round trip.
      _offset = 0;
      _hasMore = true;
    }
    final filter = _filter;

    List<YoutubeVideo> rows;
    switch (filter) {
      case _Filter.saved:
        rows = _offset == 0 ? await YoutubeService.fetchBookmarks() : const [];
      case _Filter.shorts:
        rows = await YoutubeService.fetchShorts(limit: _page, offset: _offset);
      case _Filter.series:
        // The Series filter pages playlists, not videos — handled in
        // _loadMoreSeries so the feed list stays a list of videos.
        rows = const [];
        await _loadMoreSeries(reset: reset);
      case _Filter.following:
        rows = await YoutubeService.fetchSubscriptionFeed(
          limit: _page,
          offset: _offset,
        );
      case _Filter.all:
        rows = await YoutubeService.fetchFeed(limit: _page, offset: _offset);
      case _Filter.sermons:
      case _Filter.bibleStudy:
      case _Filter.music:
      case _Filter.prophecy:
        rows = await YoutubeService.search(
          filter.query!,
          limit: _page,
          offset: _offset,
        );
    }

    // A filter change mid-flight must not append the old filter's rows.
    if (!mounted || filter != _filter) {
      _loadingMore = false;
      return;
    }
    setState(() {
      // Swap the cached page out only once the fresh rows are in hand,
      // so a refresh never flashes an empty feed.
      if (reset) _feed.clear();
      _feed.addAll(rows);
      _offset = _feed.length;
      _hasMore = rows.length == _page;
      _loadingMore = false;
    });
  }

  /// Paging for the Series filter, which browses playlists.
  List<YoutubePlaylist> _seriesBrowse = const [];
  bool _seriesHasMore = true;

  bool _seriesLoading = false;

  Future<void> _loadMoreSeries({bool reset = false}) async {
    if (reset) {
      _seriesBrowse = const [];
      _seriesHasMore = true;
    }
    // Without this guard a fast scroll fires the tail trigger several
    // times and the same page gets appended twice.
    if (_seriesLoading || !_seriesHasMore) return;
    _seriesLoading = true;
    final rows = await YoutubeService.fetchSeries(
      limit: 30,
      offset: _seriesBrowse.length,
    );
    _seriesLoading = false;
    if (!mounted || _filter != _Filter.series) return;
    setState(() {
      _seriesBrowse = [..._seriesBrowse, ...rows];
      _seriesHasMore = rows.length == 30;
    });
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 700) {
      if (_filter == _Filter.series) {
        _loadMoreSeries();
      } else {
        _loadMore();
      }
    }
  }

  void _selectFilter(_Filter next) {
    if (_filter == next) return;
    setState(() {
      _filter = next;
      _feed.clear();
      _seriesBrowse = const [];
      _seriesHasMore = true;
      _offset = 0;
      _hasMore = true;
    });
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
    _loadMore(reset: true);
  }

  // ----------------------------- navigation ---------------------------
  void _open(YoutubeVideo v) => context.pushNamed(
        'watch_video',
        pathParameters: {'id': v.videoId},
        extra: v,
      );

  void _openSeries(YoutubePlaylist p, {int startAt = 0}) => context.pushNamed(
        'watch_series',
        pathParameters: {'playlistId': p.playlistId},
        queryParameters: startAt > 0 ? {'from': '$startAt'} : const {},
        extra: p,
      );

  void _openShorts(List<YoutubeVideo> shorts, int index) => context.pushNamed(
        'watch_shorts',
        extra: ShortsArgs(shorts: shorts, initialIndex: index),
      );

  Future<void> _toggleSave(YoutubeVideo v) async {
    final saved = !_saved.contains(v.videoId);
    setState(() => saved ? _saved.add(v.videoId) : _saved.remove(v.videoId));
    await YoutubeService.setBookmarked(v.videoId, saved);
  }

  /// Reminders are device-local, so this can fail for reasons the user
  /// should hear about — no start time, notifications denied — rather
  /// than leaving a bell lit that will never ring.
  Future<void> _toggleReminder(YoutubeVideo v) async {
    final wasSet = _reminders.contains(v.videoId);
    setState(() {
      _reminders = {..._reminders};
      wasSet ? _reminders.remove(v.videoId) : _reminders.add(v.videoId);
    });

    final nowSet = await WatchReminderService.toggle(v);
    if (!mounted) return;

    if (nowSet != !wasSet) {
      // Scheduling was refused — put the bell back where it was.
      setState(() {
        _reminders = {..._reminders};
        nowSet ? _reminders.add(v.videoId) : _reminders.remove(v.videoId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't set that reminder — check notifications "
              'are allowed for Advent Connect ZW.'),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          nowSet
              ? "We'll remind you 10 minutes before it starts."
              : 'Reminder removed.',
        ),
      ),
    );
  }

  Future<void> _dismissResume(ResumeItem item) async {
    setState(() {
      _continue = [..._continue]..removeWhere(
          (e) => e.video.videoId == item.video.videoId,
        );
    });
    await YoutubeService.dismissFromContinueWatching(item.video.videoId);
  }

  // -------------------------------- build -----------------------------
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      body: NotificationListener<UserScrollNotification>(
        onNotification: handleNavScroll,
        child: ContentReveal(
          loading: _loading,
          skeleton: ShimmerLoaders.watchList(),
          child: BrandedRefreshIndicator(
            color: AppColors.primaryBlue,
            onRefresh: _bootstrap,
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                _appBar(),
                // The LIVE deck sits ABOVE the filter rail: a service
                // going out right now outranks the filter you last
                // picked. Everything else sits below, so the chips stay
                // near the top of the scroll instead of behind six
                // shelves.
                if (_filter == _Filter.all && _liveNow.isNotEmpty)
                  SliverToBoxAdapter(
                    child: LiveBanner(live: _liveNow, onTap: _open),
                  ),
                _filterBar(palette),
                if (_filter == _Filter.all) ..._shelfSlivers(palette),
                ..._feedSlivers(palette),
                // Room for the floating navigation island.
                const SliverToBoxAdapter(child: SizedBox(height: 96)),
              ],
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

  // ------------------------------- app bar ----------------------------
  Widget _appBar() {
    final palette = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SliverAppBar(
      // Pinned, not floating. The filter rail below is itself pinned, and
      // with a floating bar it ended up pinning to the top of the VIEWPORT
      // — which starts behind the status bar — so the chips slid under the
      // notch as soon as you scrolled. Keeping the toolbar on screen gives
      // the rail something to pin beneath, and keeps "Watch" always visible.
      pinned: true,
      floating: false,
      snap: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      // Flat light header on the scaffold colour — same language as
      // ScreenHero everywhere else. The old navy gradient lived in a
      // childless DecoratedBox, which collapses to zero height, so it
      // never painted and left the white "Watch" invisible on light grey.
      backgroundColor: palette.scaffoldBg,
      foregroundColor: palette.text,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      ),
      titleSpacing: AppSpace.lg,
      title: Row(
        children: [
          Text(
            'Watch',
            style: AppTextStyles.titleLarge.copyWith(
              color: palette.text,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          Text(
            '.',
            style: AppTextStyles.titleLarge.copyWith(
              color: AppColors.goldAccent,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Search',
          icon: const Icon(Icons.search_rounded),
          onPressed: () => context.pushNamed('search'),
        ),
        IconButton(
          tooltip: 'Saved',
          icon: const Icon(Icons.bookmark_border_rounded),
          onPressed: () => context.pushNamed('watch_saved'),
        ),
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (v) {
            if (v == 'submit') _openSubmitSheet();
            if (v == 'channels') context.pushNamed('watch_channels');
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'channels', child: Text('Browse channels')),
            PopupMenuItem(value: 'submit', child: Text('Submit your channel')),
          ],
        ),
      ],
    );
  }

  // ------------------------- "All" shelves ----------------------------
  /// The contextual shelves under the filter rail. The LIVE deck is not
  /// here — it sits above the rail (see build).
  List<Widget> _shelfSlivers(AppPalette palette) {
    final shelves = <Widget>[];

    if (_isSabbath && _sabbath.isNotEmpty) {
      shelves.add(_sabbathShelf(palette));
    }

    if (_channels.isNotEmpty) shelves.add(_channelRow());
    if (_continue.isNotEmpty) shelves.add(_keepWatchingShelf());
    if (_continueSeries.isNotEmpty) shelves.add(_continueSeriesShelf());
    if (_shorts.isNotEmpty) shelves.add(_shortsShelf());
    if (_series.isNotEmpty) shelves.add(_seriesShelf());
    if (_upcoming.isNotEmpty) shelves.add(_upcomingShelf());

    return [
      for (var i = 0; i < shelves.length; i++)
        SliverToBoxAdapter(
          child: StaggeredReveal(index: i, rise: 16, child: shelves[i]),
        ),
    ];
  }

  Widget _channelRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WatchSectionHeader(
          title: 'Channels',
          actionLabel: 'All ${_channels.length}',
          onAction: () => context.pushNamed('watch_channels'),
        ),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
            itemCount: _channels.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpace.md),
            itemBuilder: (_, i) => ChannelRing(
              channel: _channels[i],
              onTap: () => context.pushNamed(
                'watch_channel',
                pathParameters: {'channelId': _channels[i].channelId},
                extra: _channels[i],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _keepWatchingShelf() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const WatchSectionHeader(
          title: 'Keep watching',
          icon: Icons.history_rounded,
        ),
        SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
            itemCount: _continue.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpace.md),
            itemBuilder: (_, i) => ResumeCard(
              item: _continue[i],
              onTap: () => _open(_continue[i].video),
              onDismiss: () => _dismissResume(_continue[i]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _continueSeriesShelf() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const WatchSectionHeader(
          title: 'Continue the series',
          icon: Icons.playlist_play_rounded,
        ),
        for (final s in _continueSeries.take(3)) ...[
          ContinueSeriesCard(
            progress: s,
            onTap: () => _openSeries(s.playlist, startAt: s.nextPosition),
          ),
          const SizedBox(height: AppSpace.sm),
        ],
      ],
    );
  }

  Widget _shortsShelf() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WatchSectionHeader(
          title: 'Shorts',
          icon: Icons.bolt_rounded,
          // Opens the full-screen vertical feed, not the grid. Shorts are a
          // format you swipe through, and burying that behind a grid of
          // thumbnails hid the only part of it that feels like shorts. The
          // grid still exists on the Shorts filter chip for people who want
          // to pick a specific clip.
          actionLabel: 'Watch',
          onAction: () => _openShorts(_shorts, 0),
        ),
        SizedBox(
          height: 116 * 16 / 9,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
            itemCount: _shorts.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpace.sm + 2),
            itemBuilder: (_, i) => ShortCard(
              video: _shorts[i],
              onTap: () => _openShorts(_shorts, i),
            ),
          ),
        ),
      ],
    );
  }

  Widget _seriesShelf() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WatchSectionHeader(
          title: 'Series & playlists',
          icon: Icons.video_library_rounded,
          actionLabel: 'Browse',
          onAction: () => _selectFilter(_Filter.series),
        ),
        SizedBox(
          height: 138 + 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
            itemCount: _series.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpace.md),
            itemBuilder: (_, i) => SeriesCard(
              playlist: _series[i],
              onTap: () => _openSeries(_series[i]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _upcomingShelf() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const WatchSectionHeader(
          title: 'Upcoming live',
          icon: Icons.event_rounded,
        ),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
            itemCount: _upcoming.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpace.md),
            itemBuilder: (_, i) => UpcomingCard(
              video: _upcoming[i],
              onTap: () => _open(_upcoming[i]),
              reminderSet: _reminders.contains(_upcoming[i].videoId),
              onToggleReminder: () => _toggleReminder(_upcoming[i]),
            ),
          ),
        ),
      ],
    );
  }

  /// Friday sundown to Saturday sundown, Watch leads with worship. The
  /// sunset window is already computed on-device by SabbathService — no
  /// new data, and it is the one thing YouTube structurally cannot do.
  Widget _sabbathShelf(AppPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.xl,
            AppSpace.lg,
            AppSpace.md,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.sm + 2,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.goldAccent,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  'HAPPY SABBATH',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.darkNavy,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  'Today’s lineup',
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w800,
                    color: palette.text,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
            itemCount: _sabbath.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpace.md),
            itemBuilder: (_, i) => ResumeCard(
              // Reuses the wide card shape, but as a recommendation: no
              // progress bar and the runtime instead of "time left".
              item: ResumeItem(
                video: _sabbath[i],
                positionSeconds: 0,
                durationSeconds: _sabbath[i].durationSeconds,
              ),
              showProgress: false,
              onTap: () => _open(_sabbath[i]),
            ),
          ),
        ),
      ],
    );
  }

  // ------------------------------ filter bar --------------------------
  Widget _filterBar(AppPalette palette) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _FilterBarDelegate(
        palette: palette,
        selected: _filter,
        onSelect: _selectFilter,
      ),
    );
  }

  // -------------------------------- feed ------------------------------
  List<Widget> _feedSlivers(AppPalette palette) {
    if (_filter == _Filter.series) return _seriesGridSlivers(palette);
    if (_filter == _Filter.shorts) return _shortsGridSlivers(palette);

    if (_feed.isEmpty && !_loading) {
      return [
        SliverToBoxAdapter(
          child: _emptyState(
            palette,
            switch (_filter) {
              _Filter.saved => 'Nothing saved yet.',
              _Filter.following =>
                'Follow a channel and its newest videos land here.',
              _ => 'No videos here yet.',
            },
          ),
        ),
      ];
    }

    return [
      SliverList.builder(
        itemCount: _feed.length,
        itemBuilder: (context, i) {
          final card = YoutubeVideoCard(
            video: _feed[i],
            onTap: () => _open(_feed[i]),
            saved: _saved.contains(_feed[i].videoId),
            onSaveToggle: () => _toggleSave(_feed[i]),
          );
          final child = i < 5
              ? StaggeredReveal(index: i, rise: 18, child: card)
              : card;
          // One sponsored card, after the 8th video, keeps the browse feed
          // earning without an interstitial interrupting it.
          //
          // It used to repeat every 8 videos in an unbounded list. Appodeal
          // has a SINGLE shared MREC view per process, so on a long scroll
          // those cards fought each other: whichever mounted last took the
          // native view and every other one rendered an empty box. One card
          // is the real capacity. See AdViewSlot.
          if (i == 7) {
            return Column(children: [child, const FeedAdCard()]);
          }
          return child;
        },
      ),
      if (_loadingMore)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(AppSpace.lg),
            child: Center(child: BrandSpinner(size: 28)),
          ),
        ),
    ];
  }

  List<Widget> _shortsGridSlivers(AppPalette palette) {
    if (_feed.isEmpty && !_loading) {
      return [
        SliverToBoxAdapter(child: _emptyState(palette, 'No shorts yet.')),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: AppSpace.sm + 2,
            crossAxisSpacing: AppSpace.sm + 2,
            childAspectRatio: 9 / 16,
          ),
          itemCount: _feed.length,
          itemBuilder: (context, i) => ShortCard(
            video: _feed[i],
            width: double.infinity,
            onTap: () => _openShorts(_feed, i),
          ),
        ),
      ),
      if (_loadingMore)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(AppSpace.lg),
            child: Center(child: BrandSpinner(size: 28)),
          ),
        ),
    ];
  }

  List<Widget> _seriesGridSlivers(AppPalette palette) {
    if (_seriesBrowse.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: _loading
              ? const SizedBox.shrink()
              : _emptyState(palette, 'No series yet.'),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: AppSpace.lg,
            crossAxisSpacing: AppSpace.md,
            // Square art plus two lines of title.
            childAspectRatio: 0.78,
          ),
          itemCount: _seriesBrowse.length,
          itemBuilder: (context, i) => SeriesCard(
            playlist: _seriesBrowse[i],
            width: double.infinity,
            onTap: () => _openSeries(_seriesBrowse[i]),
          ),
        ),
      ),
    ];
  }

  Widget _emptyState(AppPalette palette, String message) {
    return Padding(
      padding: const EdgeInsets.all(AppSpace.xxl + 8),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.ondemand_video_rounded,
              size: 40,
              color: palette.textMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              message,
              style: AppTextStyles.bodyMedium.copyWith(color: palette.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------- Submit channel -------------------------
  Future<void> _openSubmitSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (_) => const _SubmitChannelSheet(),
    );
  }
}

/// The pinned chip rail. Kept in a delegate rather than a plain sliver so
/// the filter stays reachable at any scroll depth — on a 40,000-video
/// library, scrolling back to the top to change filter is the difference
/// between browsing and giving up.
class _FilterBarDelegate extends SliverPersistentHeaderDelegate {
  _FilterBarDelegate({
    required this.palette,
    required this.selected,
    required this.onSelect,
  });

  final AppPalette palette;
  final _Filter selected;
  final ValueChanged<_Filter> onSelect;

  static const double _height = 54;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return Container(
      height: _height,
      decoration: BoxDecoration(
        color: palette.scaffoldBg,
        border: Border(
          bottom: BorderSide(
            color: overlaps || shrinkOffset > 0
                ? palette.divider
                : Colors.transparent,
          ),
        ),
      ),
      alignment: Alignment.centerLeft,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
        itemCount: _Filter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpace.sm),
        itemBuilder: (_, i) {
          final f = _Filter.values[i];
          return Center(
            child: WatchFilterChip(
              label: f.label,
              selected: f == selected,
              icon: switch (f) {
                _Filter.following => Icons.subscriptions_rounded,
                _Filter.shorts => Icons.bolt_rounded,
                _Filter.series => Icons.video_library_rounded,
                _Filter.saved => Icons.bookmark_rounded,
                _ => null,
              },
              onTap: () => onSelect(f),
            ),
          );
        },
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _FilterBarDelegate old) =>
      old.selected != selected || old.palette != palette;
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
            borderRadius: BorderRadius.circular(AppRadius.button),
            borderSide: BorderSide(color: palette.divider),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.md,
          ),
        );
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpace.lg,
        right: AppSpace.lg,
        top: AppSpace.lg + 2,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpace.lg + 2,
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
          const SizedBox(height: AppSpace.xs),
          Text(
            'Adventist creator? Send your channel for review. Approved channels '
            'appear in Watch.',
            style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: AppSpace.lg),
          TextField(
            controller: _link,
            decoration: deco('YouTube channel link or @handle'),
          ),
          const SizedBox(height: AppSpace.md - 2),
          TextField(controller: _name, decoration: deco('Your name (optional)')),
          const SizedBox(height: AppSpace.md - 2),
          TextField(
            controller: _contact,
            decoration: deco('WhatsApp / email (so we can verify)'),
          ),
          const SizedBox(height: AppSpace.md - 2),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            decoration: deco('A short note (optional)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpace.md - 2),
            Text(
              _error!,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.red),
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                padding: const EdgeInsets.symmetric(vertical: AppSpace.md + 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
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
