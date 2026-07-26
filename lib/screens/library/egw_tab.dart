import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/share_config.dart';
import '../../models/library_item_model.dart';
import '../../services/cache_service.dart';
import '../../services/download_service.dart';
import '../../services/library_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/motion/staggered_reveal.dart';
import 'pdf_viewer_screen.dart';

/// Library → EGW Books tab.
///
/// A real bookshelf rather than a file list: cover grid, a resume-reading
/// hero with live progress, search, favourites, and a per-book progress ring.
/// Reading state comes from [PdfProgress], which the PDF reader writes as you
/// turn pages, so "continue where you left off" works across app restarts and
/// offline.
class EgwTab extends StatefulWidget {
  const EgwTab({super.key, this.kind = 'egw_book'});

  /// Library content kind. Defaults to EGW books; the shelf works for any
  /// uploaded-PDF kind.
  final String kind;

  @override
  State<EgwTab> createState() => _EgwTabState();
}

enum _ShelfFilter { all, reading, saved }

class _EgwTabState extends State<EgwTab> with AutomaticKeepAliveClientMixin {
  final _searchCtrl = TextEditingController();

  late Future<List<LibraryItem>> _future;
  List<LibraryItem> _all = const [];
  String _query = '';
  _ShelfFilter _filter = _ShelfFilter.all;
  bool _grid = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = _load();
    EgwPrefs.revision.addListener(_onPrefs);
  }

  @override
  void dispose() {
    EgwPrefs.revision.removeListener(_onPrefs);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onPrefs() {
    if (mounted) setState(() {});
  }

  Future<List<LibraryItem>> _load() async {
    final items = await LibraryService.fetchItems(widget.kind);
    if (mounted) setState(() => _all = items);
    return items;
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    await future;
  }

  List<LibraryItem> get _visible {
    final saved = EgwPrefs.saved();
    final q = _query.trim().toLowerCase();
    return _all.where((item) {
      switch (_filter) {
        case _ShelfFilter.reading:
          if (!PdfProgress.hasStarted(item.fileUrl)) return false;
        case _ShelfFilter.saved:
          if (!saved.contains(item.id)) return false;
        case _ShelfFilter.all:
          break;
      }
      if (q.isEmpty) return true;
      return '${item.title} ${item.author ?? ''}'.toLowerCase().contains(q);
    }).toList();
  }

  /// The most recently opened book that isn't finished — powers the hero.
  LibraryItem? get _continueBook {
    final started =
        _all.where((i) => PdfProgress.hasStarted(i.fileUrl)).toList();
    if (started.isEmpty) return null;
    started.sort((a, b) {
      final at = EgwPrefs.lastOpenedAt(a.id) ?? 0;
      final bt = EgwPrefs.lastOpenedAt(b.id) ?? 0;
      return bt.compareTo(at);
    });
    return started.first;
  }

  void _open(LibraryItem item) {
    EgwPrefs.noteOpened(item.id);
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) =>
                PdfViewerScreen(title: item.title, url: item.fileUrl),
          ),
        )
        // Progress changes while reading; refresh the shelf on the way back.
        .then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return BrandedRefreshIndicator(
      color: AppColors.primaryBlue,
      onRefresh: _refresh,
      child: FutureBuilder<List<LibraryItem>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              _all.isEmpty) {
            return const Center(child: BrandSpinner(size: 30));
          }
          if (_all.isEmpty) return _emptyShelf(context);

          final visible = _visible;
          final resume = _continueBook;
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (resume != null && _query.isEmpty &&
                  _filter == _ShelfFilter.all)
                SliverToBoxAdapter(
                  child: _ContinueReadingCard(
                    item: resume,
                    onTap: () => _open(resume),
                  ),
                ),
              SliverToBoxAdapter(child: _searchField(context)),
              SliverToBoxAdapter(child: _filterRow(context)),
              if (visible.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _emptyFiltered(context),
                )
              else if (_grid)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 16,
                      // Cover (2:3) + two text lines + progress bar.
                      childAspectRatio: 0.50,
                    ),
                    itemCount: visible.length,
                    itemBuilder: (context, i) => StaggeredReveal(
                      index: i,
                      child: _BookCover(
                        item: visible[i],
                        onTap: () => _open(visible[i]),
                        onLongPress: () => _openBookSheet(visible[i]),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                  sliver: SliverList.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => StaggeredReveal(
                      index: i,
                      child: _BookRow(
                        item: visible[i],
                        onTap: () => _open(visible[i]),
                        onMore: () => _openBookSheet(visible[i]),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ---- Controls -----------------------------------------------------------

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
          hintText: 'Search books or authors…',
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
    final palette = context.palette;
    final readingCount =
        _all.where((i) => PdfProgress.hasStarted(i.fileUrl)).length;
    final savedCount = EgwPrefs.saved().length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip(context, 'All library', _ShelfFilter.all, null),
                  const SizedBox(width: 8),
                  _chip(context, 'Reading', _ShelfFilter.reading, readingCount),
                  const SizedBox(width: 8),
                  _chip(context, 'Saved', _ShelfFilter.saved, savedCount),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: _grid ? 'List view' : 'Shelf view',
            icon: Icon(
              _grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
              color: palette.textMuted,
              size: 21,
            ),
            onPressed: () => setState(() => _grid = !_grid),
          ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    String label,
    _ShelfFilter value,
    int? count,
  ) {
    final palette = context.palette;
    final selected = _filter == value;
    return Pressable(
      onTap: () => setState(() => _filter = value),
      child: AnimatedContainer(
        duration: AppMotion.quick,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryBlue : palette.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primaryBlue : palette.divider,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
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
                      ? AppColors.white.withValues(alpha: 0.82)
                      : palette.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---- Book sheet ---------------------------------------------------------

  Future<void> _openBookSheet(LibraryItem item) async {
    final palette = context.palette;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        final isSaved = EgwPrefs.saved().contains(item.id);
        final started = PdfProgress.hasStarted(item.fileUrl);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _cover(item, width: 54, height: 78, radius: 8),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.titleSmall
                                .copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.author?.isNotEmpty ?? false
                                ? item.author!
                                : 'Ellen G. White',
                            style: AppTextStyles.bodySmall
                                .copyWith(color: palette.textMuted),
                          ),
                          if (started) ...[
                            const SizedBox(height: 5),
                            Text(
                              PdfProgress.positionLabel(item.fileUrl) ?? '',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: AppColors.primaryBlue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: palette.divider, height: 1),
              ListTile(
                leading: Icon(
                  isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                  color: isSaved ? AppColors.goldAccent : palette.textMuted,
                ),
                title: Text(isSaved ? 'Remove from saved' : 'Save to shelf',
                    style: AppTextStyles.bodyMedium),
                onTap: () async {
                  await EgwPrefs.toggleSaved(item.id);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
              ),
              if (started)
                ListTile(
                  leading: Icon(Icons.restart_alt_rounded,
                      color: palette.textMuted),
                  title: Text('Start from the beginning',
                      style: AppTextStyles.bodyMedium),
                  onTap: () async {
                    await CacheService.deletePref(
                        PdfProgress.lastPageKey(item.fileUrl));
                    EgwPrefs.revision.value++;
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                ),
              ListTile(
                leading: Icon(Icons.download_outlined, color: palette.textMuted),
                title:
                    Text('Save a copy', style: AppTextStyles.bodyMedium),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final ok = await DownloadService.downloadAndShare(
                    url: item.fileUrl,
                    suggestedName: item.title,
                    mimeType: 'application/pdf',
                  );
                  if (mounted) DownloadService.toast(context, ok);
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
                    '${(item.author?.isNotEmpty ?? false) ? ' by ${item.author}' : ''}'
                    '\n\nReading on Advent Connect ZW — get the app:\n'
                    '$appDownloadUrl',
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

  // ---- Empty states -------------------------------------------------------

  Widget _emptyShelf(BuildContext context) {
    final palette = context.palette;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 100),
        Icon(Icons.auto_stories_outlined, size: 60, color: palette.textMuted),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'Ellen G. White books will appear here once added.',
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
      _ShelfFilter.reading => (
          Icons.auto_stories_outlined,
          'Books you open will appear here,\nready to resume where you stopped.',
        ),
      _ShelfFilter.saved => (
          Icons.bookmark_border_rounded,
          'Save books to build your own shelf.\nHold any cover to save it.',
        ),
      _ShelfFilter.all => (
          Icons.search_off_rounded,
          'No book matches "$_query".',
        ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 50, 40, 60),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 52, color: palette.textMuted),
          const SizedBox(height: 14),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium
                .copyWith(color: palette.textMuted, height: 1.55),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Shared cover widget
// ---------------------------------------------------------------------------

Widget _cover(
  LibraryItem item, {
  required double width,
  required double height,
  double radius = 10,
}) {
  final hasCover = item.coverUrl != null && item.coverUrl!.isNotEmpty;
  return ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: SizedBox(
      width: width,
      height: height,
      child: hasCover
          ? CachedImage(item.coverUrl!, fit: BoxFit.cover)
          : DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1A2F5A), AppColors.darkNavy],
                ),
              ),
              // A generated spine-style cover beats a generic file icon when
              // the upload has no artwork — most of them won't.
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.auto_stories_rounded,
                        color: AppColors.goldAccent, size: 20),
                    const SizedBox(height: 6),
                    Text(
                      item.title,
                      maxLines: 3,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 9,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    ),
  );
}

// ---------------------------------------------------------------------------
//  Continue reading hero
// ---------------------------------------------------------------------------

class _ContinueReadingCard extends StatelessWidget {
  const _ContinueReadingCard({required this.item, required this.onTap});

  final LibraryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = PdfProgress.progressFor(item.fileUrl) ?? 0;
    final label = PdfProgress.positionLabel(item.fileUrl);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Pressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            gradient: AppColors.appBarGradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppColors.darkNavy.withValues(alpha: 0.3),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            children: [
              _cover(item, width: 56, height: 80, radius: 9),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CONTINUE READING',
                      style: AppTextStyles.overline.copyWith(
                        color: AppColors.goldAccent,
                        fontSize: 9,
                        letterSpacing: 1.3,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: progress),
                        duration: AppMotion.entrance,
                        curve: AppMotion.easeOut,
                        builder: (context, v, _) => LinearProgressIndicator(
                          value: v,
                          minHeight: 4,
                          backgroundColor:
                              AppColors.white.withValues(alpha: 0.2),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.goldAccent),
                        ),
                      ),
                    ),
                    if (label != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        label,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.white.withValues(alpha: 0.72),
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.play_circle_fill_rounded,
                  color: AppColors.white, size: 34),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Grid cover
// ---------------------------------------------------------------------------

class _BookCover extends StatelessWidget {
  const _BookCover({
    required this.item,
    required this.onTap,
    required this.onLongPress,
  });

  final LibraryItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final progress = PdfProgress.progressFor(item.fileUrl);
    final isSaved = EgwPrefs.saved().contains(item.id);
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 9,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: _cover(item,
                        width: double.infinity,
                        height: double.infinity,
                        radius: 11),
                  ),
                ),
                if (isSaved)
                  const Positioned(
                    top: 5,
                    right: 5,
                    child: Icon(Icons.bookmark_rounded,
                        color: AppColors.goldAccent, size: 17),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelSmall.copyWith(
              color: palette.text,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          if (progress != null) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: palette.divider,
                valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.primaryBlue),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  List row
// ---------------------------------------------------------------------------

class _BookRow extends StatelessWidget {
  const _BookRow({
    required this.item,
    required this.onTap,
    required this.onMore,
  });

  final LibraryItem item;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final progress = PdfProgress.progressFor(item.fileUrl);
    final isSaved = EgwPrefs.saved().contains(item.id);
    return PressEffect(
      child: Material(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          onLongPress: onMore,
          child: Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.divider),
            ),
            child: Row(
              children: [
                _cover(item, width: 46, height: 66, radius: 8),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleSmall
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          item.author,
                          item.language,
                        ].where((s) => s != null && s.isNotEmpty).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: palette.textMuted),
                      ),
                      if (progress != null) ...[
                        const SizedBox(height: 7),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 3,
                            backgroundColor: palette.divider,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                AppColors.primaryBlue),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isSaved)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.bookmark_rounded,
                        color: AppColors.goldAccent, size: 16),
                  ),
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

