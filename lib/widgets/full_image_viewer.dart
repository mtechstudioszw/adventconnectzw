import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/photo_url.dart';
import 'cached_image.dart';

/// Generic full-screen image viewer used app-wide for tap-to-expand:
/// avatars, cover photos, product images, event flyers, news covers,
/// etc. Pinch-to-zoom via InteractiveViewer; the ✕ button or system back
/// dismisses.
///
/// **Tapping the photo deliberately does nothing.** It used to pop the
/// route, which meant every attempt to steady a zoomed photo, or any stray
/// touch while reading a chat image, threw you out of the viewer. Zoom and
/// dismiss are different intents and a bare tap is far too easy to trigger
/// by accident to be wired to the destructive one.
///
/// Unlike PostImageViewer this needs no Hero tag — call
/// [FullImageViewer.show] with just a URL from anywhere.
class FullImageViewer extends StatelessWidget {
  const FullImageViewer({super.key, required this.imageUrl});

  final String imageUrl;

  /// Opens [imageUrl] full-screen. No-op for empty / null URLs so
  /// callers can wire it unconditionally.
  static Future<void> show(BuildContext context, String? imageUrl) {
    final url = (imageUrl ?? '').trim();
    if (url.isEmpty) return Future.value();
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, _, _) => FullImageViewer(imageUrl: url),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                // Ask for the biggest render the host will give us.
                //
                // CachedImage sizes its own request from the width/height it
                // is handed, and this one is deliberately unsized (BoxFit
                // .contain inside an InteractiveViewer), so it would fall
                // back to the URL as stored. For a Google avatar that URL is
                // `=s96-c` — a 96px image — which this screen then stretched
                // full-width and offered 4x zoom on. Hence "the Google
                // picture is far away and won't zoom": there was no detail
                // there to magnify. Non-Google URLs are returned unchanged.
                child: CachedImage(
                  photoUrlAtSize(imageUrl, 1024),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.white,
                      size: 56,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                icon: const Icon(Icons.close, color: AppColors.white),
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: 'Close',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
