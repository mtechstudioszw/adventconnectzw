import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/share_config.dart';
import '../../models/egw_book_model.dart';
import '../../models/library_item_model.dart';
import '../../services/cache_service.dart';
import '../../services/download_service.dart';
import '../../services/egw_book_service.dart';
import '../../services/egw_download_service.dart';
import '../../services/library_launch_intent.dart';
import '../../services/library_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/motion/brand_spinner.dart';
import 'egw_reader_screen.dart';
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
  const EgwTab({super.key, this.kind = egwKind});

  /// The `library_items.kind` EGW books are stored under.
  ///
  /// **It is `egw_book`, never `egw`.** That one string has now caused three
  /// separate production bugs — the Today card's devotion slide queried
  /// `kind='egw'` and found nothing, and the launch-intent guard below tested
  /// against `'egw'` while the widget's own default was `'egw_book'`, so the
  /// guard was never true and "EGW read of the day" never opened its book.
  /// Both were invisible: a wrong kind returns an empty list or falls out of
  /// an `if`, and neither throws.
  ///
  /// So the literal lives here once and everything compares against it.
  static const String egwKind = 'egw_book';

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
    _consumeLaunchIntent(items);
    return items;
  }

  /// Opens the book Home asked for, if it asked for one.
  ///
  /// "EGW read of the day" named a book and then opened the shelf. Only
  /// the EGW tab consumes this, so the music tab's intent is untouched
  /// when both are mounted at once inside the Library's TabBarView.
  void _consumeLaunchIntent(List<LibraryItem> items) {
    // Was `!= 'egw'`, which is never false for this widget — its own default
    // kind is `egw_book` — so this returned early every single time and the
    // book Home had named was silently dropped on the shelf.
    if (widget.kind != EgwTab.egwKind) return;
    final wanted = LibraryLaunchIntent.takeEgw();
    if (wanted == null || !mounted) return;
    for (final item in items) {
      if (item.id == wanted) {
        _open(item);
        return;
      }
    }
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

  /// The most recently opened book — powers the "Continue reading" hero.
  ///
  /// Keyed on [EgwPrefs.lastOpenedAt], which `_open` records unconditionally
  /// for every book the member opens. It used to require
  /// `PdfProgress.hasStarted` as well, and that was the bug: the page is
  /// persisted by the reader's `onPageChanged`, so a book opened and read
  /// WITHOUT swiping never counted as started and was filtered out — the
  /// hero kept offering the previous book (founder, 17 Aug: "Steps to
  /// Christ still has continue reading after I open Great Controversy").
  ///
  /// "Opened" is the honest signal for this hero anyway: it is answering
  /// "what were you last reading", not "what have you made progress in".
  /// The reader now also marks a book started on render, so the two agree
  /// for anything opened from here on.
  LibraryItem? get _continueBook {
    LibraryItem? best;
    var bestAt = 0;
    for (final item in _all) {
      final at = EgwPrefs.lastOpenedAt(item.id) ?? 0;
      // Fall back to progress for books opened before opens were tracked.
      if (at == 0 && !PdfProgress.hasStarted(item.fileUrl)) continue;
      if (best == null || at > bestAt) {
        best = item;
        bestAt = at;
      }
    }
    return best;
  }

  /// Opens a book in the reflowable reader when it has an EPUB, and in the
  /// PDF viewer when it does not.
  ///
  /// The EPUB path is strictly better — text that reflows, real
  /// Day/Sepia/Night, page turns, select-to-quote with the canonical page
  /// number — but it is never assumed: a book with no EPUB, a first open
  /// with no signal, or a file that will not parse all fall through to the
  /// PDF rather than failing. A member must never be told a book they can
  /// see on the shelf cannot be opened.
  Future<void> _open(LibraryItem item) async {
    EgwPrefs.noteOpened(item.id);

    EgwBook? book;
    if (item.hasEpub) {
      // Only show a wait if there IS one — a cached book resolves in the
      // same frame and must not flash a dialog.
      final pending = EgwBookService.load(item.epubUrl);
      book = await _withProgress(item, pending);
    }
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => book != null
            ? EgwReaderScreen(book: book, bookId: item.id)
            // itemId lets the viewer open a deliberately downloaded copy
            // from application support instead of re-fetching, and makes
            // an offline open work at all.
            : PdfViewerScreen(
                title: item.title,
                url: item.fileUrl,
                itemId: item.id,
              ),
      ),
    );
    // Progress changes while reading; refresh the shelf on the way back.
    if (mounted) setState(() {});
  }

  /// Awaits [pending], showing the book being opened only if there is
  /// actually a wait. Downloading a book is a real one on a first open;
  /// reopening one is instant, and a dialog that flashes for 30ms reads as
  /// a glitch.
  ///
  /// Founder, 18 Aug 2026: *"put the book thumbnail at the first when u open
  /// book"*. A bare spinner is what made this wait feel broken rather than
  /// merely slow — it gives no sign that the tap even landed on the right
  /// book. The cover is already on screen and already cached, so it costs
  /// nothing to carry it into the wait, and it turns an anonymous delay into
  /// a book being opened.
  Future<EgwBook?> _withProgress(
    LibraryItem item,
    Future<EgwBook?> pending,
  ) async {
    var settled = false;
    unawaited(pending.whenComplete(() => settled = true));
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (settled || !mounted) return pending;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      // The page's own ground, not a dim over it: this is a screen the book
      // is opening ON, and a scrim would leave the shelf half-visible behind
      // the cover it is meant to be lifting.
      barrierColor: context.palette.scaffoldBg,
      builder: (_) => _OpeningBook(item: item),
    );
    final book = await pending;
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    return book;
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
                        SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 16,
                      // Cover (2:3) + two title lines + progress bar.
                      //
                      // Derived rather than the old fixed 0.50, because a
                      // fixed ratio sets a fixed cell HEIGHT while the
                      // title underneath grows with the system font — at
                      // large text sizes the two lines no longer fit and
                      // the cell overflowed. Measuring the text allowance
                      // against the real text scale keeps the cover
                      // proportion and lets the cell get taller instead.
                      childAspectRatio: _gridAspectRatio(context),
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
                onTap: () {
                  // Pop on the same frame. The sheet used to wait for the
                  // write to land before closing, which is what "save to
                  // shelf doesn't work" looked like from the outside: a
                  // menu item that stayed put after you tapped it.
                  EgwPrefs.toggleSaved(item.id);
                  Navigator.of(ctx).pop();
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
              // READ OFFLINE — distinct from "Save a copy" below, which hands
              // the PDF to the OS share sheet and keeps nothing the app can
              // reopen. This keeps the book inside application support, where
              // the reader picks it up via PdfViewerScreen(itemId:).
              //
              // The viewer already caches whatever it fetches, but into the
              // CACHE directory, which the OS reclaims under storage
              // pressure. That is fine for "I read this once"; it is not what
              // someone means when they download a book before a journey.
              ListTile(
                leading: Icon(
                  EgwDownloadService.isDownloaded(item.id)
                      ? Icons.offline_pin_rounded
                      : Icons.cloud_download_outlined,
                  color: EgwDownloadService.isDownloaded(item.id)
                      ? AppColors.primaryBlue
                      : palette.textMuted,
                ),
                title: Text(
                  EgwDownloadService.isDownloaded(item.id)
                      ? 'Remove download'
                      : 'Read offline',
                  style: AppTextStyles.bodyMedium,
                ),
                subtitle: Text(
                  EgwDownloadService.isDownloaded(item.id)
                      ? 'Frees the space this book is using'
                      : 'Keeps this book on your phone, no data needed',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: palette.textMuted),
                ),
                onTap: () async {
                  final wasDownloaded =
                      EgwDownloadService.isDownloaded(item.id);
                  Navigator.of(ctx).pop();
                  final messenger = ScaffoldMessenger.of(context);
                  if (wasDownloaded) {
                    await EgwDownloadService.remove(item.id);
                    if (!mounted) return;
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Download removed')),
                    );
                    return;
                  }
                  messenger.showSnackBar(
                    SnackBar(content: Text('Downloading ${item.title}…')),
                  );
                  final ok = await EgwDownloadService.download(item);
                  if (!mounted) return;
                  messenger.hideCurrentSnackBar();
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        ok
                            ? '${item.title} is ready to read offline'
                            : 'Could not download ${item.title}. Check your connection.',
                      ),
                    ),
                  );
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
              //
              // Sized against the box it actually got, because this same
              // builder serves the 3-across grid AND the 46x66 thumbnail
              // in list view. The old fixed layout — 20px icon + 6 gap +
              // three 11.25px lines — needs ~60px of the 50px a list-mode
              // cover has, so every EGW book without artwork overflowed
              // the moment you switched to list view.
              child: LayoutBuilder(
                builder: (context, c) {
                  const pad = 8.0;
                  const fontSize = 9.0;
                  const lineHeight = 1.25;
                  final avail = c.maxHeight - pad * 2;
                  // Text scales with the system font; the box doesn't.
                  final line = MediaQuery.textScalerOf(context)
                          .scale(fontSize) *
                      lineHeight;
                  // Icon + its gap only earn their space if at least one
                  // line of title survives alongside them.
                  final showIcon = avail >= 26 + line;
                  final forText = avail - (showIcon ? 26 : 0);
                  final lines = (forText / line).floor().clamp(1, 3);
                  return Padding(
                    padding: const EdgeInsets.all(pad),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showIcon) ...[
                          const Icon(Icons.auto_stories_rounded,
                              color: AppColors.goldAccent, size: 20),
                          const SizedBox(height: 6),
                        ],
                        // Flexible so a mis-estimate clips instead of
                        // painting stripes.
                        Flexible(
                          child: Text(
                            item.title,
                            maxLines: lines,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: fontSize,
                              height: lineHeight,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
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

/// Cell shape for the EGW cover grid: a 2:3 cover plus however much room
/// two lines of title and a progress bar actually need at the viewer's
/// text size.
///
/// Returned as an aspect ratio because that is what the grid delegate
/// takes; the real calculation is in pixels, from the measured cell
/// width, so the covers stay 2:3 on every screen width.
double _gridAspectRatio(BuildContext context) {
  const columns = 3;
  const horizontalPadding = 32.0; // SliverPadding, both sides
  const crossSpacing = 12.0 * (columns - 1);
  final width = MediaQuery.sizeOf(context).width;
  final cellWidth =
      ((width - horizontalPadding - crossSpacing) / columns).clamp(60.0, 260.0);

  // 6 gap + two title lines + 4 gap + 3 progress bar. Only the type
  // scales; the gaps and the bar don't.
  final lineHeight = MediaQuery.textScalerOf(context).scale(11) * 1.25;
  final textAllowance = 6 + (lineHeight * 2) + 4 + 3;

  final cellHeight = (cellWidth * 3 / 2) + textAllowance;
  return cellWidth / cellHeight;
}

/// What a member looks at while a book is being fetched and parsed.
///
/// The cover carries the whole thing. It is already cached — it was on the
/// shelf a moment ago — so it paints on the first frame, and the wait reads
/// as *this book, opening* instead of an anonymous spinner over a dimmed
/// list. The only motion is a slow, shallow breath on the cover: enough to
/// say the app is alive, not enough to become a thing being watched.
class _OpeningBook extends StatefulWidget {
  const _OpeningBook({required this.item});

  final LibraryItem item;

  @override
  State<_OpeningBook> createState() => _OpeningBookState();
}

class _OpeningBookState extends State<_OpeningBook>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final item = widget.item;

    return Center(
      child: SingleChildScrollView(
        // The type here scales with the system font while the cover does
        // not, so at 2.5x this column is taller than a small phone. It
        // scrolls rather than overflowing.
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeTransition(
                opacity: Tween<double>(begin: 1.0, end: 0.86).animate(_breath),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.darkNavy.withValues(alpha: 0.22),
                        blurRadius: 28,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: _cover(item, width: 132, height: 198, radius: 12),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                item.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.titleMedium.copyWith(
                  color: palette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Opening…',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: 18),
              const BrandSpinner(size: 26),
            ],
          ),
        ),
      ),
    );
  }
}

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

  /// Started, never awaited. Nothing on screen may wait on a disk flush.
  ///
  /// These two keys are deliberately NOT `pref:`-prefixed: a saved shelf and
  /// a reading history are the member's own, so `clearUserData()` clearing
  /// them on sign-out is correct — the next person on a shared phone must
  /// not inherit somebody's shelf. (The 24h janitor does not touch them
  /// either way: it only prunes keys that carry a `__ts`, and `writePref`
  /// stores none.)
  static void _persist(String key, String value) {
    unawaited(
      CacheService.writePref(key, value).catchError(
        (Object e) => debugPrint('EgwPrefs: could not persist $key: $e'),
      ),
    );
  }

  static Set<String> saved() {
    final raw = CacheService.readPref(_kSaved);
    if (raw == null) return <String>{};
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  /// Founder, 18 Aug 2026: *"save to shelf dosent work"*.
  ///
  /// It did work — it just could not be seen working. The write was awaited
  /// before [revision] was bumped, so the bookmark, the Saved count and the
  /// shelf itself all waited on a Hive flush, and the sheet that triggered
  /// it sat open until the same flush returned. The same shape had already
  /// made the reading settings look dead; see [EgwReaderPrefs].
  ///
  /// Notify first, persist after. `writePref` reaches Hive's in-memory
  /// keystore before its first `await`, so [saved] reads the change back
  /// immediately and only the disk flush is outstanding.
  static void toggleSaved(String id) {
    final set = saved();
    set.contains(id) ? set.remove(id) : set.add(id);
    _persist(_kSaved, jsonEncode(set.toList()));
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

  static void noteOpened(String id) {
    final map = _opened()..[id] = DateTime.now().millisecondsSinceEpoch;
    _persist(_kOpened, jsonEncode(map));
    revision.value++;
  }
}
