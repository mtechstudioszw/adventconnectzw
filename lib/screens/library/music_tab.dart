import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/share_config.dart';
import '../../models/library_item_model.dart';
import '../../services/library_launch_intent.dart';
import '../../services/library_service.dart';
import '../../services/music_download_service.dart';
import '../../services/music_player_service.dart';
import '../../services/music_prefs_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/motion/staggered_reveal.dart';
import 'widgets/music_visuals.dart';

/// Full-screen Audio Bible — opened from a button inside the Bible tab
/// (founder preference: not its own Library tab). Reuses [MusicTab] with the
/// 'audio_bible' kind so it plays through the same background player.
class AudioBibleScreen extends StatelessWidget {
  const AudioBibleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('Audio Bible',
            style: AppTextStyles.appBarTitleFlat.copyWith(fontSize: 18)),
      ),
      body: SafeArea(
        top: false,
        // The mini player is mounted app-wide now (GlobalMediaBars), so
        // this screen no longer carries its own — two would stack.
        child: const MusicTab(
          kind: 'audio_bible',
          emptyText: 'Audio Bible will appear here once it\'s added.',
        ),
      ),
    );
  }
}

/// Which slice of the catalog the browse list is showing.
enum _MusicFilter { all, liked, downloaded }

/// Library → Music tab.
///
/// Browse surface for uploaded worship audio: search, quick filters, a
/// recently-played shelf, shuffle-all, and rich track rows with inline
/// download + like. Playback runs through the shared [MusicPlayerService], so
/// audio keeps going with the app backgrounded and shows lock-screen
/// controls.
class MusicTab extends StatefulWidget {
  const MusicTab({
    super.key,
    this.kind = 'music',
    this.emptyText = 'Music will appear here once it\'s added.',
  });

  /// Library content kind to list — 'music' or 'audio_bible'. Both play
  /// through the same shared [MusicPlayerService].
  final String kind;
  final String emptyText;

  @override
  State<MusicTab> createState() => _MusicTabState();
}

