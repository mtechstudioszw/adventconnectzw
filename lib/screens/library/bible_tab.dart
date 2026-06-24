import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/bible_prefs_service.dart';
import '../../services/bible_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// Library → Bible tab. Bundled offline KJV with modern-reader features:
/// full-text search, bookmarks, highlights, per-verse notes, adjustable
/// font size, share/copy verse, and resume-where-you-left-off.
class BibleTab extends StatefulWidget {
  const BibleTab({super.key});

  @override
  State<BibleTab> createState() => _BibleTabState();
}

class _BibleTabState extends State<BibleTab>
    with AutomaticKeepAliveClientMixin {
  late final Future<List<BibleBook>> _future = BibleService.books();

  @override
  bool get wantKeepAlive => true;

  void _openReader(BibleBook book, int chapter, {int? scrollToVerse}) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BibleReaderScreen(
        book: book,
        chapter: chapter,
        scrollToVerse: scrollToVerse,
      ),
    ));
  }

  Future<void> _continueReading(List<BibleBook> books) async {
    final pos = BiblePrefsService.lastPosition();
    if (pos == null) return;
    final (b, c) = pos;
    if (b < books.length && c < books[b].chapterCount) {
      _openReader(books[b], c);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final palette = context.palette;
    return FutureBuilder<List<BibleBook>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryBlue));
        }
        final books = snap.data ?? const [];
        if (books.isEmpty) {
          return Center(
            child: Text('Bible unavailable.',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: palette.textMuted)),
          );
        }
        final ot = books.where((b) => b.isOldTestament).toList();
        final nt = books.where((b) => !b.isOldTestament).toList();
        final hasResume = BiblePrefsService.lastPosition() != null;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            // Toolbar: Search · Bookmarks · Notes.
            Row(
              children: [
                Expanded(
                  child: _ToolButton(
                    icon: Icons.search,
                    label: 'Search',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => BibleSearchScreen(onOpen: _openReader),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ToolButton(
                    icon: Icons.bookmark_outline,
                    label: 'Saved',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            BibleSavedScreen(books: books, onOpen: _openReader),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (hasResume) ...[
              const SizedBox(height: 10),
              _ContinueCard(
                books: books,
                onTap: () => _continueReading(books),
              ),
            ],
            const SizedBox(height: 18),
            _sectionHeader(context, 'OLD TESTAMENT'),
            ..._bookTiles(context, ot),
            const SizedBox(height: 20),
            _sectionHeader(context, 'NEW TESTAMENT'),
            ..._bookTiles(context, nt),
          ],
        );
      },
    );
  }

  Widget _sectionHeader(BuildContext context, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 4),
        child: Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.primaryBlue,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.6,
          ),
        ),
      );

  List<Widget> _bookTiles(BuildContext context, List<BibleBook> books) {
    final palette = context.palette;
    return [
      for (final book in books)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: palette.card,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      _BibleChaptersScreen(book: book, onOpen: _openReader),
                ),
              ),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: palette.divider),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        book.name,
                        style: AppTextStyles.titleSmall
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text('${book.chapterCount} ch',
                        style: AppTextStyles.labelSmall
                            .copyWith(color: palette.textMuted)),
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right, color: palette.textMuted),
                  ],
                ),
              ),
            ),
          ),
        ),
    ];
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.divider),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.primaryBlue, size: 18),
              const SizedBox(width: 8),
              Text(label,
                  style: AppTextStyles.labelMedium
                      .copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.books, required this.onTap});
  final List<BibleBook> books;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pos = BiblePrefsService.lastPosition();
    if (pos == null) return const SizedBox.shrink();
    final (b, c) = pos;
    if (b >= books.length) return const SizedBox.shrink();
    final label = '${books[b].name} ${c + 1}';
    return Material(
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.history_rounded, color: AppColors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Continue reading',
                        style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.white.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1)),
                    const SizedBox(height: 2),
                    Text(label,
                        style: AppTextStyles.titleSmall.copyWith(
                            color: AppColors.white,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios,
                  color: AppColors.white, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Chapter picker
// ---------------------------------------------------------------------------

class _BibleChaptersScreen extends StatelessWidget {
  const _BibleChaptersScreen({required this.book, required this.onOpen});
  final BibleBook book;
  final void Function(BibleBook, int, {int? scrollToVerse}) onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      appBar: AppBar(
        title: Text(book.name,
            style: AppTextStyles.appBarTitle.copyWith(fontSize: 18)),
        foregroundColor: AppColors.white,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.appBarGradient),
        ),
      ),
      body: SafeArea(
        top: false,
        child: GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1,
          ),
          itemCount: book.chapterCount,
          itemBuilder: (context, i) => Material(
            color: palette.card,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.of(context).pop();
                onOpen(book, i);
              },
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: palette.divider),
                ),
                child: Text('${i + 1}',
                    style: AppTextStyles.titleMedium
                        .copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Verse reader (highlights, bookmarks, notes, font size, share)
// ---------------------------------------------------------------------------

class BibleReaderScreen extends StatefulWidget {
  const BibleReaderScreen({
    super.key,
    required this.book,
    required this.chapter,
    this.scrollToVerse,
  });
  final BibleBook book;
  final int chapter;
  final int? scrollToVerse;

  @override
  State<BibleReaderScreen> createState() => _BibleReaderScreenState();
}

class _BibleReaderScreenState extends State<BibleReaderScreen> {
  late int _chapter = widget.chapter;
  final _scrollCtrl = ScrollController();
  final _verseKeys = <int, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    BiblePrefsService.setLastPosition(widget.book.index, _chapter);
    BiblePrefsService.revision.addListener(_onPrefs);
    if (widget.scrollToVerse != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTarget());
    }
  }

  @override
  void dispose() {
    BiblePrefsService.revision.removeListener(_onPrefs);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onPrefs() {
    if (mounted) setState(() {});
  }

  void _scrollToTarget() {
    final key = _verseKeys[widget.scrollToVerse];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 350), alignment: 0.1);
    }
  }

  void _goChapter(int c) {
    setState(() {
      _chapter = c;
      _verseKeys.clear();
    });
    BiblePrefsService.setLastPosition(widget.book.index, c);
    _scrollCtrl.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final verses = widget.book.chapters[_chapter];
    final scale = BiblePrefsService.fontScale();
    final last = widget.book.chapterCount - 1;
    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      appBar: AppBar(
        title: Text('${widget.book.name} ${_chapter + 1}',
            style: AppTextStyles.appBarTitle.copyWith(fontSize: 18)),
        foregroundColor: AppColors.white,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.appBarGradient),
        ),
        actions: [
          IconButton(
            tooltip: 'Text size',
            icon: const Icon(Icons.format_size),
            onPressed: _openFontSheet,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < verses.length; i++)
                _verseTile(context, i, verses[i], scale),
              const SizedBox(height: 16),
              _chapterNav(context, last),
            ],
          ),
        ),
      ),
    );
  }

  Widget _verseTile(BuildContext context, int i, String raw, double scale) {
    final palette = context.palette;
    final key = BiblePrefsService.verseKey(widget.book.index, _chapter, i);
    final hlIndex = BiblePrefsService.highlightColor(key);
    final bookmarked = BiblePrefsService.isBookmarked(key);
    final hasNote = BiblePrefsService.note(key) != null;
    _verseKeys[i] = GlobalKey();

    return Container(
      key: _verseKeys[i],
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: hlIndex != null
            ? Color(BiblePrefsService.highlightColors[hlIndex])
                .withValues(alpha: 0.55)
            : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openVerseActions(i, BibleService.cleanVerse(raw), key),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: RichText(
            text: TextSpan(
              style: AppTextStyles.bodyLarge.copyWith(
                color: palette.text,
                height: 1.7,
                fontSize: 16.5 * scale,
              ),
              children: [
                TextSpan(
                  text: '${i + 1}  ',
                  style: TextStyle(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5 * scale,
                  ),
                ),
                TextSpan(text: BibleService.cleanVerse(raw)),
                if (bookmarked)
                  const WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(Icons.bookmark,
                          size: 14, color: AppColors.goldAccent),
                    ),
                  ),
                if (hasNote)
                  const WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.sticky_note_2_outlined,
                          size: 14, color: AppColors.primaryBlue),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- Verse action sheet -------------------------------------------------
  Future<void> _openVerseActions(int verse, String text, String key) async {
    final palette = context.palette;
    final ref = '${widget.book.name} ${_chapter + 1}:${verse + 1}';
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Text(ref,
                  style: AppTextStyles.titleSmall.copyWith(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: palette.textMuted)),
            ),
            // Highlight color row.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (var ci = 0;
                      ci < BiblePrefsService.highlightColors.length;
                      ci++)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: GestureDetector(
                        onTap: () {
                          BiblePrefsService.setHighlight(key, ci);
                          Navigator.pop(ctx);
                        },
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: Color(
                              BiblePrefsService.highlightColors[ci]),
                        ),
                      ),
                    ),
                  GestureDetector(
                    onTap: () {
                      BiblePrefsService.setHighlight(key, null);
                      Navigator.pop(ctx);
                    },
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: palette.cardMuted,
                      child: Icon(Icons.format_color_reset,
                          size: 16, color: palette.textMuted),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            _action(ctx, Icons.bookmark_outline,
                BiblePrefsService.isBookmarked(key)
                    ? 'Remove bookmark'
                    : 'Bookmark', () {
              BiblePrefsService.toggleBookmark(key);
              Navigator.pop(ctx);
            }),
            _action(ctx, Icons.sticky_note_2_outlined,
                BiblePrefsService.note(key) == null ? 'Add note' : 'Edit note',
                () {
              Navigator.pop(ctx);
              _openNoteEditor(key, ref);
            }),
            _action(ctx, Icons.copy, 'Copy', () {
              Clipboard.setData(ClipboardData(text: '$text\n— $ref (KJV)'));
              Navigator.pop(ctx);
            }),
            _action(ctx, Icons.share_outlined, 'Share', () {
              Navigator.pop(ctx);
              Share.share('$text\n\n— $ref (KJV)\nShared from Advent Connect ZW');
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _action(
      BuildContext ctx, IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primaryBlue),
      title: Text(label, style: AppTextStyles.bodyLarge),
      onTap: onTap,
    );
  }

  Future<void> _openNoteEditor(String key, String ref) async {
    final controller =
        TextEditingController(text: BiblePrefsService.note(key) ?? '');
    final palette = context.palette;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.card,
        title: Text('Note · $ref',
            style: AppTextStyles.titleMedium
                .copyWith(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          minLines: 3,
          style: AppTextStyles.bodyMedium.copyWith(color: palette.text),
          decoration: InputDecoration(
            hintText: 'Your reflection…',
            filled: true,
            fillColor: palette.inputFill,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: palette.divider)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(color: palette.textMuted)),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.primaryBlue),
            onPressed: () {
              BiblePrefsService.setNote(key, controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _openFontSheet() async {
    final palette = context.palette;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          var scale = BiblePrefsService.fontScale();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Text size',
                      style: AppTextStyles.titleMedium
                          .copyWith(fontWeight: FontWeight.w700)),
                  Row(
                    children: [
                      const Text('A', style: TextStyle(fontSize: 14)),
                      Expanded(
                        child: Slider(
                          value: scale,
                          min: 0.8,
                          max: 1.8,
                          divisions: 10,
                          activeColor: AppColors.primaryBlue,
                          label: '${(scale * 100).round()}%',
                          onChanged: (v) {
                            setSheet(() => scale = v);
                            BiblePrefsService.setFontScale(v);
                          },
                        ),
                      ),
                      const Text('A', style: TextStyle(fontSize: 24)),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _chapterNav(BuildContext context, int last) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        TextButton.icon(
          onPressed: _chapter > 0 ? () => _goChapter(_chapter - 1) : null,
          icon: const Icon(Icons.chevron_left, size: 20),
          label: const Text('Previous'),
        ),
        Text('${_chapter + 1} / ${widget.book.chapterCount}',
            style: AppTextStyles.labelMedium
                .copyWith(color: context.palette.textMuted)),
        TextButton(
          onPressed: _chapter < last ? () => _goChapter(_chapter + 1) : null,
          child: Row(mainAxisSize: MainAxisSize.min, children: const [
            Text('Next'),
            Icon(Icons.chevron_right, size: 20),
          ]),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
//  Search
// ---------------------------------------------------------------------------

class BibleSearchScreen extends StatefulWidget {
  const BibleSearchScreen({super.key, required this.onOpen});
  final void Function(BibleBook, int, {int? scrollToVerse}) onOpen;

  @override
  State<BibleSearchScreen> createState() => _BibleSearchScreenState();
}

class _BibleSearchScreenState extends State<BibleSearchScreen> {
  final _controller = TextEditingController();
  List<BibleSearchHit> _hits = const [];
  bool _searching = false;
  bool _ran = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run(String q) async {
    if (q.trim().length < 2) return;
    setState(() => _searching = true);
    final hits = await BibleService.search(q);
    if (!mounted) return;
    setState(() {
      _hits = hits;
      _searching = false;
      _ran = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      appBar: AppBar(
        foregroundColor: AppColors.white,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.appBarGradient),
        ),
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: _run,
          style: const TextStyle(color: AppColors.white, fontSize: 16),
          cursorColor: AppColors.white,
          decoration: InputDecoration(
            hintText: 'Search the Bible…',
            hintStyle:
                TextStyle(color: AppColors.white.withValues(alpha: 0.6)),
            border: InputBorder.none,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _run(_controller.text),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _searching
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primaryBlue))
            : !_ran
                ? Center(
                    child: Text('Type a word or phrase to search.',
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: palette.textMuted)),
                  )
                : _hits.isEmpty
                    ? Center(
                        child: Text('No matches found.',
                            style: AppTextStyles.bodyMedium
                                .copyWith(color: palette.textMuted)),
                      )
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text('${_hits.length} result(s)',
                                  style: AppTextStyles.labelMedium
                                      .copyWith(color: palette.textMuted)),
                            ),
                          ),
                          Expanded(
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              itemCount: _hits.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                final h = _hits[i];
                                return Material(
                                  color: palette.card,
                                  borderRadius: BorderRadius.circular(12),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () {
                                      Navigator.of(context).pop();
                                      widget.onOpen(h.book, h.chapter,
                                          scrollToVerse: h.verse);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        border:
                                            Border.all(color: palette.divider),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(h.reference,
                                              style: AppTextStyles.labelMedium
                                                  .copyWith(
                                                      color:
                                                          AppColors.primaryBlue,
                                                      fontWeight:
                                                          FontWeight.w700)),
                                          const SizedBox(height: 4),
                                          Text(h.text,
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                              style: AppTextStyles.bodyMedium
                                                  .copyWith(
                                                      color: palette.text,
                                                      height: 1.4)),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Saved (bookmarks + notes)
// ---------------------------------------------------------------------------

class BibleSavedScreen extends StatefulWidget {
  const BibleSavedScreen({super.key, required this.books, required this.onOpen});
  final List<BibleBook> books;
  final void Function(BibleBook, int, {int? scrollToVerse}) onOpen;

  @override
  State<BibleSavedScreen> createState() => _BibleSavedScreenState();
}

class _BibleSavedScreenState extends State<BibleSavedScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  ({BibleBook book, int chapter, int verse})? _parse(String key) {
    final p = key.split(':');
    if (p.length != 3) return null;
    final b = int.tryParse(p[0]);
    final c = int.tryParse(p[1]);
    final v = int.tryParse(p[2]);
    if (b == null || c == null || v == null || b >= widget.books.length) {
      return null;
    }
    return (book: widget.books[b], chapter: c, verse: v);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      appBar: AppBar(
        title: Text('Saved',
            style: AppTextStyles.appBarTitle.copyWith(fontSize: 18)),
        foregroundColor: AppColors.white,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.appBarGradient),
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.goldAccent,
          labelColor: AppColors.white,
          unselectedLabelColor: AppColors.white.withValues(alpha: 0.6),
          tabs: const [Tab(text: 'Bookmarks'), Tab(text: 'Notes')],
        ),
      ),
      body: SafeArea(
        top: false,
        child: TabBarView(
          controller: _tabs,
          children: [
            _bookmarksList(context),
            _notesList(context),
          ],
        ),
      ),
    );
  }

  Widget _bookmarksList(BuildContext context) {
    final palette = context.palette;
    final keys = BiblePrefsService.bookmarks().toList()..sort();
    if (keys.isEmpty) {
      return _empty(context, Icons.bookmark_outline,
          'Bookmarked verses appear here.');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: keys.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final parsed = _parse(keys[i]);
        if (parsed == null) return const SizedBox.shrink();
        final raw =
            parsed.book.chapters[parsed.chapter][parsed.verse];
        final ref =
            '${parsed.book.name} ${parsed.chapter + 1}:${parsed.verse + 1}';
        return Material(
          color: palette.card,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.of(context).pop();
              widget.onOpen(parsed.book, parsed.chapter,
                  scrollToVerse: parsed.verse);
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: palette.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.bookmark,
                          color: AppColors.goldAccent, size: 16),
                      const SizedBox(width: 6),
                      Text(ref,
                          style: AppTextStyles.labelMedium.copyWith(
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(BibleService.cleanVerse(raw),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: palette.text, height: 1.4)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _notesList(BuildContext context) {
    final palette = context.palette;
    final entries = BiblePrefsService.notes().entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (entries.isEmpty) {
      return _empty(context, Icons.sticky_note_2_outlined,
          'Your verse notes appear here.');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final parsed = _parse(entries[i].key);
        if (parsed == null) return const SizedBox.shrink();
        final ref =
            '${parsed.book.name} ${parsed.chapter + 1}:${parsed.verse + 1}';
        return Material(
          color: palette.card,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.of(context).pop();
              widget.onOpen(parsed.book, parsed.chapter,
                  scrollToVerse: parsed.verse);
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: palette.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ref,
                      style: AppTextStyles.labelMedium.copyWith(
                          color: AppColors.primaryBlue,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(entries[i].value,
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: palette.text, height: 1.4)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _empty(BuildContext context, IconData icon, String text) {
    final palette = context.palette;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: palette.textMuted),
          const SizedBox(height: 14),
          Text(text,
              style:
                  AppTextStyles.bodyMedium.copyWith(color: palette.textMuted)),
        ],
      ),
    );
  }
}
