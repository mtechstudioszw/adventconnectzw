import 'package:flutter/material.dart';

import '../../models/bible_translation.dart';
import '../../services/bible_audio_service.dart';
import '../../services/bible_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/screen_shell.dart';
import 'widgets/bible_listen_sheet.dart';

/// Bible → Audio (2 Nov 2026). It used to open an empty catalogue ("Audio
/// Bible will appear here once it's added") because no tracks were ever
/// uploaded. Now: every book of the narrated English Bible, tap a chapter
/// to listen, and keep whole books on the phone.
class AudioBibleBooksScreen extends StatefulWidget {
  const AudioBibleBooksScreen({super.key, required this.books});

  final List<BibleBook> books;

  @override
  State<AudioBibleBooksScreen> createState() => _AudioBibleBooksScreenState();
}

class _AudioBibleBooksScreenState extends State<AudioBibleBooksScreen> {
  Future<void> _openBook(BibleBook book) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.sheet,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ChapterPicker(book: book),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final ot = widget.books.where((b) => b.isOldTestament).toList();
    final nt = widget.books.where((b) => !b.isOldTestament).toList();
    Widget section(String title, List<BibleBook> books) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Text(
            title.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
              color: palette.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              for (var i = 0; i < books.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, indent: 60, color: palette.divider),
                _bookRow(books[i]),
              ],
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const ScreenHero(
              title: 'Audio Bible',
              tagline: 'Listen',
              fallbackRoute: 'library',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'The ${BibleAudio.narratedTranslation}, read aloud by '
                '${BibleAudio.narrator.name}. Tap a book to choose a chapter; '
                'it keeps playing through the book.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: palette.textMuted,
                  height: 1.45,
                ),
              ),
            ),
            section('Old Testament', ot),
            section('New Testament', nt),
          ],
        ),
      ),
    );
  }

  Widget _bookRow(BibleBook book) {
    final palette = context.palette;
    final have = BibleAudio.downloadedInBook(book.index, book.chapterCount);
    return InkWell(
      onTap: () => _openBook(book),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.headphones_rounded,
                size: 18,
                color: AppColors.primaryBlue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                book.name,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: palette.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              have == book.chapterCount
                  ? 'Offline'
                  : have > 0
                  ? '$have/${book.chapterCount} saved'
                  : '${book.chapterCount} ch',
              style: AppTextStyles.bodySmall.copyWith(
                color: have == book.chapterCount
                    ? AppColors.primaryBlue
                    : palette.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            Icon(Icons.chevron_right, color: palette.textMuted),
          ],
        ),
      ),
    );
  }
}

class _ChapterPicker extends StatelessWidget {
  const _ChapterPicker({required this.book});
  final BibleBook book;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              book.name,
              style: AppTextStyles.titleLarge.copyWith(
                color: palette.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose a chapter. Hold a chapter for download options.',
              style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: GridView.count(
                crossAxisCount: 6,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                shrinkWrap: true,
                children: [
                  for (var c = 0; c < book.chapterCount; c++)
                    _chapterTile(context, c),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chapterTile(BuildContext context, int c) {
    final palette = context.palette;
    final saved = BibleAudio.isDownloaded(book.index, c);
    void openSheet() {
      Navigator.of(context).pop();
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: palette.sheet,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => BibleListenSheet(
          bookIndex: book.index,
          bookName: book.name,
          chapter: c,
          chapters: [for (final ch in book.chapters) ch.length],
          translation: BibleTranslations.bsb,
        ),
      );
    }

    return Material(
      color: saved
          ? AppColors.primaryBlue.withValues(alpha: 0.16)
          : palette.cardMuted,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          Navigator.of(context).pop();
          try {
            await BibleAudio.play(
              bookIndex: book.index,
              chapter: c,
              bookName: book.name,
              chapterCount: book.chapterCount,
            );
          } catch (_) {}
        },
        onLongPress: openSheet,
        child: Center(
          child: Text(
            '${c + 1}',
            style: AppTextStyles.bodyMedium.copyWith(
              color: saved ? AppColors.primaryBlue : palette.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
