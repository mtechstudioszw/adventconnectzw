import 'package:flutter/material.dart';

import '../../../models/bible_translation.dart';
import '../../../services/bible_audio_service.dart';
import '../../../services/music_download_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';

/// "Listen to John 3": play, choose a voice, and keep chapters or a whole
/// book on the phone for offline listening (2 Nov 2026).
class BibleListenSheet extends StatefulWidget {
  const BibleListenSheet({
    super.key,
    required this.bookIndex,
    required this.bookName,
    required this.chapter,
    required this.chapters,
    required this.translation,
  });

  final int bookIndex;
  final String bookName;
  final int chapter;

  /// Verse count per chapter of this book (for size estimates).
  final List<int> chapters;
  final BibleTranslation translation;

  @override
  State<BibleListenSheet> createState() => _BibleListenSheetState();
}

class _BibleListenSheetState extends State<BibleListenSheet> {
  bool _starting = false;
  bool _chapterBusy = false;

  int get _bookVerses => widget.chapters.fold(0, (a, b) => a + b);

  String _mb(double mb) =>
      mb >= 100 ? '${mb.round()} MB' : '${mb.toStringAsFixed(1)} MB';

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _play() async {
    setState(() => _starting = true);
    try {
      await BibleAudio.play(
        bookIndex: widget.bookIndex,
        chapter: widget.chapter,
        bookName: widget.bookName,
        chapterCount: widget.chapters.length,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        _toast(
          BibleAudio.isDownloaded(widget.bookIndex, widget.chapter)
              ? "Couldn't play this chapter."
              : "Couldn't play. Check your connection, or download the chapter first.",
        );
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _toggleChapter() async {
    final b = widget.bookIndex, c = widget.chapter;
    setState(() => _chapterBusy = true);
    if (BibleAudio.isDownloaded(b, c)) {
      await BibleAudio.removeChapter(b, c);
    } else {
      final ok = await BibleAudio.downloadChapter(b, c, widget.bookName);
      if (!ok && mounted) _toast("Couldn't download. Check your connection.");
    }
    if (mounted) setState(() => _chapterBusy = false);
  }

  Future<void> _downloadBook() async {
    final failed = await BibleAudio.downloadBook(
      widget.bookIndex,
      widget.bookName,
      widget.chapters.length,
    );
    if (!mounted) return;
    setState(() {});
    _toast(
      failed == 0
          ? '${widget.bookName} is ready to play offline.'
          : '$failed chapters didn\'t download. Tap again to finish.',
    );
  }

  Future<void> _removeBook() async {
    await BibleAudio.removeBook(widget.bookIndex, widget.chapters.length);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final b = widget.bookIndex, c = widget.chapter;
    final chapterVerses = c < widget.chapters.length ? widget.chapters[c] : 30;
    final chapterDone = BibleAudio.isDownloaded(b, c);
    final voice = BibleAudio.narrator;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Listen to ${widget.bookName} ${c + 1}',
              style: AppTextStyles.titleLarge.copyWith(
                color: palette.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              BibleAudio.wordingDiffers(widget.translation)
                  ? 'Read aloud from the ${BibleAudio.narratedTranslation}. '
                        'Its wording differs a little from the '
                        '${widget.translation.name} on screen.'
                  : 'Read aloud by a narrator. Keeps playing through the '
                        'rest of ${widget.bookName}.',
              style: AppTextStyles.bodySmall.copyWith(
                color: palette.textMuted,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _starting ? null : _play,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: _starting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.white,
                        ),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(chapterDone ? 'Play (offline)' : 'Play'),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'VOICE',
              style: AppTextStyles.labelSmall.copyWith(
                color: palette.textMuted,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final n in BibleAudio.narrators)
                  ChoiceChip(
                    label: Text(n.name),
                    selected: n.id == voice.id,
                    onSelected: (_) async {
                      await BibleAudio.setNarrator(n);
                      if (mounted) setState(() {});
                    },
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'LISTEN OFFLINE',
              style: AppTextStyles.labelSmall.copyWith(
                color: palette.textMuted,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 6),
            ValueListenableBuilder<Map<String, double>>(
              valueListenable: MusicDownloadService.progress,
              builder: (context, prog, _) {
                final p = prog[BibleAudio.trackId(b, c)];
                return _Row(
                  icon: chapterDone
                      ? Icons.offline_pin_rounded
                      : Icons.download_rounded,
                  title: chapterDone
                      ? 'This chapter is on your phone'
                      : 'Download this chapter',
                  subtitle: chapterDone
                      ? 'Tap to remove it'
                      : 'About ${_mb(BibleAudio.estimateMb(chapterVerses))}',
                  progress: p,
                  busy: _chapterBusy && p == null,
                  onTap: _chapterBusy ? null : _toggleChapter,
                );
              },
            ),
            ValueListenableBuilder<Map<int, ({int done, int total})>>(
              valueListenable: BibleAudio.bookProgress,
              builder: (context, books, _) {
                final run = books[b];
                final have = BibleAudio.downloadedInBook(
                  b,
                  widget.chapters.length,
                );
                final all = have == widget.chapters.length;
                return _Row(
                  icon: all
                      ? Icons.library_add_check_rounded
                      : Icons.download_for_offline_rounded,
                  title: run != null
                      ? 'Downloading ${widget.bookName}… '
                            '${run.done + 1} of ${run.total}'
                      : all
                      ? 'All of ${widget.bookName} is on your phone'
                      : 'Download all of ${widget.bookName}',
                  subtitle: run != null
                      ? 'Tap to stop'
                      : all
                      ? 'Tap to remove all ${widget.chapters.length} chapters'
                      : '${widget.chapters.length} chapters · about '
                            '${_mb(BibleAudio.estimateMb(_bookVerses))}'
                            '${have > 0 ? ' · $have already saved' : ''}',
                  progress: run == null ? null : run.done / run.total,
                  onTap: run != null
                      ? () => BibleAudio.cancelBook(b)
                      : all
                      ? _removeBook
                      : _downloadBook,
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Downloads use the selected voice. Use Wi-Fi for whole books.',
              style: AppTextStyles.bodySmall.copyWith(
                color: palette.textMuted,
                fontSize: 11.5,
              ),
            ),
          ],
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
    required this.onTap,
    this.progress,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final double? progress;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primaryBlue, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: palette.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (progress != null || busy)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 2),
                      child: LinearProgressIndicator(
                        value: busy ? null : progress,
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(2),
                        color: AppColors.primaryBlue,
                        backgroundColor: palette.divider,
                      ),
                    ),
                  Text(
                    subtitle,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
