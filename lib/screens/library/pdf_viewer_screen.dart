import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/share_config.dart';
import '../../services/cache_service.dart';
import '../../services/download_service.dart';
import '../../services/egw_download_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// Shared keys + helpers for per-book reading progress.
///
/// Lives here (next to the writer) so the Library bookshelf and the reader
/// can never drift apart on key naming.
class PdfProgress {
  PdfProgress._();

  static String _hash(String url) => sha1.convert(url.codeUnits).toString();

  /// Last page the reader stopped on (0-based).
  static String lastPageKey(String url) => 'pdf_page:${_hash(url)}';

  /// Total pages, learned the first time the book renders.
  static String pageCountKey(String url) => 'pdf_pages:${_hash(url)}';

  /// Reading progress 0.0–1.0, or null when the book was never opened.
  static double? progressFor(String url) {
    final page = int.tryParse(CacheService.readPref(lastPageKey(url)) ?? '');
    final total = int.tryParse(CacheService.readPref(pageCountKey(url)) ?? '');
    if (page == null || total == null || total <= 1) return null;
    return ((page + 1) / total).clamp(0.0, 1.0);
  }

  /// "Page 42 of 380", or null when never opened.
  static String? positionLabel(String url) {
    final page = int.tryParse(CacheService.readPref(lastPageKey(url)) ?? '');
    final total = int.tryParse(CacheService.readPref(pageCountKey(url)) ?? '');
    if (page == null) return null;
    if (total == null || total <= 0) return 'Page ${page + 1}';
    return 'Page ${page + 1} of $total';
  }

  /// True once the book has been opened at least once.
  static bool hasStarted(String url) =>
      CacheService.readPref(lastPageKey(url)) != null;
}

/// Full-screen in-app PDF reader for Library hymnals + EGW books.
///
/// The PDF lives in the public `library` storage bucket. `flutter_pdfview`
/// renders from a LOCAL file, so we download once to the cache dir (keyed by
/// the URL hash) and reuse it on every subsequent open — which also makes a
/// once-opened book readable offline.
class PdfViewerScreen extends StatefulWidget {
  const PdfViewerScreen({
    super.key,
    required this.title,
    required this.url,
    this.itemId,
  });

  final String title;
  final String url;

  /// `library_items.id` when this document is a Library book.
  ///
  /// Lets the reader check [EgwDownloadService] for a DURABLE copy before
  /// falling back to its own cache. Optional because this screen also opens
  /// documents that were never Library rows (the bundled hymnal).
  ///
  /// The distinction matters: _prepare() below already caches every PDF it
  /// fetches, but into `getApplicationCacheDirectory()`, which the OS may
  /// reclaim whenever storage is tight. That is fine for "I read this once";
  /// it is not what someone means when they deliberately download a book for
  /// a journey. A file saved through EgwDownloadService lives in application
  /// SUPPORT and is only ever removed by the reader.
  final String? itemId;

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  String? _localPath;
  String? _error;
  double? _progress; // download progress 0–1 (null = size unknown)
  int _pages = 0;
  int _current = 0;
  late final int _resumePage;
  /// Night mode OVERRIDE. Null means "follow the app theme".
  ///
  /// This was a plain `bool _night = false`, so the reader opened on a
  /// blazing white page even with the whole app in dark mode — which is
  /// what "dark mode doesn't work in EGW" is (founder, 17 Aug). The page
  /// content is a rendered PDF, so no amount of `context.palette` on the
  /// chrome could reach it; the renderer's own nightMode is the only lever.
  ///
  /// Kept as an override rather than replaced outright: a reader
  /// legitimately wants to flip it per book, and once they do, their
  /// choice must win over the theme for the rest of the session.
  bool? _nightOverride;
  PDFViewController? _ctrl;

  /// Only ever read from `build` — it needs a context to see the theme.
  bool get _night =>
      _nightOverride ?? Theme.of(context).brightness == Brightness.dark;

  // Per-document last-page key, so reopening a book continues where you left
  // off (resume reading — a basic-feeling reader was the tester's complaint).
  String get _pageKey => PdfProgress.lastPageKey(widget.url);

