import 'package:flutter/material.dart';

import '../../models/hymn_model.dart';
import '../../models/library_item_model.dart';
import '../../services/bible_prefs_service.dart';
import '../../services/bible_service.dart';
import '../../services/egw_download_service.dart';
import '../../services/hymn_service.dart';
import '../../services/library_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/screen_shell.dart';
import 'egw_tab.dart' show EgwPrefs;
import 'hymnal_tab.dart' show HymnPrefs;
import 'library_open.dart';

/// One saved Bible verse, from a bookmark, a highlight or a note.
class SavedVerse {
  const SavedVerse({
    required this.book,
    required this.chapter,
    required this.verse,
    required this.text,
    this.bookmarked = false,
    this.highlight,
    this.note,
  });

  final BibleBook book;

  /// 0-based, like the reader and the prefs keys.
  final int chapter;
  final int verse;
  final String text;
  final bool bookmarked;
  final int? highlight;
  final String? note;

  String get reference => '${book.name} ${chapter + 1}:${verse + 1}';
}

/// Everything the member saved across the Library, and what is on the
/// phone for offline reading. Read from the prefs each section already
/// writes — the same data, one place to find it.
class LibrarySavedScreen extends StatefulWidget {
  const LibrarySavedScreen({super.key, this.autoLoad = true});

  /// False in widget tests: no Bible parse, no network.
  final bool autoLoad;

  /// Bookmarks, highlights and notes merged per verse, in Bible order.
  /// Keys that no longer resolve (corrupt or from another translation's
  /// versification) are skipped, never shown as blanks.
  static List<SavedVerse> mergeVerses(
    List<BibleBook> books, {
    required Set<String> bookmarks,
    required Map<String, int> highlights,
    required Map<String, String> notes,
  }) {
    final keys = {...bookmarks, ...highlights.keys, ...notes.keys};
    final out = <SavedVerse>[];
    for (final key in keys) {
      final parts = key.split(':').map(int.tryParse).toList();
      if (parts.length != 3 || parts.contains(null)) continue;
      final (b, c, v) = (parts[0]!, parts[1]!, parts[2]!);
      if (b < 0 || b >= books.length) continue;
      final book = books[b];
      if (c < 0 || c >= book.chapters.length) continue;
      if (v < 0 || v >= book.chapters[c].length) continue;
      out.add(
        SavedVerse(
          book: book,
          chapter: c,
          verse: v,
          text: BibleService.cleanVerse(book.chapters[c][v]),
          bookmarked: bookmarks.contains(key),
          highlight: highlights[key],
          note: notes[key],
        ),
      );
    }
    out.sort((a, b) {
      final byBook = a.book.index.compareTo(b.book.index);
      if (byBook != 0) return byBook;
      final byChapter = a.chapter.compareTo(b.chapter);
      return byChapter != 0 ? byChapter : a.verse.compareTo(b.verse);
    });
    return out;
  }

  @override
  State<LibrarySavedScreen> createState() => _LibrarySavedScreenState();
}