class _MusicTabState extends State<MusicTab>
    with AutomaticKeepAliveClientMixin {
  final _service = MusicPlayerService.instance;
  final _searchCtrl = TextEditingController();

  late Future<List<LibraryItem>> _future;
  List<LibraryItem> _all = const [];
  String _query = '';
  _MusicFilter _filter = _MusicFilter.all;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<List<LibraryItem>> _load() async {
    final items = await LibraryService.fetchItems(widget.kind);
    // Resolve which tracks are already on disk so rows can show the offline
    // badge without each one hitting the filesystem during build.
    await MusicDownloadService.warmPaths(items);
    if (mounted) setState(() => _all = items);
    await _consumeLaunchIntent(items);
    return items;
  }

  /// Starts the track Home asked for, if it asked for one.
  ///
  /// "Music of the day" used to just open this tab, leaving the member to
  /// hunt for the track they had literally just tapped. The queue is seeded
  /// with the whole catalogue from that track's position, so play-next still
  /// works exactly as it does when you tap a row here.
  Future<void> _consumeLaunchIntent(List<LibraryItem> items) async {
    final wanted = LibraryLaunchIntent.takeMusic();
    if (wanted == null || !mounted) return;
    final index = items.indexWhere((i) => i.id == wanted);
    if (index < 0) return;
    await _play(items, index);
  }

  Future<void> _refresh() async {
    final future = _load();
    // Braces, not an arrow: an arrow body returns the assigned Future and
    // `setState` asserts against that, which silently broke pull-to-refresh
    // on every Library tab. See `_EgwTabState._refresh`.
    setState(() {
      _future = future;
    });
    await future;
  }

  /// The catalog after search + filter, in display order.
  List<LibraryItem> get _visible {
    final liked = MusicPrefsService.liked();
    final downloaded = MusicDownloadService.downloadedIds();
    final q = _query.trim().toLowerCase();
    return _all.where((item) {
      switch (_filter) {
        case _MusicFilter.liked:
          if (!liked.contains(item.id)) return false;
        case _MusicFilter.downloaded:
          if (!downloaded.contains(item.id)) return false;
        case _MusicFilter.all:
          break;
      }
      if (q.isEmpty) return true;
      final hay = '${item.title} ${item.author ?? ''}'.toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  /// Tracks from the recently-played list that still exist in this catalog,
  /// newest first. Drives the top shelf.
  List<LibraryItem> get _recent {
    final byId = {for (final item in _all) item.id: item};
    return [
      for (final id in MusicPrefsService.recentIds())
        if (byId.containsKey(id)) byId[id]!,
    ].take(10).toList();
  }

  Future<void> _play(List<LibraryItem> list, int index) async {
    try {
      await _service.setQueueAndPlay(list, index);
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      // Being offline is not an error the member caused, so it does not get
      // the red treatment or the word "Could not". It gets the reason and
      // the way out. Everything else keeps the raw detail, which is what
      // makes a genuine fault reportable.
      final offline = e is OfflineTrackException;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: offline ? AppColors.darkNavy : AppColors.red,
          content: Text(
            offline
                ? OfflineTrackException.message
                : 'Could not play this track: $e',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  /// The real deal is done by [MusicPlayerService.shuffleAll] — see the
  /// three separate reasons the old inline version always played track 0.
  Future<void> _shuffleAll() async {
    final list = _visible;
    if (list.isEmpty) return;
    try {
      await _service.shuffleAll(list);
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not shuffle these tracks: $e',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Both prefs sources feed row badges and the filter counts, so rebuild
    // the whole tab when either changes.
    return ValueListenableBuilder<int>(
      valueListenable: MusicPrefsService.revision,
      builder: (context, _, _) => ValueListenableBuilder<int>(
        valueListenable: MusicDownloadService.revision,
        // The mini player is owned by the Library shell (and by
        // AudioBibleScreen when this tab is used standalone), so it is
        // deliberately NOT rendered here — two bars would stack.
        builder: (context, _, _) => BrandedRefreshIndicator(
          color: AppColors.primaryBlue,
          onRefresh: _refresh,
          child: FutureBuilder<List<LibraryItem>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting &&
                  _all.isEmpty) {
                return const Center(child: BrandSpinner(size: 30));
              }
              if (_all.isEmpty) return _emptyCatalog(context);
              return _browse(context);
            },
          ),
        ),
      ),
    );
  }

  // ---- Browse -------------------------------------------------------------

  Widget _browse(BuildContext context) {
    final visible = _visible;
    final recent = _recent;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _searchField(context)),
        SliverToBoxAdapter(child: _filterRow(context)),
        if (recent.isNotEmpty && _filter == _MusicFilter.all && _query.isEmpty)
          SliverToBoxAdapter(child: _recentShelf(context, recent)),
        SliverToBoxAdapter(child: _listHeader(context, visible.length)),
        if (visible.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _emptyFiltered(context),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList.separated(
              itemCount: visible.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => StaggeredReveal(
                index: i,
                child: _TrackRow(
                  item: visible[i],
                  onPlay: () => _play(visible, i),
                  onMore: () => _openTrackSheet(context, visible[i]),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _searchField(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        textInputAction: TextInputAction.search,
        style: AppTextStyles.bodyMedium.copyWith(color: palette.text),
        decoration: InputDecoration(
          hintText: widget.kind == 'audio_bible'
              ? 'Search books…'
              : 'Search songs or artists…',
          hintStyle: TextStyle(color: palette.textMuted),
          prefixIcon: Icon(Icons.search_rounded, color: palette.textMuted),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close_rounded, color: palette.textMuted),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                ),
          filled: true,
          fillColor: palette.inputFill,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: palette.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: palette.divider),
          ),
        ),
      ),
    );
  }

  Widget _filterRow(BuildContext context) {
    final likedCount = MusicPrefsService.liked().length;
    final downloadedCount = MusicDownloadService.downloadedCount;
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          _chip(context, 'All', _MusicFilter.all, null),
          const SizedBox(width: 8),
          _chip(context, 'Liked', _MusicFilter.liked, likedCount),
          const SizedBox(width: 8),
          _chip(context, 'Downloaded', _MusicFilter.downloaded, downloadedCount),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    String label,
    _MusicFilter value,
    int? count,
  ) {
    final palette = context.palette;
    final selected = _filter == value;
    return Pressable(
      onTap: () => setState(() => _filter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryBlue : palette.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primaryBlue : palette.divider,
          ),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: AppTextStyles.labelMedium.copyWith(
                color: selected ? AppColors.white : palette.text,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (count != null && count > 0) ...[
              const SizedBox(width: 6),
              Text(
                '$count',
                style: AppTextStyles.labelSmall.copyWith(
                  color: selected
                      ? AppColors.white.withValues(alpha: 0.8)
                      : palette.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _recentShelf(BuildContext context, List<LibraryItem> recent) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Text(
            'Jump back in',
            style: AppTextStyles.titleSmall.copyWith(
              fontWeight: FontWeight.w700,
              color: palette.text,
            ),
          ),
        ),
        SizedBox(
          height: 152,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: recent.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final item = recent[i];
              return Pressable(
                onTap: () {
                  final list = _visible;
                  final index = list.indexWhere((e) => e.id == item.id);
                  _play(index >= 0 ? list : [item], index >= 0 ? index : 0);
                },
                child: SizedBox(
                  width: 108,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TrackArtwork(
                        coverUrl: item.coverUrl,
                        size: 108,
                        radius: 14,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: palette.text,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _listHeader(BuildContext context, int count) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Row(
        children: [
          Text(
            '$count ${count == 1 ? 'track' : 'tracks'}',
            style: AppTextStyles.labelMedium.copyWith(color: palette.textMuted),
          ),
          const Spacer(),
          if (count > 1)
            Pressable(
              onTap: _shuffleAll,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shuffle_rounded,
                        color: AppColors.white, size: 17),
                    const SizedBox(width: 7),
                    Text(
                      'Shuffle',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---- Track sheet --------------------------------------------------------

  Future<void> _openTrackSheet(BuildContext context, LibraryItem item) async {
    final palette = context.palette;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        final liked = MusicPrefsService.isLiked(item.id);
        final saved = MusicDownloadService.isDownloaded(item.id);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                child: Row(
                  children: [
                    TrackArtwork(
                        coverUrl: item.coverUrl, size: 52, radius: 10),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.titleSmall
                                .copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            (item.author?.isNotEmpty ?? false)
                                ? item.author!
                                : 'Adventist Super App',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySmall
                                .copyWith(color: palette.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: palette.divider, height: 1),
              ListTile(
                leading: Icon(
                  liked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: liked ? AppColors.red : palette.textMuted,
                ),
                title: Text(liked ? 'Remove from liked' : 'Add to liked',
                    style: AppTextStyles.bodyMedium),
                onTap: () async {
                  await MusicPrefsService.toggleLike(item.id);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
              ),
              ListTile(
                leading: Icon(
                  saved
                      ? Icons.download_done_rounded
                      : Icons.download_outlined,
                  color: saved ? AppColors.successGreen : palette.textMuted,
                ),
                title: Text(
                  saved ? 'Remove download' : 'Download for offline',
                  style: AppTextStyles.bodyMedium,
                ),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _handleDownload(item, saved);
                },
              ),
              ListTile(
                leading:
                    Icon(Icons.ios_share_rounded, color: palette.textMuted),
                title: Text('Share', style: AppTextStyles.bodyMedium),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Share.share(
                    '${item.title}'
                    '${(item.author?.isNotEmpty ?? false) ? ' — ${item.author}' : ''}'
                    '\n\nListening on Adventist Super App:\n$appDownloadUrl',
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleDownload(LibraryItem item, bool saved) async {
    final messenger = ScaffoldMessenger.of(context);
    if (saved) {
      await MusicDownloadService.remove(item.id);
      messenger.showSnackBar(
        const SnackBar(content: Text('Removed from downloads.')),
      );
      return;
    }
    final ok = await MusicDownloadService.download(item);
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Saved for offline listening.'
            : 'Download failed. Check your connection.'),
      ),
    );
  }

  // ---- Empty states -------------------------------------------------------

  Widget _emptyCatalog(BuildContext context) {
    final palette = context.palette;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 100),
        Icon(Icons.library_music_outlined, size: 60, color: palette.textMuted),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            widget.emptyText,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(color: palette.textMuted),
          ),
        ),
      ],
    );
  }

  Widget _emptyFiltered(BuildContext context) {
    final palette = context.palette;
    final (icon, text) = switch (_filter) {
      _MusicFilter.liked => (
          Icons.favorite_border_rounded,
          'Songs you like will collect here.\nTap the heart on any track.',
        ),
      _MusicFilter.downloaded => (
          Icons.download_outlined,
          'Download tracks to listen with no data.\nThey play even in airplane mode.',
        ),
      _MusicFilter.all => (
          Icons.search_off_rounded,
          'Nothing matches "$_query".',
        ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 40, 40, 60),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 52, color: palette.textMuted),
          const SizedBox(height: 14),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: palette.textMuted,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Track row
// ---------------------------------------------------------------------------

/// One track in the browse list: art, title/artist, offline + liked badges,
/// live equalizer when it's the active track, and an overflow menu.
class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.item,
    required this.onPlay,
    required this.onMore,
  });

  final LibraryItem item;
  final VoidCallback onPlay;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final service = MusicPlayerService.instance;
    final isCurrent = service.current?.id == item.id;
    final liked = MusicPrefsService.isLiked(item.id);
    final saved = MusicDownloadService.isDownloaded(item.id);

    return PressEffect(
      child: Material(
        color: isCurrent
            ? AppColors.primaryBlue.withValues(alpha: 0.07)
            : palette.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPlay,
          onLongPress: onMore,
          child: Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isCurrent ? AppColors.primaryBlue : palette.divider,
                width: isCurrent ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    TrackArtwork(
                      coverUrl: item.coverUrl,
                      size: 54,
                      radius: 12,
                      icon: item.kind == 'audio_bible'
                          ? Icons.menu_book_rounded
                          : Icons.music_note_rounded,
                    ),
                    // Live download progress sits on the artwork so the row
                    // doesn't reflow while a track saves.
                    ValueListenableBuilder<Map<String, double>>(
                      valueListenable: MusicDownloadService.progress,
                      builder: (context, map, _) {
                        final value = map[item.id];
                        if (value == null) return const SizedBox.shrink();
                        return Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: SizedBox(
                              width: 26,
                              height: 26,
                              child: CircularProgressIndicator(
                                value: value == 0 ? null : value,
                                strokeWidth: 2.4,
                                color: AppColors.white,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleSmall.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isCurrent
                              ? AppColors.primaryBlue
                              : palette.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              (item.author?.isNotEmpty ?? false)
                                  ? item.author!
                                  : 'Adventist Super App',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: palette.textMuted),
                            ),
                          ),
                          if (item.durationSeconds != null) ...[
                            Text(' · ',
                                style: AppTextStyles.bodySmall
                                    .copyWith(color: palette.textMuted)),
                            Text(
                              formatDuration(
                                  Duration(seconds: item.durationSeconds!)),
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: palette.textMuted),
                            ),
                          ],
                          if (saved) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.download_done_rounded,
                                size: 14, color: AppColors.successGreen),
                          ],
                          if (liked) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.favorite_rounded,
                                size: 13, color: AppColors.red),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (isCurrent)
                  StreamBuilder<PlayerState>(
                    stream: service.player.playerStateStream,
                    builder: (context, snap) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: EqualizerBars(
                        playing: snap.data?.playing ?? false,
                        size: 17,
                      ),
                    ),
                  )
                else
                  Icon(Icons.play_arrow_rounded,
                      color: palette.textMuted, size: 24),
                IconButton(
                  tooltip: 'More',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.more_vert_rounded,
                      color: palette.textMuted, size: 20),
                  onPressed: onMore,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
