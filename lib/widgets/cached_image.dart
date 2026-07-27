import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
// flutter_cache_manager ships as a transitive dependency of
// cached_network_image (already in pubspec.lock), so importing it directly
// pulls in nothing new.
// ignore: depend_on_referenced_packages
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// HTTP file service that bounds how long a single image fetch may take.
///
/// The default [HttpFileService] awaits the response with NO timeout, so a
/// stalled socket (common on a flaky mobile network) leaves the download
/// future pending forever — which is exactly the "every image just spins and
/// never loads" bug the tester reported. Capping the request guarantees a
/// stuck fetch fails (→ error tile + retry) instead of hanging.
class _TimeoutHttpFileService extends HttpFileService {
  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) {
    return super.get(url, headers: headers).timeout(
          const Duration(seconds: 25),
        );
  }
}

/// Shared cache manager for all network images. Same disk-cache behaviour as
/// the default, but every fetch is time-bounded by [_TimeoutHttpFileService].
///
/// The limits are generous on purpose. At 400 objects the cache held roughly
/// one long session of feed scrolling, and feed photos are by far the highest
/// churn source of images in the app — so Library artwork (Sabbath School
/// quarterly covers, hymn and EGW jackets, album art) was being evicted
/// between visits and re-downloaded every time, which is what "the Sabbath
/// School images aren't cached" actually was. Library artwork is a small,
/// stable set; the feed is what should be losing the race for space.
final BaseCacheManager adventImageCacheManager = CacheManager(
  Config(
    'adventImageCache',
    stalePeriod: const Duration(days: 60),
    maxNrOfCacheObjects: 1200,
    fileService: _TimeoutHttpFileService(),
  ),
);

/// Pulls [urls] into the image cache ahead of time, ignoring failures.
///
/// Used by content services that already know which artwork a screen is about
/// to need, so a quarter opened once keeps its covers offline instead of
/// showing retry tiles on the next flight-mode launch.
Future<void> precacheImageUrls(Iterable<String?> urls) async {
  for (final url in urls) {
    if (url == null || url.isEmpty) continue;
    try {
      await adventImageCacheManager.downloadFile(url);
    } catch (_) {
      // Best-effort warm-up — the widget will fetch on demand if this failed.
    }
  }
}

/// Drop-in replacement for `Image.network(...)`. Disk-caches the image
/// via cached_network_image so post photos, avatars, product shots
/// etc. don't redownload on every scroll / app start.
///
/// The constructor signature mirrors `Image.network` (positional URL +
/// the most-used named params) so the migration was a mechanical
/// search-and-replace. `loadingBuilder` is accepted for API
/// compatibility but ignored — we use a light-grey placeholder while
/// the image streams in, which is simpler and matches the rest of
/// the app's skeleton states.
class CachedImage extends StatefulWidget {
  const CachedImage(
    this.url, {
    super.key,
    this.fit,
    this.width,
    this.height,
    this.errorBuilder,
    this.loadingBuilder,
  });

  final String url;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final ImageErrorWidgetBuilder? errorBuilder;

  // Kept for source-level compatibility with Image.network so call
  // sites compile unchanged. We don't have CachedNetworkImage chunk
  // events to forward to it, so it's intentionally unused.
  // ignore: unused_field
  final ImageLoadingBuilder? loadingBuilder;

  @override
  State<CachedImage> createState() => _CachedImageState();
}

class _CachedImageState extends State<CachedImage> {
  // Bumped on tap-to-retry: changing the provider key forces
  // CachedNetworkImage to recreate its provider and re-attempt the fetch.
  int _attempt = 0;

  @override
  Widget build(BuildContext context) {
    final url = widget.url;
    return CachedNetworkImage(
      key: ValueKey('$url#$_attempt'),
      imageUrl: url,
      cacheManager: adventImageCacheManager,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      fadeInDuration: const Duration(milliseconds: 180),
      fadeOutDuration: Duration.zero,
      useOldImageOnUrlChange: true,
      errorWidget: (ctx, _, error) {
        final builder = widget.errorBuilder;
        if (builder != null) {
          // Image.network's errorBuilder receives (context, Object, StackTrace?).
          // CachedNetworkImage only hands us the Object — pass null for the
          // stack trace, which is what most builders ignore anyway.
          return builder(ctx, error, null);
        }
        return _RetryTile(
          width: widget.width,
          height: widget.height,
          onRetry: () {
            adventImageCacheManager.removeFile(url).catchError((_) {});
            if (mounted) setState(() => _attempt++);
          },
        );
      },
      // Show a download progress ring while the image streams in (WhatsApp
      // style) so on a slow network a photo reads as "downloading", not a
      // blank/broken tile. Tiny tiles (avatars) just show the grey
      // placeholder — a ring would be bigger than the image.
      progressIndicatorBuilder: (context, url, progress) {
        final width = widget.width;
        final height = widget.height;
        final small =
            (width != null && width < 80) || (height != null && height < 80);
        // Tiny tiles (avatars) just show the grey placeholder. Larger
        // media shows a download progress BAR pinned to the bottom.
        return Stack(
          fit: StackFit.expand,
          children: [
            Container(
                width: width, height: height, color: context.palette.cardMuted),
            if (!small)
              Align(
                alignment: Alignment.bottomCenter,
                child: LinearProgressIndicator(
                  value: progress.progress, // null → indeterminate
                  minHeight: 4,
                  backgroundColor: Colors.black.withValues(alpha: 0.12),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.primaryBlue,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Tapped to re-attempt a failed image. Replaces the old static broken-image
/// tile so a transient network failure isn't a dead end.
class _RetryTile extends StatelessWidget {
  const _RetryTile({this.width, this.height, required this.onRetry});

  final double? width;
  final double? height;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final small =
        (width != null && width! < 80) || (height != null && height! < 80);
    return GestureDetector(
      onTap: onRetry,
      child: Container(
        width: width,
        height: height,
        color: AppColors.surfaceMuted,
        alignment: Alignment.center,
        child: Icon(
          small ? Icons.broken_image_outlined : Icons.refresh,
          color: AppColors.primaryBlue,
          size: 24,
        ),
      ),
    );
  }
}
