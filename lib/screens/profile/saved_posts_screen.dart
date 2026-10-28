import 'package:flutter/material.dart';

import '../../models/post_model.dart';
import '../../services/auth_service.dart';
import '../../services/feed_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/home/comments_sheet.dart';
import '../../widgets/home/post_card.dart';
import '../../widgets/home/post_image_viewer.dart';
import '../../widgets/home/report_sheet.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/screen_shell.dart';

/// The member's private collection of saved posts (patch_273), opened from
/// Profile → ⋯ → Saved.
///
/// Uses the same post card as everywhere else, so liking, commenting and
/// the ⋯ menu behave the same here. Removing a post from Saved (from its
/// menu) takes it off this list at once.
class SavedPostsScreen extends StatefulWidget {
  const SavedPostsScreen({super.key});

  @override
  State<SavedPostsScreen> createState() => _SavedPostsScreenState();
}

class _SavedPostsScreenState extends State<SavedPostsScreen> {
  List<Post> _posts = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    FeedService.savedPostIds.addListener(_onSavedChanged);
    _load();
  }

  @override
  void dispose() {
    FeedService.savedPostIds.removeListener(_onSavedChanged);
    super.dispose();
  }

  /// Unsaving from a card's menu removes it here straight away.
  void _onSavedChanged() {
    if (!mounted) return;
    final saved = FeedService.savedPostIds.value;
    setState(() {
      _posts = _posts.where((p) => saved.contains(p.id)).toList();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await FeedService.loadSavedAndHidden();
      final posts = await FeedService.fetchSavedPosts();
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = FeedService.savedPostsAvailable
            ? 'Could not load your saved posts. Pull down to try again.'
            : 'Saved posts need a database update (patch_273) before they '
                  'can be used.';
      });
    }
  }

  Future<void> _toggleLike(Post post) async {
    final liked = !post.viewerLiked;
    void apply(Post p) => setState(() {
      _posts = [for (final x in _posts) x.id == p.id ? p : x];
    });
    apply(
      post.copyWith(
        viewerReaction: liked ? PostReaction.like : null,
        likeCount: (post.likeCount + (liked ? 1 : -1)).clamp(0, 1 << 30),
      ),
    );
    try {
      if (liked) {
        await FeedService.likePost(post.id);
      } else {
        await FeedService.unlikePost(post.id);
      }
    } catch (_) {
      if (mounted) apply(post);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final viewerId = AuthService.currentUser?.id;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BrandedRefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const ScreenHero(
              title: 'Saved posts',
              tagline: 'PROFILE',
              fallbackRoute: 'profile',
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: BrandSpinner(size: 30)),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: EmptyStateCard(
                  icon: Icons.bookmark_border_rounded,
                  title: "Can't show Saved",
                  message: _error!,
                ),
              )
            else if (_posts.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: EmptyStateCard(
                  icon: Icons.bookmark_border_rounded,
                  title: 'Nothing saved yet',
                  message:
                      'Tap ⋯ on any post and choose "Save post" to keep it '
                      'here. Only you can see what you save.',
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Only you can see your saved posts.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              ),
              for (final post in _posts)
                PostCard(
                  post: post,
                  viewerId: viewerId,
                  onLikeToggled: () => _toggleLike(post),
                  onCommentsTapped: () => showCommentsSheet(
                    context,
                    postId: post.id,
                    postAuthorId: post.authorId,
                    onCommentCountChanged: (n) => setState(() {
                      _posts = [
                        for (final x in _posts)
                          x.id == post.id ? x.copyWith(commentCount: n) : x,
                      ];
                    }),
                  ),
                  onImageTapped: (i) {
                    final images = post.imageUrls;
                    if (images.isEmpty) return;
                    final safe = i.clamp(0, images.length - 1);
                    PostImageViewer.show(
                      context,
                      imageUrl: images[safe],
                      heroTag: 'saved_${post.id}_$safe',
                    );
                  },
                  onReport: () => showReportSheet(
                    context,
                    contentType: 'post',
                    contentId: post.id,
                    contentLabel: 'this post',
                  ),
                ),
              const SizedBox(height: 32),
            ],
          ],
        ),
      ),
    );
  }
}