class _LibrarySavedScreenState extends State<LibrarySavedScreen> {
  List<SavedVerse> _verses = const [];
  List<Hymn> _hymns = const [];
  List<LibraryItem> _egwSaved = const [];
  List<LibraryItem> _egwDownloaded = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.autoLoad) {
      _load();
      BiblePrefsService.revision.addListener(_load);
      HymnPrefs.revision.addListener(_load);
      EgwPrefs.revision.addListener(_load);
      EgwDownloadService.revision.addListener(_load);
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    if (widget.autoLoad) {
      BiblePrefsService.revision.removeListener(_load);
      HymnPrefs.revision.removeListener(_load);
      EgwPrefs.revision.removeListener(_load);
      EgwDownloadService.revision.removeListener(_load);
    }
    super.dispose();
  }

  Future<void> _load() async {
    final books = await BibleService.books();
    final verses = LibrarySavedScreen.mergeVerses(
      books,
      bookmarks: BiblePrefsService.bookmarks(),
      highlights: BiblePrefsService.highlights(),
      notes: BiblePrefsService.notes(),
    );
    final favIds = HymnPrefs.favorites();
    final hymns = favIds.isEmpty
        ? const <Hymn>[]
        : (await HymnService.all())
              .where((h) => favIds.contains(h.id))
              .toList();
    final savedIds = EgwPrefs.saved();
    final downloadedIds = EgwDownloadService.downloadedIds();
    var egw = const <LibraryItem>[];
    if (savedIds.isNotEmpty || downloadedIds.isNotEmpty) {
      egw = await LibraryService.fetchItems('egw_book');
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _verses = verses;
      _hymns = hymns;
      _egwSaved = egw.where((i) => savedIds.contains(i.id)).toList();
      _egwDownloaded = egw.where((i) => downloadedIds.contains(i.id)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FlatStatusBar(
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(
              'Saved & downloads',
              style: AppTextStyles.appBarTitleFlat.copyWith(fontSize: 19),
            ),
            bottom: TabBar(
              dividerColor: Colors.transparent,
              indicatorColor: AppColors.primaryBlue,
              indicatorSize: TabBarIndicatorSize.label,
              labelColor: AppColors.primaryBlue,
              unselectedLabelColor: context.palette.textMuted,
              labelStyle: AppTextStyles.labelMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
              tabs: const [
                Tab(text: 'Saved'),
                Tab(text: 'On this phone'),
              ],
            ),
          ),
          body: SafeArea(
            top: false,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(children: [_saved(context), _offline(context)]),
          ),
        ),
      ),
    );
  }

  Widget _saved(BuildContext context) {
    final palette = context.palette;
    if (_verses.isEmpty && _hymns.isEmpty && _egwSaved.isEmpty) {
      return const _Empty(
        text:
            'Nothing saved yet. Bookmark or highlight a verse, add a note, '
            'star a hymn or save an Ellen G. White book — it will be here.',
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpace.xxl),
      children: [
        if (_verses.isNotEmpty) ...[
          _Heading('BIBLE · ${_verses.length}'),
          for (final v in _verses)
            _Row(
              icon: v.note != null
                  ? Icons.sticky_note_2_rounded
                  : v.bookmarked
                  ? Icons.bookmark_rounded
                  : Icons.format_color_fill_rounded,
              iconColor:
                  v.highlight != null &&
                      v.highlight! < BiblePrefsService.highlightColors.length
                  ? Color(BiblePrefsService.highlightColors[v.highlight!])
                  : null,
              title: v.reference,
              subtitle: v.note ?? v.text,
              lines: 2,
              onTap: () =>
                  LibraryOpen.verse(context, v.book, v.chapter, verse: v.verse),
            ),
        ],
        if (_hymns.isNotEmpty) ...[
          _Heading('HYMNS · ${_hymns.length}'),
          for (final h in _hymns)
            _Row(
              icon: Icons.queue_music_rounded,
              title: h.number == null ? h.title : '${h.number}. ${h.title}',
              subtitle: h.category ?? 'Hymnal',
              onTap: () => LibraryOpen.hymn(context, h),
            ),
        ],
        if (_egwSaved.isNotEmpty) ...[
          _Heading('ELLEN G. WHITE · ${_egwSaved.length}'),
          for (final b in _egwSaved)
            _Row(
              icon: Icons.auto_stories_rounded,
              title: b.title,
              subtitle: b.author ?? 'Ellen G. White',
              onTap: () => LibraryOpen.egwBook(context, b.id),
            ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.lg,
            AppSpace.lg,
            0,
          ),
          child: Text(
            'Saved on this phone. Signing out clears it.',
            style: AppTextStyles.caption.copyWith(color: palette.textMuted),
          ),
        ),
      ],
    );
  }

  Widget _offline(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpace.xxl),
      children: [
        const _Heading('ALWAYS AVAILABLE OFFLINE'),
        const _Row(
          icon: Icons.menu_book_rounded,
          title: 'Bible — King James Version',
          subtitle: 'Built into the app. Other translations need internet.',
        ),
        const _Row(
          icon: Icons.queue_music_rounded,
          title: 'Hymnal',
          subtitle: 'Built into the app.',
        ),
        const _Row(
          icon: Icons.history_edu_rounded,
          title: '28 Fundamental Beliefs',
          subtitle: 'Built into the app.',
        ),
        _Heading('DOWNLOADED BOOKS · ${_egwDownloaded.length}'),
        if (_egwDownloaded.isEmpty)
          const _Row(
            icon: Icons.download_rounded,
            title: 'No books downloaded',
            subtitle:
                'Download an Ellen G. White book from its page in the '
                'EGW shelf to read it without internet.',
          )
        else
          for (final b in _egwDownloaded)
            _Row(
              icon: Icons.download_done_rounded,
              title: b.title,
              subtitle: b.author ?? 'Ellen G. White',
              onTap: () => LibraryOpen.egwBook(context, b.id),
            ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.lg,
        AppSpace.lg,
        AppSpace.xs,
      ),
      child: Text(
        text,
        style: AppTextStyles.overline.copyWith(
          color: context.palette.textMuted,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.iconColor,
    this.lines = 1,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  /// The highlight's own colour, as a swatch behind the icon.
  final Color? iconColor;
  final int lines;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor ?? AppColors.primaryBlue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(
          icon,
          size: 20,
          color: iconColor != null ? AppColors.darkNavy : palette.brandBlue,
        ),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.labelLarge.copyWith(
          color: palette.text,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: lines,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.caption.copyWith(color: palette.textMuted),
      ),
      trailing: onTap == null
          ? null
          : Icon(Icons.chevron_right_rounded, color: palette.textMuted),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium.copyWith(
            color: context.palette.textMuted,
          ),
        ),
      ),
    );
  }
}
