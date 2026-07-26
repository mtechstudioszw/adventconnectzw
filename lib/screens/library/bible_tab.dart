import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'music_tab.dart';
import '../../models/bible_translation.dart';
import '../../models/library_item_model.dart';
import '../../services/bible_prefs_service.dart';
import '../../services/bible_service.dart';
import '../../services/bible_translation_service.dart';
import '../../services/music_player_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/motion/pressable.dart';
import 'widgets/translation_picker.dart';
import 'widgets/verse_share_card.dart';

/// Library → Bible tab. Bundled offline KJV with a full modern reader:
/// verse-of-the-day, reading streak, fast book/chapter picking, swipe between
/// chapters across the whole Bible, multi-verse selection, highlights,
/// bookmarks, notes, reading themes, and share-as-image.
class BibleTab extends StatefulWidget {
  const BibleTab({super.key});

  @override
  State<BibleTab> createState() => _BibleTabState();
}

class _BibleTabState extends State<BibleTab>
    with AutomaticKeepAliveClientMixin {
  late final Future<List<BibleBook>> _future = BibleService.books();
  final _bookSearchCtrl = TextEditingController();

  /// false = Old Testament, true = New Testament.
  bool _showNt = false;
  String _bookQuery = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    BiblePrefsService.revision.addListener(_onPrefs);
    // Bring back the translation the user last read in.
    BibleTranslationService.restore();
    BibleTranslationService.active.addListener(_onPrefs);
  }

  @override
  void dispose() {
    BiblePrefsService.revision.removeListener(_onPrefs);
    BibleTranslationService.active.removeListener(_onPrefs);
    _bookSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _switchTranslation() async {
    final chosen = await TranslationPicker.show(
      context,
      current: BibleTranslationService.current,
    );
    if (chosen != null) await BibleTranslationService.setActive(chosen);
  }

  void _onPrefs() {
    if (mounted) setState(() {});
  }

  void _openReader(BibleBook book, int chapter, {int? scrollToVerse}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BibleReaderScreen(
          book: book,
          chapter: chapter,
          scrollToVerse: scrollToVerse,
        ),
      ),
    );
  }

  Future<void> _continueReading(List<BibleBook> books) async {
    final pos = BiblePrefsService.lastPosition();
    if (pos == null) return;
    final (b, c) = pos;
    if (b < books.length && c < books[b].chapterCount) {
      _openReader(books[b], c);
    }
  }

  /// Opens the chapter grid for [book] as a sheet — one tap fewer than
  /// pushing a whole screen, and it keeps the book list underneath.
  Future<void> _pickChapter(BibleBook book) async {
    HapticFeedback.selectionClick();
    final palette = context.palette;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.sheet,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => _ChapterGridSheet(
        book: book,
        onPick: (chapter) {
          Navigator.of(ctx).pop();
          _openReader(book, chapter);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final palette = context.palette;
    return FutureBuilder<List<BibleBook>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: BrandSpinner(size: 30));
        }
        final books = snap.data ?? const <BibleBook>[];
        if (books.isEmpty) {
          return Center(
            child: Text(
              'Bible unavailable.',
              style:
                  AppTextStyles.bodyMedium.copyWith(color: palette.textMuted),
            ),
          );
        }

        final query = _bookQuery.trim().toLowerCase();
        final searching = query.isNotEmpty;
        final shown = searching
            ? books
                .where((b) =>
                    b.name.toLowerCase().contains(query) ||
                    b.abbrev.toLowerCase().contains(query))
                .toList()
            : books.where((b) => b.isOldTestament != _showNt).toList();

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _VerseOfDayCard(books: books)),
            SliverToBoxAdapter(child: _translationRow(context)),
            SliverToBoxAdapter(child: _toolRow(context, books)),
            if (BiblePrefsService.lastPosition() != null)
              SliverToBoxAdapter(
                child: _ContinueCard(
                  books: books,
                  onTap: () => _continueReading(books),
                ),
              ),
            SliverToBoxAdapter(child: _bookSearch(context)),
            if (!searching)
              SliverToBoxAdapter(child: _testamentToggle(context)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              sliver: SliverGrid.builder(
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.85,
                ),
                itemCount: shown.length,
                itemBuilder: (context, i) => _BookChip(
                  book: shown[i],
                  onTap: () => _pickChapter(shown[i]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Current-translation banner. Doubles as the entry point to the picker so
  /// a reader can change Bible before choosing a book, not only inside the
  /// reader.
  Widget _translationRow(BuildContext context) {
    final palette = context.palette;
    final t = BibleTranslationService.current;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Pressable(
        onTap: _switchTranslation,
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      t.accent,
                      Color.lerp(t.accent, Colors.black, 0.35)!,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  t.glyph,
                  style: AppTextStyles.titleSmall.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelMedium.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      t.languageLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'Change',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Tools --------------------------------------------------------------

  Widget _toolRow(BuildContext context, List<BibleBook> books) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _ToolButton(
              icon: Icons.search_rounded,
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
              icon: Icons.bookmark_outline_rounded,
              label: 'Saved',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      BibleSavedScreen(books: books, onOpen: _openReader),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ToolButton(
              icon: Icons.headset_rounded,
              label: 'Audio',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AudioBibleScreen(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bookSearch(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: TextField(
        controller: _bookSearchCtrl,
        onChanged: (v) => setState(() => _bookQuery = v),
        textInputAction: TextInputAction.search,
        style: AppTextStyles.bodyMedium.copyWith(color: palette.text),
        decoration: InputDecoration(
          hintText: 'Jump to a book…',
          hintStyle: TextStyle(color: palette.textMuted),
          prefixIcon:
              Icon(Icons.menu_book_rounded, color: palette.textMuted, size: 20),
          suffixIcon: _bookQuery.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close_rounded, color: palette.textMuted),
                  onPressed: () {
                    _bookSearchCtrl.clear();
                    setState(() => _bookQuery = '');
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

  /// Old/New Testament segmented control. Two taps to any book beats scrolling
  /// a 66-row list, which is what the old layout forced.
  Widget _testamentToggle(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: palette.inputFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.divider),
        ),
        child: Row(
          children: [
            for (final (isNt, label) in const [
              (false, 'Old Testament'),
              (true, 'New Testament'),
            ])
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (_showNt == isNt) return;
                    HapticFeedback.selectionClick();
                    setState(() => _showNt = isNt);
                  },
                  child: AnimatedContainer(
                    duration: AppMotion.quick,
                    curve: AppMotion.ease,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient:
                          _showNt == isNt ? AppColors.primaryGradient : null,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      label,
                      style: AppTextStyles.labelMedium.copyWith(
                        color: _showNt == isNt
                            ? AppColors.white
                            : palette.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Verse of the day
// ---------------------------------------------------------------------------

/// A curated verse, chosen deterministically from the day's date so every
/// user sees the same one and it changes at midnight without any server.
class _VerseOfDayCard extends StatelessWidget {
  const _VerseOfDayCard({required this.books});

  final List<BibleBook> books;

  /// (bookIndex, chapter, verse) — all 0-based. Hand-picked well-known
  /// passages; a random verse would surface genealogies.
  static const _picks = <(int, int, int)>[
    (42, 2, 15), // John 3:16
    (18, 22, 0), // Psalm 23:1
    (19, 2, 4), // Proverbs 3:5
    (44, 7, 27), // Romans 8:28
    (49, 3, 12), // Philippians 4:13
    (22, 40, 30), // Isaiah 40:31
    (23, 28, 10), // Jeremiah 29:11
    (5, 0, 8), // Joshua 1:9
    (18, 45, 9), // Psalm 46:10
    (39, 5, 32), // Matthew 6:33
    (58, 10, 0), // Hebrews 11:1
    (19, 15, 3), // Proverbs 16:3
    (18, 118, 104), // Psalm 119:105
    (46, 4, 16), // 2 Corinthians 5:17
    (48, 2, 19), // Galatians 2:20
    (61, 0, 8), // 1 John 1:9
    (40, 10, 27), // Matthew 11:28
    (24, 2, 22), // Lamentations 3:22
    (36, 3, 5), // Zephaniah 3:17
    (44, 11, 1), // Romans 12:2
    (50, 3, 5), // Philippians 4:6
    (18, 26, 0), // Psalm 27:1
    (43, 13, 26), // John 14:27
    (59, 0, 4), // James 1:5
    (60, 4, 6), // 1 Peter 5:7
  ];

  (BibleBook, int, int)? _resolve() {
    final now = DateTime.now();
    // Day-of-year keeps it stable for the whole day and cycles the list.
    final dayOfYear = now.difference(DateTime(now.year)).inDays;
    for (var attempt = 0; attempt < _picks.length; attempt++) {
      final (b, c, v) = _picks[(dayOfYear + attempt) % _picks.length];
      if (b < books.length &&
          c < books[b].chapters.length &&
          v < books[b].chapters[c].length) {
        return (books[b], c, v);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _resolve();
    if (resolved == null) return const SizedBox.shrink();
    final (book, chapter, verse) = resolved;
    final text = BibleService.cleanVerse(book.chapters[chapter][verse]);
    final reference = '${book.name} ${chapter + 1}:${verse + 1}';
    final streak = BiblePrefsService.streak();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        decoration: BoxDecoration(
          gradient: AppColors.appBarGradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.darkNavy.withValues(alpha: 0.32),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.wb_sunny_rounded,
                    color: AppColors.goldAccent, size: 16),
                const SizedBox(width: 7),
                Text(
                  'VERSE OF THE DAY',
                  style: AppTextStyles.overline.copyWith(
                    color: AppColors.goldAccent,
                    fontSize: 9.5,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                if (streak > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.goldAccent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.local_fire_department_rounded,
                            color: AppColors.goldAccent, size: 13),
                        const SizedBox(width: 3),
                        Text(
                          '$streak day${streak == 1 ? '' : 's'}',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.goldAccent,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              text,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyLarge.copyWith(
                color: AppColors.white,
                height: 1.6,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  reference,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: AppColors.white.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                _iconAction(
                  context,
                  Icons.ios_share_rounded,
                  'Share',
                  () => VerseShareSheet.open(
                    context,
                    reference: reference,
                    text: text,
                  ),
                ),
                const SizedBox(width: 4),
                _iconAction(
                  context,
                  Icons.arrow_forward_rounded,
                  'Read',
                  () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BibleReaderScreen(
                        book: book,
                        chapter: chapter,
                        scrollToVerse: verse,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconAction(
    BuildContext context,
    IconData icon,
    String tooltip,
    VoidCallback onTap,
  ) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(icon, color: AppColors.white, size: 19),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Book chip + tool button + continue card
// ---------------------------------------------------------------------------

class _BookChip extends StatelessWidget {
  const _BookChip({required this.book, required this.onTap});

  final BibleBook book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return PressEffect(
      child: Material(
        color: palette.card,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: palette.divider),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${book.chapterCount} ch',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: palette.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return PressEffect(
      child: Material(
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
                Text(
                  label,
                  style: AppTextStyles.labelMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: PressEffect(
        child: Material(
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
                        Text(
                          'Continue reading',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.white.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          label,
                          style: AppTextStyles.titleSmall.copyWith(
                            color: AppColors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios,
                      color: AppColors.white, size: 14),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Chapter grid sheet
// ---------------------------------------------------------------------------

class _ChapterGridSheet extends StatelessWidget {
  const _ChapterGridSheet({required this.book, required this.onPick});

  final BibleBook book;
  final void Function(int chapter) onPick;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final last = BiblePrefsService.lastPosition();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (context, scrollCtrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: Row(
              children: [
                Text(
                  book.name,
                  style: AppTextStyles.titleMedium
                      .copyWith(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Text(
                  '${book.chapterCount} chapters',
                  style: AppTextStyles.labelSmall
                      .copyWith(color: palette.textMuted),
                ),
              ],
            ),
          ),
          Divider(color: palette.divider, height: 1),
          Expanded(
            child: GridView.builder(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1,
              ),
              itemCount: book.chapterCount,
              itemBuilder: (context, i) {
                // Mark where the reader last stopped inside this book.
                final isLast =
                    last != null && last.$1 == book.index && last.$2 == i;
                return Material(
                  color: isLast
                      ? AppColors.primaryBlue.withValues(alpha: 0.12)
                      : palette.card,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onPick(i),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isLast
                              ? AppColors.primaryBlue
                              : palette.divider,
                          width: isLast ? 1.5 : 1,
                        ),
                      ),
                      child: Text(
                        '${i + 1}',
                        style: AppTextStyles.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          color:
                              isLast ? AppColors.primaryBlue : palette.text,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Reader
// ---------------------------------------------------------------------------

/// Flat address of a chapter across the whole Bible, so the reader can page
/// continuously from Genesis 1 to Revelation 22 — swiping past the last
/// chapter of a book rolls into the next book instead of dead-ending.
class _ChapterRef {
  const _ChapterRef(this.bookIndex, this.chapter);
  final int bookIndex;
  final int chapter;
}

List<_ChapterRef> _buildChapterIndex(List<BibleBook> books) => [
      for (var b = 0; b < books.length; b++)
        for (var c = 0; c < books[b].chapterCount; c++) _ChapterRef(b, c),
    ];

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
  List<BibleBook> _books = const [];
  List<_ChapterRef> _index = const [];
  PageController? _pageCtrl;
  int _page = 0;

  /// Verses selected in the CURRENT chapter, as verse indexes. Multi-select is
  /// what lets a user highlight or share a whole passage in one gesture —
  /// the single-verse-only sheet was the biggest gap vs other Bible apps.
  final Set<int> _selected = {};

  /// Immersive reading: hides the app bar so only scripture is on screen.
  bool _immersive = false;

  @override
  void initState() {
    super.initState();
    BiblePrefsService.revision.addListener(_onPrefs);
    BibleTranslationService.active.addListener(_onPrefs);
    BiblePrefsService.noteReadToday();
    _load();
  }

  @override
  void dispose() {
    BiblePrefsService.revision.removeListener(_onPrefs);
    BibleTranslationService.active.removeListener(_onPrefs);
    _pageCtrl?.dispose();
    super.dispose();
  }

  /// Opens the cinematic picker and switches translation in place — the
  /// reader stays on the same chapter, the text dissolves into the new
  /// language.
  Future<void> _switchTranslation() async {
    final chosen = await TranslationPicker.show(
      context,
      current: BibleTranslationService.current,
    );
    if (chosen == null) return;
    await BibleTranslationService.setActive(chosen);
    if (!mounted) return;
    // Selection indexes are translation-specific (verse counts can differ).
    setState(_selected.clear);
  }

  void _onPrefs() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final books = await BibleService.books();
    if (!mounted) return;
    final index = _buildChapterIndex(books);
    final start = index.indexWhere(
      (r) => r.bookIndex == widget.book.index && r.chapter == widget.chapter,
    );
    setState(() {
      _books = books;
      _index = index;
      _page = start < 0 ? 0 : start;
      _pageCtrl = PageController(initialPage: _page);
    });
    _persistPosition();
  }

  _ChapterRef? get _ref =>
      (_page >= 0 && _page < _index.length) ? _index[_page] : null;

  BibleBook? get _currentBook {
    final ref = _ref;
    if (ref == null || ref.bookIndex >= _books.length) return null;
    return _books[ref.bookIndex];
  }

  void _persistPosition() {
    final ref = _ref;
    if (ref == null) return;
    BiblePrefsService.setLastPosition(ref.bookIndex, ref.chapter);
  }

  void _onPageChanged(int page) {
    setState(() {
      _page = page;
      _selected.clear();
    });
    _persistPosition();
  }

  double get _scale => BiblePrefsService.fontScale();

  // ---- Theme --------------------------------------------------------------

  /// Resolves the reader's paper. `system` follows the app palette; the other
  /// three are explicit so a user can read sepia at night in a light app.
  ({Color bg, Color fg, Color muted}) get _paper {
    final theme = BiblePrefsService.readingTheme();
    return switch (theme) {
      BibleReadingTheme.light => (
          bg: const Color(0xFFFFFFFF),
          fg: const Color(0xFF1A1A2E),
          muted: const Color(0x991A1A2E),
        ),
      BibleReadingTheme.sepia => (
          bg: const Color(0xFFF7F1E3),
          fg: const Color(0xFF3A3222),
          muted: const Color(0x993A3222),
        ),
      BibleReadingTheme.dark => (
          bg: const Color(0xFF12100E),
          fg: const Color(0xFFF2E7D0),
          muted: const Color(0x99F2E7D0),
        ),
      BibleReadingTheme.system => (
          bg: context.palette.scaffoldBg,
          fg: context.palette.text,
          muted: context.palette.textMuted,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final paper = _paper;
    final book = _currentBook;
    final ref = _ref;

    if (_pageCtrl == null || book == null || ref == null) {
      return Scaffold(
        backgroundColor: paper.bg,
        body: const Center(child: BrandSpinner(size: 30)),
      );
    }

    return Scaffold(
      backgroundColor: paper.bg,
      appBar: _immersive
          ? null
          : AppBar(
              backgroundColor: paper.bg,
              foregroundColor: paper.fg,
              elevation: 0,
              scrolledUnderElevation: 0,
              title: GestureDetector(
                onTap: () => _openChapterPicker(book),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${book.name} ${ref.chapter + 1}',
                      style: AppTextStyles.appBarTitleFlat
                          .copyWith(fontSize: 18, color: paper.fg),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.expand_more_rounded, color: paper.fg, size: 20),
                  ],
                ),
              ),
              actions: [
                _translationButton(),
                IconButton(
                  tooltip: 'Reading settings',
                  icon: const Icon(Icons.text_fields_rounded),
                  onPressed: _openReadingSheet,
                ),
                IconButton(
                  tooltip: 'Focus mode',
                  icon: const Icon(Icons.fullscreen_rounded),
                  onPressed: () => setState(() => _immersive = true),
                ),
              ],
            ),
      body: SafeArea(
        top: _immersive,
        child: PageView.builder(
          controller: _pageCtrl,
          itemCount: _index.length,
          onPageChanged: _onPageChanged,
          itemBuilder: (context, page) {
            final r = _index[page];
            return _ChapterPage(
              // Rebuild the page when the translation changes so the new
              // language loads for the chapter already on screen.
              key: ValueKey(
                '${BibleTranslationService.active.value}:'
                '${r.bookIndex}:${r.chapter}',
              ),
              book: _books[r.bookIndex],
              chapter: r.chapter,
              scale: _scale,
              paper: paper,
              translation: BibleTranslationService.current,
              // Selection only applies to the visible chapter.
              selected: page == _page ? _selected : const {},
              scrollToVerse:
                  page == _page ? widget.scrollToVerse : null,
              onToggleVerse: (v) => setState(() {
                _selected.contains(v)
                    ? _selected.remove(v)
                    : _selected.add(v);
              }),
              onTapEmptySpace: () =>
                  setState(() => _immersive = !_immersive),
            );
          },
        ),
      ),
      bottomNavigationBar:
          _selected.isEmpty ? null : _selectionBar(context, book, ref),
    );
  }

  /// Translation switcher in the app bar. Shows the ACTIVE translation's own
  /// script glyph in its accent colour, so the reader always knows which Bible
  /// they're in without reading a label.
  Widget _translationButton() {
    final t = BibleTranslationService.current;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      child: Tooltip(
        message: 'Translation — ${t.name}',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: _switchTranslation,
            child: AnimatedContainer(
              duration: AppMotion.standard,
              curve: AppMotion.ease,
              width: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    t.accent,
                    Color.lerp(t.accent, Colors.black, 0.35)!,
                  ],
                ),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                t.glyph,
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---- Selection action bar ----------------------------------------------

  Widget _selectionBar(BuildContext context, BibleBook book, _ChapterRef ref) {
    final verses = book.chapters[ref.chapter];
    final sorted = _selected.toList()..sort();
    final reference = _referenceFor(book, ref.chapter, sorted);
    final text = sorted
        .map((v) => BibleService.cleanVerse(verses[v]))
        .join(' ');

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: context.palette.card,
          border: Border(top: BorderSide(color: context.palette.divider)),
        ),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Highlight swatches — one tap applies to every selected verse.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var ci = 0;
                    ci < BiblePrefsService.highlightColors.length;
                    ci++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: GestureDetector(
                      onTap: () => _applyHighlight(book, ref, ci),
                      child: CircleAvatar(
                        radius: 15,
                        backgroundColor:
                            Color(BiblePrefsService.highlightColors[ci]),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: GestureDetector(
                    onTap: () => _applyHighlight(book, ref, null),
                    child: CircleAvatar(
                      radius: 15,
                      backgroundColor: context.palette.cardMuted,
                      child: Icon(Icons.format_color_reset_rounded,
                          size: 16, color: context.palette.textMuted),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _barAction(context, Icons.bookmark_outline_rounded, 'Save',
                    () => _applyBookmark(book, ref)),
                _barAction(context, Icons.copy_rounded, 'Copy', () {
                  Clipboard.setData(
                      ClipboardData(text: '$reference\n$text'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied.')),
                  );
                  setState(_selected.clear);
                }),
                _barAction(context, Icons.edit_note_rounded, 'Note',
                    () => _openNoteEditor(book, ref, sorted, reference)),
                _barAction(context, Icons.ios_share_rounded, 'Share', () {
                  VerseShareSheet.open(context,
                      reference: reference, text: text);
                  setState(_selected.clear);
                }),
                _barAction(context, Icons.close_rounded, 'Clear',
                    () => setState(_selected.clear)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _barAction(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.primaryBlue, size: 21),
              const SizedBox(height: 3),
              Text(
                label,
                style: AppTextStyles.labelSmall.copyWith(
                  color: context.palette.textMuted,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "John 3:16" or "John 3:16-18" / "John 3:16,18" as appropriate.
  String _referenceFor(BibleBook book, int chapter, List<int> verses) {
    if (verses.isEmpty) return '${book.name} ${chapter + 1}';
    if (verses.length == 1) {
      return '${book.name} ${chapter + 1}:${verses.first + 1}';
    }
    final contiguous = verses.last - verses.first == verses.length - 1;
    if (contiguous) {
      return '${book.name} ${chapter + 1}:'
          '${verses.first + 1}-${verses.last + 1}';
    }
    return '${book.name} ${chapter + 1}:'
        '${verses.map((v) => v + 1).join(',')}';
  }

  void _applyHighlight(BibleBook book, _ChapterRef ref, int? colorIndex) {
    for (final v in _selected) {
      BiblePrefsService.setHighlight(
        BiblePrefsService.verseKey(book.index, ref.chapter, v),
        colorIndex,
      );
    }
    HapticFeedback.selectionClick();
    setState(_selected.clear);
  }

  void _applyBookmark(BibleBook book, _ChapterRef ref) {
    for (final v in _selected) {
      final key = BiblePrefsService.verseKey(book.index, ref.chapter, v);
      if (!BiblePrefsService.isBookmarked(key)) {
        BiblePrefsService.toggleBookmark(key);
      }
    }
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved to bookmarks.')),
    );
    setState(_selected.clear);
  }

  Future<void> _openNoteEditor(
    BibleBook book,
    _ChapterRef ref,
    List<int> verses,
    String reference,
  ) async {
    if (verses.isEmpty) return;
    // A note attaches to the FIRST selected verse — that's where it shows.
    final key =
        BiblePrefsService.verseKey(book.index, ref.chapter, verses.first);
    final controller =
        TextEditingController(text: BiblePrefsService.note(key) ?? '');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 18,
          bottom: MediaQuery.viewInsetsOf(ctx).bottom + 18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              reference,
              style: AppTextStyles.titleSmall.copyWith(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 6,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Write your note…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  await BiblePrefsService.setNote(key, controller.text);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
                child: const Text('Save note'),
              ),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (mounted) setState(_selected.clear);
  }

  // ---- Sheets -------------------------------------------------------------

  Future<void> _openChapterPicker(BibleBook book) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.sheet,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => _ChapterGridSheet(
        book: book,
        onPick: (chapter) {
          Navigator.of(ctx).pop();
          final target = _index.indexWhere(
            (r) => r.bookIndex == book.index && r.chapter == chapter,
          );
          if (target >= 0) _pageCtrl?.jumpToPage(target);
        },
      ),
    );
  }

  Future<void> _openReadingSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Text size',
                    style: AppTextStyles.titleSmall
                        .copyWith(fontWeight: FontWeight.w700)),
                Row(
                  children: [
                    const Text('A', style: TextStyle(fontSize: 13)),
                    Expanded(
                      child: Slider(
                        value: BiblePrefsService.fontScale(),
                        min: 0.8,
                        max: 2.0,
                        divisions: 12,
                        activeColor: AppColors.primaryBlue,
                        label:
                            '${(BiblePrefsService.fontScale() * 100).round()}%',
                        onChanged: (v) {
                          BiblePrefsService.setFontScale(v);
                          setSheet(() {});
                        },
                      ),
                    ),
                    const Text('A', style: TextStyle(fontSize: 24)),
                  ],
                ),
                const SizedBox(height: 10),
                Text('Reading theme',
                    style: AppTextStyles.titleSmall
                        .copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final (theme, label, bg, fg) in const [
                      (BibleReadingTheme.system, 'Auto', null, null),
                      (
                        BibleReadingTheme.light,
                        'Light',
                        Color(0xFFFFFFFF),
                        Color(0xFF1A1A2E)
                      ),
                      (
                        BibleReadingTheme.sepia,
                        'Sepia',
                        Color(0xFFF7F1E3),
                        Color(0xFF3A3222)
                      ),
                      (
                        BibleReadingTheme.dark,
                        'Dark',
                        Color(0xFF12100E),
                        Color(0xFFF2E7D0)
                      ),
                    ])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () {
                              BiblePrefsService.setReadingTheme(theme);
                              setSheet(() {});
                              setState(() {});
                            },
                            child: Container(
                              height: 56,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: bg ?? context.palette.cardMuted,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: BiblePrefsService.readingTheme() ==
                                          theme
                                      ? AppColors.primaryBlue
                                      : context.palette.divider,
                                  width:
                                      BiblePrefsService.readingTheme() == theme
                                          ? 2
                                          : 1,
                                ),
                              ),
                              child: Text(
                                label,
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: fg ?? context.palette.text,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
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
//  One chapter
// ---------------------------------------------------------------------------

//  One chapter
// ---------------------------------------------------------------------------

class _ChapterPage extends StatefulWidget {
  const _ChapterPage({
    super.key,
    required this.book,
    required this.chapter,
    required this.scale,
    required this.paper,
    required this.translation,
    required this.selected,
    required this.onToggleVerse,
    required this.onTapEmptySpace,
    this.scrollToVerse,
  });

  final BibleBook book;
  final int chapter;
  final double scale;
  final ({Color bg, Color fg, Color muted}) paper;

  /// Which Bible to render. The bundled KJV reads straight off the asset;
  /// everything else loads through [BibleTranslationService].
  final BibleTranslation translation;

  final Set<int> selected;
  final void Function(int verse) onToggleVerse;
  final VoidCallback onTapEmptySpace;
  final int? scrollToVerse;

  @override
  State<_ChapterPage> createState() => _ChapterPageState();
}

class _ChapterPageState extends State<_ChapterPage> {
  final _scrollCtrl = ScrollController();
  final _verseKeys = <int, GlobalKey>{};

  TranslatedChapter? _remote;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.translation.isRemote) _loadRemote();
    if (widget.scrollToVerse != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _verseKeys[widget.scrollToVerse]?.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx,
              duration: AppMotion.standard, alignment: 0.15);
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRemote() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final chapter = await BibleTranslationService.chapter(
      translation: widget.translation,
      bookIndex: widget.book.index,
      chapter: widget.chapter,
    );
    if (!mounted) return;
    setState(() {
      _remote = chapter;
      _loading = false;
      _failed = chapter == null;
    });
  }

  /// Verses for whichever translation is active.
  List<String> get _verses {
    if (widget.translation.isBundled) {
      return [
        for (final raw in widget.book.chapters[widget.chapter])
          BibleService.cleanVerse(raw),
      ];
    }
    return _remote?.verses ?? const [];
  }

  Map<int, String> get _headings => _remote?.headings ?? const {};

  @override
  Widget build(BuildContext context) {
    final t = widget.translation;

    // This translation genuinely doesn't contain this book (Greek NT has no
    // Genesis). Say so plainly instead of showing an empty chapter.
    if (!t.hasBook(widget.book.index)) {
      return _message(
        icon: Icons.menu_book_outlined,
        title: '${widget.book.name} is not in ${t.name}',
        body: t.coverage == TranslationCoverage.newTestament
            ? 'This is a New Testament text. Switch translation to read the '
                'Old Testament.'
            : 'This is an Old Testament text. Switch translation to read the '
                'New Testament.',
        action: 'Change translation',
      );
    }

    if (_loading) {
      return const Center(child: BrandSpinner(size: 28));
    }

    if (_failed) {
      return _message(
        icon: Icons.wifi_off_rounded,
        title: 'Not downloaded yet',
        body: '${t.name} needs a connection the first time you open a '
            'chapter. Once loaded it stays available offline.',
        action: 'Try again',
        onAction: _loadRemote,
      );
    }

    final verses = _verses;
    final headings = _headings;

    return TranslationCrossfade(
      translationId: t.id,
      child: ListView(
        controller: _scrollCtrl,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
        children: [
          _chapterHeading(t),
          const SizedBox(height: 14),
          for (var i = 0; i < verses.length; i++) ...[
            if (headings[i] != null) _sectionHeading(headings[i]!),
            _verse(context, i, verses[i]),
          ],
          const SizedBox(height: 28),
          GestureDetector(
            onTap: widget.onTapEmptySpace,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              height: 60,
              child: Center(
                child: Text(
                  'Swipe for the next chapter',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: widget.paper.muted,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chapterHeading(BibleTranslation t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${widget.book.name} ${widget.chapter + 1}',
          style: AppTextStyles.headlineSmall.copyWith(
            color: widget.paper.fg,
            fontWeight: FontWeight.w800,
            fontSize: 22 * widget.scale,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: t.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                t.name,
                style: AppTextStyles.labelSmall.copyWith(
                  color: t.accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 10.5,
                ),
              ),
            ),
            if (_remote?.hasAudio ?? false) ...[
              const SizedBox(width: 8),
              _listenButton(),
            ],
          ],
        ),
      ],
    );
  }

  /// Plays this chapter's narration through the shared music player, so it
  /// keeps going with the screen off and shows lock-screen controls — the
  /// same engine the Music tab uses.
  Widget _listenButton() {
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: _playChapterAudio,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.goldAccent.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.headphones_rounded,
                size: 13, color: AppColors.goldAccent),
            const SizedBox(width: 5),
            Text(
              'Listen',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.goldAccent,
                fontWeight: FontWeight.w700,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _playChapterAudio() async {
    final links = _remote?.audioLinks ?? const <String, String>{};
    if (links.isEmpty) return;
    // The API exposes several narrators; take the first deterministically
    // rather than adding a picker for a feature most users tap once.
    final url = links.values.first;
    final reference = '${widget.book.name} ${widget.chapter + 1}';
    final item = LibraryItem(
      id: 'bible-audio:${widget.translation.id}:'
          '${widget.book.index}:${widget.chapter}',
      kind: 'audio_bible',
      title: reference,
      fileUrl: url,
      author: widget.translation.name,
    );
    try {
      await MusicPlayerService.instance.setQueueAndPlay([item], 0);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Playing $reference')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not play this chapter: $e')),
      );
    }
  }

  /// Section headings ("Jesus Teaches Nicodemus") that modern translations
  /// carry. The KJV has none, so this only appears where it exists.
  Widget _sectionHeading(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8, left: 6),
      child: Text(
        text,
        textAlign: widget.translation.rtl ? TextAlign.right : TextAlign.left,
        style: AppTextStyles.titleSmall.copyWith(
          color: widget.translation.accent,
          fontWeight: FontWeight.w800,
          fontSize: 15 * widget.scale,
        ),
      ),
    );
  }

  Widget _message({
    required IconData icon,
    required String title,
    required String body,
    required String action,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: widget.paper.muted),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleSmall.copyWith(
                color: widget.paper.fg,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: widget.paper.muted,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
              ),
              onPressed: onAction ??
                  () async {
                    final chosen = await TranslationPicker.show(
                      context,
                      current: widget.translation,
                    );
                    if (chosen != null) {
                      await BibleTranslationService.setActive(chosen);
                    }
                  },
              child: Text(action),
            ),
          ],
        ),
      ),
    );
  }

  Widget _verse(BuildContext context, int i, String text) {
    final key = BiblePrefsService.verseKey(
        widget.book.index, widget.chapter, i);
    final hlIndex = BiblePrefsService.highlightColor(key);
    final bookmarked = BiblePrefsService.isBookmarked(key);
    final note = BiblePrefsService.note(key);
    final isSelected = widget.selected.contains(i);
    final rtl = widget.translation.rtl;
    _verseKeys[i] = GlobalKey();

    return Container(
      key: _verseKeys[i],
      margin: const EdgeInsets.only(bottom: 3),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.primaryBlue.withValues(alpha: 0.18)
            : hlIndex != null
                ? Color(BiblePrefsService.highlightColors[hlIndex])
                    .withValues(alpha: 0.55)
                : null,
        borderRadius: BorderRadius.circular(8),
        border: isSelected
            ? Border.all(color: AppColors.primaryBlue, width: 1.5)
            : null,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onToggleVerse(i);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                // Hebrew reads right-to-left; without this the verse number
                // lands on the wrong side and the text is unreadable.
                textDirection:
                    rtl ? TextDirection.rtl : TextDirection.ltr,
                textAlign: rtl ? TextAlign.right : TextAlign.left,
                text: TextSpan(
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: widget.paper.fg,
                    height: rtl ? 2.0 : 1.75,
                    fontSize: (rtl ? 18.5 : 16.5) * widget.scale,
                  ),
                  children: [
                    TextSpan(
                      text: '${i + 1}  ',
                      style: TextStyle(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5 * widget.scale,
                      ),
                    ),
                    TextSpan(text: text),
                    if (bookmarked)
                      const WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(Icons.bookmark_rounded,
                              size: 14, color: AppColors.goldAccent),
                        ),
                      ),
                  ],
                ),
              ),
              // Notes render inline rather than behind an icon — a note you
              // can't see is a note you forget you wrote.
              if (note != null) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(9),
                    border: const Border(
                      left: BorderSide(
                          color: AppColors.primaryBlue, width: 2.5),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.sticky_note_2_outlined,
                          size: 13, color: AppColors.primaryBlue),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          note,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: widget.paper.fg,
                            height: 1.45,
                            fontSize: 13 * widget.scale,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
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
  Timer? _debounce;
  List<BibleSearchHit> _hits = const [];
  bool _searching = false;
  bool _ran = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Live search as the user types (debounced so we don't scan the whole
  /// KJV on every keystroke). Clearing the box resets to the prompt state.
  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() {
        _hits = const [];
        _ran = false;
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(q));
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
        title: Text(
          'Search the Bible',
          style: AppTextStyles.appBarTitleFlat.copyWith(fontSize: 18),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Search box lives in the BODY (not the app bar) on an adaptive
            // surface, so the typed text uses palette.text — always visible in
            // BOTH light and dark mode (the app-bar field rendered the text
            // dark-on-dark in light mode: the "black spaces" the tester saw).
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                onSubmitted: _run,
                style: AppTextStyles.bodyMedium.copyWith(color: palette.text),
                cursorColor: AppColors.primaryBlue,
                decoration: InputDecoration(
                  hintText: 'Search a word or phrase…',
                  hintStyle: TextStyle(color: palette.textMuted),
                  prefixIcon: Icon(Icons.search, color: palette.textMuted),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(Icons.close, color: palette.textMuted),
                          onPressed: () {
                            _controller.clear();
                            _onChanged('');
                          },
                        ),
                  filled: true,
                  fillColor: palette.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.primaryBlue),
                  ),
                ),
              ),
            ),
            Expanded(child: _results(context, palette)),
          ],
        ),
      ),
    );
  }

  Widget _results(BuildContext context, AppPalette palette) {
    if (_searching) {
      return const Center(child: BrandSpinner(size: 30));
    }
    if (!_ran) {
      return Center(
        child: Text(
          'Type a word or phrase to search.',
          style: AppTextStyles.bodyMedium.copyWith(color: palette.textMuted),
        ),
      );
    }
    if (_hits.isEmpty) {
      return Center(
        child: Text(
          'No matches found.',
          style: AppTextStyles.bodyMedium.copyWith(color: palette.textMuted),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${_hits.length} result(s)',
              style: AppTextStyles.labelMedium.copyWith(
                color: palette.textMuted,
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: _hits.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final h = _hits[i];
              return Material(
                color: palette.card,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.of(context).pop();
                    widget.onOpen(h.book, h.chapter, scrollToVerse: h.verse);
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
                        Text(
                          h.reference,
                          style: AppTextStyles.labelMedium.copyWith(
                            color: AppColors.primaryBlue,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          h.text,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: palette.text,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
//  Saved (bookmarks + notes)
// ---------------------------------------------------------------------------

class BibleSavedScreen extends StatefulWidget {
  const BibleSavedScreen({
    super.key,
    required this.books,
    required this.onOpen,
  });
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
        title: Text(
          'Saved',
          style: AppTextStyles.appBarTitleFlat.copyWith(fontSize: 18),
        ),
        bottom: TabBar(
          controller: _tabs,
          dividerColor: Colors.transparent,
          indicatorColor: AppColors.primaryBlue,
          labelColor: AppColors.primaryBlue,
          unselectedLabelColor: const Color(0xFF7C8698),
          tabs: const [
            Tab(text: 'Bookmarks'),
            Tab(text: 'Notes'),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: TabBarView(
          controller: _tabs,
          children: [_bookmarksList(context), _notesList(context)],
        ),
      ),
    );
  }

  Widget _bookmarksList(BuildContext context) {
    final palette = context.palette;
    final keys = BiblePrefsService.bookmarks().toList()..sort();
    if (keys.isEmpty) {
      return _empty(
        context,
        Icons.bookmark_outline,
        'Bookmarked verses appear here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: keys.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final parsed = _parse(keys[i]);
        if (parsed == null) return const SizedBox.shrink();
        final raw = parsed.book.chapters[parsed.chapter][parsed.verse];
        final ref =
            '${parsed.book.name} ${parsed.chapter + 1}:${parsed.verse + 1}';
        return Material(
          color: palette.card,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.of(context).pop();
              widget.onOpen(
                parsed.book,
                parsed.chapter,
                scrollToVerse: parsed.verse,
              );
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
                      const Icon(
                        Icons.bookmark,
                        color: AppColors.goldAccent,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        ref,
                        style: AppTextStyles.labelMedium.copyWith(
                          color: AppColors.primaryBlue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    BibleService.cleanVerse(raw),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: palette.text,
                      height: 1.4,
                    ),
                  ),
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
      return _empty(
        context,
        Icons.sticky_note_2_outlined,
        'Your verse notes appear here.',
      );
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
              widget.onOpen(
                parsed.book,
                parsed.chapter,
                scrollToVerse: parsed.verse,
              );
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
                  Text(
                    ref,
                    style: AppTextStyles.labelMedium.copyWith(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entries[i].value,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: palette.text,
                      height: 1.4,
                    ),
                  ),
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
          Text(
            text,
            style: AppTextStyles.bodyMedium.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}
