import 'package:flutter/material.dart';
import '../../models/story_model.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Horizontal "stories" rail that sits near the top of the home feed.
/// The first tile is always "Your story" — tapping it opens the
/// composer. Subsequent tiles are one per author, with their newest
/// story used as the preview. Tapping an author tile pops the full-
/// screen viewer (handled by the parent via onAuthorTapped).
class StoriesRail extends StatelessWidget {
  const StoriesRail({
    super.key,
    required this.stories,
    required this.viewerId,
    required this.viewerName,
    required this.viewerPhotoUrl,
    required this.onAddStory,
    required this.onAuthorTapped,
  });

  final List<Story> stories;
  final String viewerId;
  final String viewerName;
  final String? viewerPhotoUrl;
  final VoidCallback onAddStory;
  final void Function(String authorId, List<Story> authorStories) onAuthorTapped;

  @override
  Widget build(BuildContext context) {
    // Group by author so each member surfaces once even if they posted
    // multiple stories in the last 24h. Preserves the
    // newest-author-first order from the input.
    final byAuthor = <String, List<Story>>{};
    for (final story in stories) {
      byAuthor.putIfAbsent(story.authorId, () => []).add(story);
    }
    final authorIds = byAuthor.keys.toList();

    return SizedBox(
      height: 108,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: authorIds.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _AddStoryTile(
              viewerName: viewerName,
              viewerPhotoUrl: viewerPhotoUrl,
              onTap: onAddStory,
            );
          }
          final authorId = authorIds[index - 1];
          final authorStories = byAuthor[authorId]!;
          final preview = authorStories.first;
          return _StoryTile(
            story: preview,
            onTap: () => onAuthorTapped(authorId, authorStories),
          );
        },
      ),
    );
  }
}

class _AddStoryTile extends StatelessWidget {
  const _AddStoryTile({
    required this.viewerName,
    required this.viewerPhotoUrl,
    required this.onTap,
  });

  final String viewerName;
  final String? viewerPhotoUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 72,
          child: Column(
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.lightGrey,
                      border: Border.all(
                        color: const Color.fromRGBO(26, 26, 46, 0.08),
                        width: 1.5,
                      ),
                    ),
                    child: viewerPhotoUrl == null || viewerPhotoUrl!.isEmpty
                        ? _initialAvatar(viewerName)
                        : Image.network(
                            viewerPhotoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                _initialAvatar(viewerName),
                          ),
                  ),
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.white, width: 2.0),
                    ),
                    child: const Icon(
                      Icons.add,
                      size: 14,
                      color: AppColors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Your story',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelSmall.copyWith(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _initialAvatar(String name) {
    final initial = name.trim().isEmpty
        ? '?'
        : name.trim().substring(0, 1).toUpperCase();
    return Container(
      decoration: BoxDecoration(gradient: AppColors.primaryGradient),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: AppTextStyles.titleMedium.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w700,
          fontSize: 22,
        ),
      ),
    );
  }
}

class _StoryTile extends StatelessWidget {
  const _StoryTile({required this.story, required this.onTap});

  final Story story;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 72,
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.primaryGradient,
                ),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.white,
                  ),
                  child: ClipOval(
                    child: Image.network(
                      story.mediaUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: AppColors.lightGrey,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.image_not_supported_outlined,
                          size: 18,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                story.authorName.split(' ').first,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelSmall.copyWith(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
