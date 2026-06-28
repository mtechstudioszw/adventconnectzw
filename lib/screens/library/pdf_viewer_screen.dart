import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';

import '../../services/cache_service.dart';
import '../../services/download_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// Full-screen in-app PDF reader for Library hymnals + EGW books.
///
/// The PDF lives in the public `library` storage bucket. `flutter_pdfview`
/// renders from a LOCAL file, so we download once to the cache dir (keyed by
/// the URL hash) and reuse it on every subsequent open — which also makes a
/// once-opened book readable offline.
class PdfViewerScreen extends StatefulWidget {
  const PdfViewerScreen({super.key, required this.title, required this.url});

  final String title;
  final String url;

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  String? _localPath;
  String? _error;
  int _pages = 0;
  int _current = 0;
  late final int _resumePage;

  // Per-document last-page key, so reopening a book continues where you left
  // off (resume reading — a basic-feeling reader was the tester's complaint).
  String get _pageKey =>
      'pdf_page:${sha1.convert(widget.url.codeUnits)}';

  @override
  void initState() {
    super.initState();
    _resumePage =
        int.tryParse(CacheService.readPref(_pageKey) ?? '') ?? 0;
    _prepare();
  }

  Future<void> _prepare() async {
    try {
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
        await resp.pipe(file.openWrite());
      }
      if (!mounted) return;
      setState(() => _localPath = file.path);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error =
          'Could not open this file. Check your connection and try again.');
    }
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
          style: AppTextStyles.appBarTitle.copyWith(fontSize: 17),
        ),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.appBarGradient),
        ),
        foregroundColor: AppColors.white,
        actions: [
          IconButton(
            tooltip: 'Download',
            icon: const Icon(Icons.download_outlined),
            onPressed: () async {
              final ok = await DownloadService.downloadAndShare(
                url: widget.url,
                suggestedName: widget.title,
                mimeType: 'application/pdf',
              );
              if (mounted) DownloadService.toast(context, ok);
            },
          ),
        ],
        bottom: _pages > 0
            ? PreferredSize(
                preferredSize: const Size.fromHeight(22),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Page ${_current + 1} of $_pages',
                    style: AppTextStyles.labelSmall
                        .copyWith(color: AppColors.white.withValues(alpha: 0.8)),
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
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primaryBlue),
                )
              : PDFView(
                  filePath: _localPath,
                  swipeHorizontal: false,
                  autoSpacing: true,
                  pageFling: true,
                  // Resume where the reader left off last time.
                  defaultPage: _resumePage,
                  onRender: (pages) =>
                      setState(() => _pages = pages ?? 0),
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
