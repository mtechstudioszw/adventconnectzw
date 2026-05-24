import 'package:flutter/material.dart';
import '../../models/story_model.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../cached_image.dart';

/// Facebook-style horizontal stories rail with vertical 9:16-ish
/// cards. First card is always "Your story" (full-bleed avatar +
/// blue + button on the seam). Subsequent cards are per-author, each
/// rendered as a stacked layer:
///   - background: full-bleed story image with a dark bottom gradient
///   - top-left: floating circular avatar (ringed for unread, dim
///     for read)
///   - bottom-left: author name in white on top of the gradient
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
    // multiple stories in the last 24h. Viewer's own stories surface
    // on the leading "Your story" card.
    final byAuthor = <String, List<Story>>{};
    for (final story in stories) {
      byAuthor.putIfAbsent(story.authorId, () => []).add(story);
    }
    final ownStories = byAuthor.remove(viewerId);
    final otherAuthors = byAuthor.keys.toList();

    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: otherAuthors.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _YourStoryCard(
              viewerName: viewerName,
              viewerPhotoUrl: viewerPhotoUrl,
              ownStories: ownStories,
              onAdd: onAddStory,
              onView: ownStories == null
                  ? null
                  : () => onAuthorTapped(viewerId, ownStories),
            );
          }
          final authorId = otherAuthors[index - 1];
          final list = byAuthor[authorId]!;
          final preview = list.first;
          return _FriendStoryCard(
            story: preview,
            onTap: () => onAuthorTapped(authorId, list),
          );
        },
      ),
    );
  }
}

/// Vertical 3:4 "Your story" card. If the viewer has posted a story
/// in the last 24h, the top half shows its image. Otherwise the top
/// half shows their avatar. The bottom half is always a small white
/// banner with a blue + button on the seam and "Create story" label.
class _YourStoryCard extends StatelessWidget {
  const _YourStoryCard({
    required this.viewerName,
    required this.viewerPhotoUrl,
    required this.ownStories,
    required this.onAdd,
    required this.onView,
  });

  final String viewerName;
  final String? viewerPhotoUrl;
  final List<Story>? ownStories;
  final VoidCallback onAdd;
  final VoidCallback? onView;

  bool get _hasStory => ownStories != null && ownStories!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: SizedBox(
        width: 116,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            color: AppColors.white,
            child: InkWell(
              // Single tap region for the whole card. When the viewer
              // hasn't posted yet the whole thing is "Create story";
              // once they have one, tapping opens their viewer and a
              // tiny "+" badge in the top-right adds another.
              onTap: _hasStory ? onView : onAdd,
              child: Stack(
                children: [
                  Column(
                    children: [
                      // Top: ~70% image / avatar.
                      Expanded(
                        flex: 7,
                        child: _hasStory
                            ? CachedImage(
                                ownStories!.first.mediaUrl,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                errorBuilder: (_, _, _) =>
                                    _avatarBackground(),
                              )
                            : _avatarBackground(),
                      ),
                      // Bottom: white banner with label only — no overlay
                      // button to avoid the double-tap target the old
                      // layout had.
                      Expanded(
                        flex: 3,
                        child: Container(
                          color: AppColors.white,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            _hasStory ? 'Your story' : 'Create story',
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.labelMedium.copyWith(
                              color: AppColors.textDark,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // "+" affordance — when the viewer already has a story
                  // we show a small badge in the corner so they can add
                  // another. When they don't, the whole card acts as
                  // "Create" so an overlay button is redundant.
                  if (_hasStory)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: GestureDetector(
                        onTap: onAdd,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.white,
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryBlue
                                    .withValues(alpha: 0.35),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.add,
                            color: AppColors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatarBackground() {
    if (viewerPhotoUrl != null && viewerPhotoUrl!.isNotEmpty) {
      return CachedImage(
        viewerPhotoUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, _, _) => _initialFill(),
      );
    }
    return _initialFill();
  }

  Widget _initialFill() {
    final initial = viewerName.trim().isEmpty
        ? '?'
        : viewerName.trim().substring(0, 1).toUpperCase();
    return Container(
      decoration: BoxDecoration(gradient: AppColors.primaryGradient),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: AppTextStyles.displayMedium.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w700,
          fontSize: 40,
        ),
      ),
    );
  }
}

/// Vertical 3:4 card for someone else's story.
class _FriendStoryCard extends StatelessWidget {
  const _FriendStoryCard({required this.story, required this.onTap});

  final Story story;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: SizedBox(
        width: 116,
        child: GestureDetector(
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Layer 1: full-bleed story image.
                CachedImage(
                  story.mediaUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: AppColors.darkNavy,
                  ),
                ),
                // Dark gradient to keep the name legible.
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.25),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.55),
                        ],
                        stops: const [0.0, 0.4, 1.0],
                      ),
                    ),
                  ),
                ),
                // Layer 2: floating avatar top-left with blue ring.
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      shape: BoxShape.circle,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.white,
                      ),
                      child: ClipOval(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: (story.authorPhotoUrl ?? '').isEmpty
                              ? _initialAvatar(story.authorName)
                              : CachedImage(
                                  story.authorPhotoUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      _initialAvatar(story.authorName),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Layer 3: author name + relative time at the bottom.
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        story.authorName.split(' ').first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelMedium.copyWith(
                          color: AppColors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          shadows: const [
                            Shadow(
                              color: Colors.black54,
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _relativeTime(story.createdAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.white.withValues(alpha: 0.85),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          shadows: const [
                            Shadow(
                              color: Colors.black54,
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _relativeTime(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
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
        style: AppTextStyles.labelMedium.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );
  }
}
