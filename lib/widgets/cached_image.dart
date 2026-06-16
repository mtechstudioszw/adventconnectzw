import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

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
class CachedImage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: width,
      height: height,
      fadeInDuration: const Duration(milliseconds: 180),
      fadeOutDuration: Duration.zero,
      errorWidget: (ctx, _, error) {
        final builder = errorBuilder;
        if (builder != null) {
          // Image.network's errorBuilder receives (context, Object, StackTrace?).
          // CachedNetworkImage only hands us the Object — pass null for the
          // stack trace, which is what most builders ignore anyway.
          return builder(ctx, error, null);
        }
        return _defaultErrorTile(width: width, height: height);
      },
      // Show a download progress ring while the image streams in (WhatsApp
      // style) so on a slow network a photo reads as "downloading", not a
      // blank/broken tile. Tiny tiles (avatars) just show the grey
      // placeholder — a ring would be bigger than the image.
      progressIndicatorBuilder: (context, url, progress) {
        final small = (width != null && width! < 80) ||
            (height != null && height! < 80);
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

  static Widget _defaultErrorTile({double? width, double? height}) {
    // TODO(dark-mode): static method — see _placeholderTile note.
    return Container(
      width: width,
      height: height,
      color: AppColors.surfaceMuted,
      alignment: Alignment.center,
      child: const Icon(
        Icons.broken_image_outlined,
        color: AppColors.primaryBlue,
        size: 24,
      ),
    );
  }
}