  @override
  void initState() {
    super.initState();
    _resumePage =
        int.tryParse(CacheService.readPref(_pageKey) ?? '') ?? 0;
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      // A deliberately downloaded copy wins over the incidental cache, and
      // skips the network entirely — including the HttpClient call below,
      // which is what made an offline open fail even when the bytes were
      // already on the device.
      final id = widget.itemId;
      if (id != null) {
        final durable = await EgwDownloadService.localPath(id);
        if (durable != null) {
          if (!mounted) return;
          setState(() => _localPath = durable);
          return;
        }
      }
      final dir = await getApplicationCacheDirectory();
      final name = sha1.convert(widget.url.codeUnits).toString();
      final file = File('${dir.path}/library_$name.pdf');

      if (!await file.exists() || (await file.length()) == 0) {
        final client = HttpClient();
        final req = await client.getUrl(Uri.parse(widget.url));
        final resp = await req.close();
        if (resp.statusCode != 200) {
          throw HttpException('HTTP ${resp.statusCode}');
        }
        // Stream to disk while reporting progress, so a big book shows a
        // real "Downloading 42%" instead of an endless spinner.
        final total = resp.contentLength;
        final sink = file.openWrite();
        var received = 0;
        await for (final chunk in resp) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0 && mounted) {
            setState(() => _progress = received / total);
          }
        }
        await sink.close();
      }
      if (!mounted) return;
      setState(() => _localPath = file.path);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error =
          'Could not open this file. Check your connection and try again.');
    }
  }

  /// Jump to a page by number. Tapping the "Page X of Y" indicator opens this.
  Future<void> _openJumpDialog() async {
    if (_pages <= 0) return;
    final palette = context.palette;
    final controller = TextEditingController(text: '${_current + 1}');
    final page = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.card,
        title: Text('Go to page',
            style: AppTextStyles.titleMedium
                .copyWith(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: AppTextStyles.bodyLarge.copyWith(color: palette.text),
          decoration: InputDecoration(
            hintText: '1 – $_pages',
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
            child: Text('Cancel', style: TextStyle(color: palette.textMuted)),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.primaryBlue),
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(controller.text.trim())),
            child: const Text('Go'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (page == null) return;
    final target = page.clamp(1, _pages) - 1;
    await _ctrl?.setPage(target);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      appBar: AppBar(
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.appBarTitleFlat.copyWith(fontSize: 17),
        ),
        actions: [
          IconButton(
            tooltip: _night ? 'Day mode' : 'Night mode',
            icon: Icon(_night
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined),
            // Records an explicit choice, which then outranks the theme.
            onPressed: () => setState(() => _nightOverride = !_night),
          ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => Share.share(
              '${widget.title}\n\nReading on Advent Connect ZW — get the app:\n$appDownloadUrl',
            ),
          ),
          IconButton(
            tooltip: 'Download',
            icon: const Icon(Icons.download_outlined),
            onPressed: () async {
              final ok = await DownloadService.downloadAndShare(
                url: widget.url,
                suggestedName: widget.title,
                mimeType: 'application/pdf',
              );
              if (context.mounted) DownloadService.toast(context, ok);
            },
          ),
        ],
        bottom: _pages > 0
            ? PreferredSize(
                preferredSize: const Size.fromHeight(26),
                child: GestureDetector(
                  onTap: _openJumpDialog,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Page ${_current + 1} of $_pages',
                          style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.white.withValues(alpha: 0.85)),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.unfold_more,
                            size: 13,
                            color: AppColors.white.withValues(alpha: 0.7)),
                      ],
                    ),
                  ),
                ),
              )
            : null,
      ),
      body: _error != null
          ? _ErrorView(message: _error!, onRetry: () {
              setState(() => _error = null);
              _prepare();
            })
          : _localPath == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                          value: _progress, color: AppColors.primaryBlue),
                      const SizedBox(height: 14),
                      Text(
                        _progress == null
                            ? 'Opening…'
                            : 'Downloading ${(_progress! * 100).round()}%',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: palette.textMuted),
                      ),
                    ],
                  ),
                )
              : PDFView(
                  filePath: _localPath,
                  swipeHorizontal: false,
                  autoSpacing: true,
                  pageFling: true,
                  nightMode: _night,
                  // Resume where the reader left off last time.
                  defaultPage: _resumePage,
                  onViewCreated: (c) => _ctrl = c,
                  onRender: (pages) {
                    setState(() => _pages = pages ?? 0);
                    // Persist the length too, so the Library bookshelf can
                    // show "page 42 of 380" progress without opening the file.
                    if (pages != null && pages > 0) {
                      CacheService.writePref(
                        PdfProgress.pageCountKey(widget.url),
                        pages.toString(),
                      );
                    }
                    // Mark the book STARTED on render, not on the first page
                    // turn.
                    //
                    // The page was only ever written by onPageChanged, so a
                    // book you opened and read without swiping was invisible
                    // to `PdfProgress.hasStarted` — and the EGW shelf's
                    // "Continue reading" hero filters on exactly that. Open
                    // Steps to Christ and turn a page, then open Great
                    // Controversy and read page one, and the hero still
                    // offered Steps to Christ (founder, 17 Aug).
                    //
                    // Only writes when absent, so it can never clobber a real
                    // resume position with the default page.
                    if (!PdfProgress.hasStarted(widget.url)) {
                      CacheService.writePref(_pageKey, _resumePage.toString());
                    }
                  },
                  onPageChanged: (page, _) {
                    setState(() => _current = page ?? 0);
                    // Remember the page so the next open resumes here.
                    if (page != null) {
                      CacheService.writePref(_pageKey, page.toString());
                    }
                  },
                  onError: (_) => setState(() =>
                      _error = 'This PDF could not be displayed.'),
                ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.picture_as_pdf_outlined,
                size: 56, color: palette.textMuted),
            const SizedBox(height: 14),
            Text(message,
                textAlign: TextAlign.center,
                style:
                    AppTextStyles.bodyMedium.copyWith(color: palette.textMuted)),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
