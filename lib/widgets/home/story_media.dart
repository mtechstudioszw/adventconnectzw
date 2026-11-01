import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/story_model.dart';
import '../../services/e2ee/story_crypto.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../cached_image.dart';

/// Draws a story's photo, whatever state it is in (1 Nov 2026):
///  * plain: from its URL, as before;
///  * end-to-end encrypted (patch_300): downloaded, opened on the phone
///    with the story's key, shown from a local file;
///  * locked: encrypted but this phone has no key — says so instead of
///    drawing a broken image.
class StoryMedia extends StatelessWidget {
  const StoryMedia({
    super.key,
    required this.story,
    this.fit = BoxFit.cover,
    this.width,
    this.compact = false,
    this.errorBuilder,
  });

  final Story story;
  final BoxFit fit;
  final double? width;

  /// Rail thumbnails: just an icon when locked, no sentence.
  final bool compact;
  final Widget Function(BuildContext)? errorBuilder;

  @override
  Widget build(BuildContext context) {
    if (story.locked) return _Locked(compact: compact);
    if (story.mediaUrl.startsWith('/')) {
      return Image.file(
        File(story.mediaUrl),
        fit: fit,
        width: width,
        errorBuilder: (c, _, _) => _error(c),
      );
    }
    if (story.isEncrypted && story.mediaKey != null) {
      return FutureBuilder<String>(
        future: StoryCrypto.photoPath(story),
        builder: (context, snap) {
          if (snap.hasError) return _error(context);
          if (!snap.hasData) {
            return const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.white,
                ),
              ),
            );
          }
          return Image.file(
            File(snap.data!),
            fit: fit,
            width: width,
            errorBuilder: (c, _, _) => _error(c),
          );
        },
      );
    }
    return CachedImage(
      story.mediaUrl,
      fit: fit,
      width: width,
      errorBuilder: (c, _, _) => _error(c),
    );
  }

  Widget _error(BuildContext context) =>
      errorBuilder?.call(context) ??
      const Center(
        child: Icon(
          Icons.broken_image_outlined,
          size: 40,
          color: AppColors.white,
        ),
      );
}

class _Locked extends StatelessWidget {
  const _Locked({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.darkNavy,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: compact
          ? const Icon(Icons.lock_outline, color: AppColors.white, size: 22)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outline,
                  color: AppColors.white,
                  size: 36,
                ),
                const SizedBox(height: 12),
                Text(
                  'This story is end-to-end encrypted.\n'
                  'Update the app to see it.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.white,
                    height: 1.5,
                  ),
                ),
              ],
            ),
    );
  }
}