// ---------------------------------------------------------------------------
//  Shelf prefs
// ---------------------------------------------------------------------------

/// Saved books + last-opened ordering for the EGW shelf. Local and offline,
/// same pattern as the Bible and Hymnal prefs.
class EgwPrefs {
  EgwPrefs._();

  static const _kSaved = 'egw_saved_v1';
  static const _kOpened = 'egw_opened_at_v1'; // id → epoch ms

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Set<String> saved() {
    final raw = CacheService.readPref(_kSaved);
    if (raw == null) return <String>{};
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> toggleSaved(String id) async {
    final set = saved();
    set.contains(id) ? set.remove(id) : set.add(id);
    await CacheService.writePref(_kSaved, jsonEncode(set.toList()));
    revision.value++;
  }

  static Map<String, int> _opened() {
    final raw = CacheService.readPref(_kOpened);
    if (raw == null) return <String, int>{};
    try {
      return (jsonDecode(raw) as Map)
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    } catch (_) {
      return <String, int>{};
    }
  }

  static int? lastOpenedAt(String id) => _opened()[id];

  static Future<void> noteOpened(String id) async {
    final map = _opened()..[id] = DateTime.now().millisecondsSinceEpoch;
    await CacheService.writePref(_kOpened, jsonEncode(map));
    revision.value++;
  }
}
