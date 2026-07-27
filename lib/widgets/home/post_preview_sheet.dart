import 'package:flutter/material.dart';

import '../../models/post_model.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../motion/pressable.dart';
import 'post_card.dart';

/// "See it before you send it" — shows the post exactly as the feed will
/// render it.
///
/// It renders the **real [PostCard]**, not a lookalike, on the real feed
/// background. That is the whole value: a mock would drift from the card the
/// moment either changed, and would quietly lie about the two things people
/// actually want to check — where the text wraps, and how the photos crop.
///
/// Interactions are inert. Like/comment/menu are wired to no-ops because
/// nothing exists to act on yet: the post has no id until it is published.
///
/// Returns `true` if the member pressed **Post** from here, so the composer
/// can publish without making them go back first.
Future<bool> showPostPreview(
  BuildContext context, {
  required String body,
  required List<String> photos,
  required PostVisibility visibility,
  String? churchName,
  String? churchPhotoUrl,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PostPreviewSheet(
      body: body,
      photos: photos,
      visibility: visibility,
      churchName: churchName,
      churchPhotoUrl: churchPhotoUrl,
    ),
  );
  return result ?? false;
}

class _PostPreviewSheet extends StatelessWidget {
  const _PostPreviewSheet({
    required this.body,
    required this.photos,
    required this.visibility,
    this.churchName,
    this.churchPhotoUrl,
  });

  final String body;
  final List<String> photos;
  final PostVisibility visibility;
  final String? churchName;
  final String? churchPhotoUrl;

  /// Builds the post the feed would show, from what's in the composer.
  ///
  /// `createdAt` is now, so the card's relative timestamp reads "just now" —
  /// which is exactly what it will say a second after publishing.
  Post _draftPost() {
    final user = AuthService.currentUser;
    final meta = user?.userMetadata ?? const {};
    final trimmed = body.trim();
    return Post(
      // Never persisted — the real id is assigned by the insert.
      id: 'preview',
      authorId: user?.id ?? 'preview',
      authorName: (meta['full_name'] as String?)?.trim().isNotEmpty == true
          ? (meta['full_name'] as String).trim()
          : 'You',
      authorPhotoUrl: (meta['profile_photo_url'] as String?)?.trim(),
      createdAt: DateTime.now(),
      body: trimmed.isEmpty ? null : trimmed,
      imageUrl: photos.isEmpty ? null : photos.first,
      imageUrls: photos,
      visibility: visibility,
      churchName: churchName,
      churchPhotoUrl: churchPhotoUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final media = MediaQuery.of(context);

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
        decoration: BoxDecoration(
          color: palette.sheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.lg,
                AppSpace.lg,
                AppSpace.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'PREVIEW',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.primaryBlue,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.6,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'How your post will look',
                          style: AppTextStyles.titleLarge.copyWith(
                            color: palette.text,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Back to editing',
                    icon: Icon(Icons.close_rounded, color: palette.text),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
            // The feed's own background behind the card, so the preview shows
            // the real contrast rather than the sheet's surface colour.
            Flexible(
              child: Container(
                width: double.infinity,
                color: palette.scaffoldBg,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
                  child: IgnorePointer(
                    // Inert on purpose: there is nothing to like or comment on
                    // until this post exists.
                    child: PostCard(
                      post: _draftPost(),
                      viewerId: AuthService.currentUser?.id,
                      onLikeToggled: () {},
                      onCommentsTapped: () {},
                      onImageTapped: (_) {},
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.md,
                AppSpace.lg,
                AppSpace.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Pressable(
                      onTap: () => Navigator.of(context).pop(false),
                      pressedScale: 0.97,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: palette.card,
                          borderRadius: AppRadius.buttonAll,
                          border: Border.all(color: palette.divider),
                        ),
                        child: Text(
                          'Keep editing',
                          style: AppTextStyles.buttonText.copyWith(
                            color: palette.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Pressable(
                      onTap: () => Navigator.of(context).pop(true),
                      haptics: true,
                      pressedScale: 0.97,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: AppRadius.buttonAll,
                          boxShadow: AppShadows.glow(context),
                        ),
                        child: Text(
                          'Post it',
                          style: AppTextStyles.buttonText.copyWith(
                            color: AppColors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
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
