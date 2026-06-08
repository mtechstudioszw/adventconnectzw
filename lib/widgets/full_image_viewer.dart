import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'cached_image.dart';

/// Generic full-screen image viewer used app-wide for tap-to-expand:
/// avatars, cover photos, product images, event flyers, news covers,
/// etc. Pinch-to-zoom via InteractiveViewer; tap or back to dismiss.
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
      body: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: CachedImage(
                    imageUrl,
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
