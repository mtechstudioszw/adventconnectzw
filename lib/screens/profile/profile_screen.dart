import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/business_application_model.dart';
import '../../models/church_model.dart';
import '../../models/post_model.dart';
import '../../services/account_mode_service.dart';
import '../../services/account_service.dart';
import '../../services/auth_service.dart';
import '../../services/church_service.dart';
import '../../services/event_service.dart';
import '../../services/feed_service.dart';
import '../../services/gallery_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/home/comments_sheet.dart';
import '../../widgets/home/edit_post_dialog.dart';
import '../../widgets/home/invite_friends_card.dart';
import '../../widgets/home/post_card.dart';
import '../../widgets/home/post_image_viewer.dart';
import '../widgets/main_bottom_nav.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  int _churchesFollowed = 0;
  int _eventsGoing = 0;
  AccountState? _accountState;
  List<Post> _myPosts = const [];
  List<Church> _myChurches = const [];
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slide = Tween<double>(begin: 12, end: 0).animate(
      CurvedAnimation(parent: _entrance, curve: Curves.easeOut),
    );
    _bootstrap();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final viewerId = AuthService.currentUser?.id;
    try {
      final results = await Future.wait([
        ChurchService.fetchUserFollowedChurchIds(),
        EventService.fetchUserRsvpedEventIds(),
        AccountService.fetchMyAccount(),
        FeedService.fetchFeed(limit: 120),
        ChurchService.fetchChurches(),
      ]);
      if (!mounted) return;
      final followed = results[0] as Set<String>;
      final allPosts = results[3] as List<Post>;
      final allChurches = results[4] as List<Church>;
      setState(() {
        _churchesFollowed = followed.length;
        _eventsGoing = (results[1] as Set).length;
        _accountState = results[2] as AccountState?;
        _myPosts = viewerId == null
            ? const []
            : allPosts.where((p) => p.authorId == viewerId).toList();
        _myChurches = allChurches
            .where((c) => followed.contains(c.id))
            .toList();
      });
    } catch (_) {
      // ignore — UI just keeps showing whatever it has.
    }
  }

  Future<void> _openApplyBusiness() async {
    final result = await context.pushNamed<BusinessApplication>(
      'apply_business',
    );
    if (!mounted || result == null) return;
    // After a fresh application the latest row is `pending` — refresh
    // local state so the badge updates without a manual reload.
    setState(() {
      _accountState = AccountState(
        userId: _accountState?.userId ?? '',
        isBusiness: _accountState?.isBusiness ?? false,
        latestApplication: result,
      );
    });
  }

  String _displayName() {
    final user = AuthService.currentUser;
    final meta = user?.userMetadata ?? const {};
    final name = (meta['full_name'] as String?)?.trim() ?? '';
    if (name.isNotEmpty) return name;
    return user?.email ?? 'Welcome';
  }

  String _initials() {
    final name = _displayName();
    final parts =
        name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  String _bio() {
    final user = AuthService.currentUser;
    final meta = user?.userMetadata ?? const {};
    final bio = (meta['bio'] as String?)?.trim() ?? '';
    if (bio.isNotEmpty) return bio;
    return 'Add a bio to tell the community about yourself.';
  }

  String _email() {
    return AuthService.currentUser?.email ?? '';
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sign out?', style: AppTextStyles.headlineSmall),
        content: Text(
          'You\'ll need to sign in again to access the community.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: AppTextStyles.labelMedium.copyWith(
                color: AppColors.textDark,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.red,
            ),
            child: Text('Sign out', style: AppTextStyles.labelLarge),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await AuthService.signOut();
    if (!mounted) return;
    // After sign-out land on the unified auth screen. The standalone
    // age-verification screen is no longer in the first-run flow.
    context.goNamed('login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGrey,
      body: RefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: _bootstrap,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: AnimatedBuilder(
            animation: _entrance,
            builder: (context, child) => Opacity(
              opacity: _fade.value,
              child: Transform.translate(
                offset: Offset(0, _slide.value),
                child: child,
              ),
            ),
            child: Column(
              children: [
                _buildHeader(),
                _buildIdentity(),
                const SizedBox(height: 10),
                _buildInlineStats(),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildActionToolbar(),
                ),
                const SizedBox(height: 18),
                _buildTabSelector(),
                const SizedBox(height: 12),
                _buildTabContent(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: const MainBottomNav(currentIndex: 4),
    );
  }

  Widget _buildInlineStats() {
    final parts = <String>[
      '$_churchesFollowed Church${_churchesFollowed == 1 ? '' : 'es'} followed',
      '${_myPosts.length} Post${_myPosts.length == 1 ? '' : 's'}',
      '$_eventsGoing Event${_eventsGoing == 1 ? '' : 's'}',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        parts.join('  ·  '),
        textAlign: TextAlign.center,
        style: AppTextStyles.bodySmall.copyWith(
          color: const Color.fromRGBO(26, 26, 46, 0.6),
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildActionToolbar() {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: _ToolbarButton(
            icon: Icons.edit_outlined,
            label: 'Edit profile',
            primary: true,
            onTap: () => context.pushNamed('edit_profile'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 1,
          child: _ToolbarButton(
            icon: Icons.more_horiz,
            label: '',
            primary: false,
            onTap: _openMoreMenu,
          ),
        ),
      ],
    );
  }

  Future<void> _openMoreMenu() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(26, 26, 46, 0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              _MoreMenuRow(
                icon: Icons.settings_outlined,
                label: 'Settings',
                onTap: () => Navigator.pop(ctx, 'settings'),
              ),
              _MoreMenuRow(
                icon: Icons.notifications_outlined,
                label: 'Notifications',
                onTap: () => Navigator.pop(ctx, 'notifications'),
              ),
              _MoreMenuRow(
                icon: Icons.feedback_outlined,
                label: 'Send feedback',
                onTap: () => Navigator.pop(ctx, 'feedback'),
              ),
              _MoreMenuRow(
                icon: Icons.brightness_3_outlined,
                label: 'Sabbath timer',
                onTap: () => Navigator.pop(ctx, 'sabbath_timer'),
              ),
              _MoreMenuRow(
                icon: Icons.logout,
                label: 'Sign out',
                destructive: true,
                onTap: () => Navigator.pop(ctx, 'sign_out'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || result == null) return;
    switch (result) {
      case 'settings':
        context.pushNamed('settings');
        break;
      case 'notifications':
        context.pushNamed('notification_preferences');
        break;
      case 'feedback':
        context.pushNamed('feedback');
        break;
      case 'sabbath_timer':
        context.pushNamed('sabbath_timer');
        break;
      case 'sign_out':
        await _signOut();
        break;
    }
  }

  Widget _buildTabSelector() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color.fromRGBO(26, 26, 46, 0.06)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _TabPill(label: 'Posts', selected: _tabIndex == 0, onTap: () => setState(() => _tabIndex = 0)),
          _TabPill(label: 'About', selected: _tabIndex == 1, onTap: () => setState(() => _tabIndex = 1)),
          _TabPill(label: 'Photos', selected: _tabIndex == 2, onTap: () => setState(() => _tabIndex = 2)),
          _TabPill(label: 'Churches', selected: _tabIndex == 3, onTap: () => setState(() => _tabIndex = 3)),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_tabIndex) {
      case 0:
        return _buildPostsTab();
      case 1:
        return _buildAboutTab();
      case 2:
        return _buildPhotosTab();
      case 3:
        return _buildChurchesTab();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildPostsTab() {
    if (_myPosts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Text(
          'You haven\'t posted anything yet.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySmall.copyWith(
            color: const Color.fromRGBO(26, 26, 46, 0.55),
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    final viewerId = AuthService.currentUser?.id;
    return Column(
      children: [
        for (final post in _myPosts)
          PostCard(
            post: post,
            viewerId: viewerId,
            onLikeToggled: () => _toggleLike(post),
            onCommentsTapped: () => _openComments(post),
            onImageTapped: () async {
              final url = post.imageUrl;
              if (url == null || url.isEmpty) return;
              await PostImageViewer.show(
                context,
                imageUrl: url,
                heroTag: 'post_image_${post.id}',
              );
            },
            onEdit: () => _editPost(post),
            onDelete: () => _confirmDeletePost(post),
            onToggleVisibility: () => _togglePostVisibility(post),
            onSaveImage: () => _savePostImage(post),
          ),
      ],
    );
  }

  Future<void> _toggleLike(Post post) async {
    final newLiked = !post.viewerLiked;
    final newCount =
        (post.likeCount + (newLiked ? 1 : -1)).clamp(0, 1 << 30);
    setState(() {
      _myPosts = _myPosts
          .map((p) => p.id == post.id
              ? p.copyWith(viewerLiked: newLiked, likeCount: newCount)
              : p)
          .toList();
    });
    try {
      if (newLiked) {
        await FeedService.likePost(post.id);
      } else {
        await FeedService.unlikePost(post.id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _myPosts = _myPosts
            .map((p) => p.id == post.id
                ? p.copyWith(
                    viewerLiked: post.viewerLiked,
                    likeCount: post.likeCount,
                  )
                : p)
            .toList();
      });
    }
  }

  Future<void> _openComments(Post post) {
    return showCommentsSheet(
      context,
      postId: post.id,
      onCommentCountChanged: (newCount) {
        if (!mounted) return;
        setState(() {
          _myPosts = _myPosts
              .map((p) =>
                  p.id == post.id ? p.copyWith(commentCount: newCount) : p)
              .toList();
        });
      },
    );
  }

  Future<void> _savePostImage(Post post) async {
    final url = post.imageUrl;
    if (url == null || url.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: AppColors.darkNavy,
        duration: const Duration(seconds: 2),
        content: Text(
          'Saving image to gallery…',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        ),
      ),
    );
    final ok = await GalleryService.saveImageFromUrl(url);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: ok ? AppColors.successGreen : AppColors.red,
        content: Text(
          ok
              ? 'Saved to your Advent Connect album.'
              : 'Could not save the image. Check storage permission and try again.',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        ),
      ),
    );
  }

  Future<void> _togglePostVisibility(Post post) async {
    final newVisibility = post.visibility == PostVisibility.public
        ? PostVisibility.friendsOnly
        : PostVisibility.public;
    try {
      final updated =
          await FeedService.updatePost(post.id, visibility: newVisibility);
      if (!mounted) return;
      setState(() {
        _myPosts =
            _myPosts.map((p) => p.id == updated.id ? updated : p).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newVisibility == PostVisibility.public
                ? 'Post is now public.'
                : 'Post is now visible to friends only.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not update post. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  Future<void> _editPost(Post post) async {
    final newBody =
        await showEditPostDialog(context, initialBody: post.body ?? '');
    if (newBody == null) return;
    try {
      final updated = await FeedService.updatePost(post.id, body: newBody);
      if (!mounted) return;
      setState(() {
        _myPosts =
            _myPosts.map((p) => p.id == updated.id ? updated : p).toList();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not save changes.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  Future<void> _confirmDeletePost(Post post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Delete post?',
          style:
              AppTextStyles.titleLarge.copyWith(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This will remove the post for everyone. You can\'t undo it.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: AppTextStyles.buttonText.copyWith(
                color: AppColors.textDark,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FeedService.deletePost(post.id);
      if (!mounted) return;
      setState(() {
        _myPosts = _myPosts.where((p) => p.id != post.id).toList();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not delete post. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  Widget _buildAboutTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildBioCard(),
        ),
        const SizedBox(height: 16),
        _buildAccountCard(),
        const SizedBox(height: 16),
        const InviteFriendsCard(),
      ],
    );
  }

  Widget _buildPhotosTab() {
    final withImages = _myPosts
        .where((p) => (p.imageUrl ?? '').isNotEmpty)
        .toList();
    if (withImages.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Text(
          'No photos yet — posts with images will show up here.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySmall.copyWith(
            color: const Color.fromRGBO(26, 26, 46, 0.55),
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: withImages.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemBuilder: (_, i) {
          final post = withImages[i];
          return GestureDetector(
            onTap: () => PostImageViewer.show(
              context,
              imageUrl: post.imageUrl!,
              heroTag: 'post_image_${post.id}',
            ),
            child: Hero(
              tag: 'post_image_${post.id}',
              child: Image.network(post.imageUrl!, fit: BoxFit.cover),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChurchesTab() {
    if (_myChurches.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Text(
          'You haven\'t followed any churches yet.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySmall.copyWith(
            color: const Color.fromRGBO(26, 26, 46, 0.55),
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (final church in _myChurches)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color.fromRGBO(26, 26, 46, 0.06),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => context.pushNamed(
                    'church_details',
                    pathParameters: {'id': church.id},
                    extra: church,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.church,
                            color: AppColors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                church.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.titleMedium.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              if (church.city.isNotEmpty)
                                Text(
                                  church.city,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: const Color.fromRGBO(26, 26, 46, 0.6),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          color: AppColors.primaryBlue,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String? _coverPhotoUrl() {
    final user = AuthService.currentUser;
    final meta = user?.userMetadata ?? const {};
    final raw = (meta['cover_photo_url'] as String?)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  String? _profilePhotoUrl() {
    final user = AuthService.currentUser;
    final meta = user?.userMetadata ?? const {};
    final raw = (meta['profile_photo_url'] as String?)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  Widget _buildHeader() {
    final coverUrl = _coverPhotoUrl();
    final photoUrl = _profilePhotoUrl();
    return SizedBox(
      height: 220,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 180,
            child: ClipPath(
              clipper: _CoverClipper(),
              child: Container(
                decoration: coverUrl == null
                    ? const BoxDecoration(
                        gradient: AppColors.appBarGradient,
                      )
                    : null,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (coverUrl != null)
                      Image.network(
                        coverUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          decoration: const BoxDecoration(
                            gradient: AppColors.appBarGradient,
                          ),
                        ),
                      ),
                    // Always darken slightly so the white app-bar text
                    // stays legible over busy photos.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(
                                  alpha: coverUrl == null ? 0.0 : 0.25,
                                ),
                                Colors.black.withValues(
                                  alpha: coverUrl == null ? 0.0 : 0.35,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                        child: Row(
                          children: [
                            Text(
                              'Profile',
                              style: AppTextStyles.appBarTitle.copyWith(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            _CircleIconButton(
                              icon: Icons.settings_outlined,
                              onTap: () => context.pushNamed('settings'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Center(
              child: Container(
                width: 120,
                height: 120,
                clipBehavior: Clip.antiAlias,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: photoUrl == null
                      ? AppColors.primaryGradient
                      : null,
                  color: photoUrl == null ? null : AppColors.lightGrey,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.white, width: 5),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.30),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: photoUrl == null
                    ? Text(
                        _initials(),
                        style: AppTextStyles.displayMedium.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 38,
                        ),
                      )
                    : Image.network(
                        photoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Text(
                          _initials(),
                          style: AppTextStyles.displayMedium.copyWith(
                            color: AppColors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 38,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentity() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        children: [
          Text(
            _displayName(),
            textAlign: TextAlign.center,
            style: AppTextStyles.headlineLarge.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.email_outlined,
                size: 14,
                color: Color.fromRGBO(26, 26, 46, 0.55),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  _email(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: const Color.fromRGBO(26, 26, 46, 0.6),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBioCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ABOUT',
            style: AppTextStyles.labelSmall.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.5),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _bio(),
            style: AppTextStyles.bodyMedium.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.85),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard() {
    final state = _accountState;
    final isBusiness = state?.isBusiness ?? false;
    final latest = state?.latestApplication;
    final pending = latest != null && latest.isPending;
    final rejected = !isBusiness && latest != null && latest.isRejected;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color.fromRGBO(26, 26, 46, 0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: isBusiness
                        ? AppColors.primaryGradient
                        : null,
                    color: isBusiness
                        ? null
                        : AppColors.lightGrey,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isBusiness ? Icons.business_center : Icons.person,
                    color: isBusiness
                        ? AppColors.white
                        : AppColors.primaryBlue,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            isBusiness
                                ? 'Business account'
                                : 'Personal account',
                            style: AppTextStyles.titleMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                            ),
                          ),
                          if (isBusiness) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.verified,
                              color: AppColors.goldAccent,
                              size: 16,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _accountSubtitle(isBusiness, pending, rejected),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: const Color.fromRGBO(26, 26, 46, 0.6),
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (isBusiness) ...[
              const SizedBox(height: 14),
              ValueListenableBuilder<AppViewMode>(
                valueListenable: AccountModeService.notifier,
                builder: (ctx, mode, _) => _ModeSwitch(
                  mode: mode,
                  onChanged: (newMode) async {
                    await AccountModeService.setMode(newMode);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: AppColors.primaryBlue,
                        content: Text(
                          newMode == AppViewMode.business
                              ? 'Switched to Business view.'
                              : 'Switched to Personal view. Business actions are hidden until you switch back.',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.white,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (!isBusiness && !pending) ...[
              const SizedBox(height: 14),
              _ApplyBusinessButton(
                rejected: rejected,
                rejectionNote: rejected ? latest.reviewerNote : null,
                onTap: _openApplyBusiness,
              ),
            ],
            if (pending) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.goldAccent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.goldAccent.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.hourglass_empty_rounded,
                      color: AppColors.goldAccent,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your business application is under review.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.goldAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _accountSubtitle(bool isBusiness, bool pending, bool rejected) {
    if (isBusiness) {
      return 'You can sell in the marketplace and claim a church listing.';
    }
    if (pending) {
      return 'We\'ll let you know in the app once your account is upgraded.';
    }
    if (rejected) {
      return 'Your last application was declined. You can re-apply below.';
    }
    return 'Upgrade to a business account to sell or claim a church.';
  }

}

class _CoverClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 28);
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width,
      size.height - 28,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.white.withValues(alpha: 0.10)),
          ),
          child: Icon(icon, color: AppColors.white, size: 22),
        ),
      ),
    );
  }
}

class _ApplyBusinessButton extends StatelessWidget {
  const _ApplyBusinessButton({
    required this.rejected,
    required this.rejectionNote,
    required this.onTap,
  });

  final bool rejected;
  final String? rejectionNote;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rejected && (rejectionNote ?? "").isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.red.withValues(alpha: 0.30)),
            ),
            child: Text(
              rejectionNote!,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.red,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                rejected ? "Re-apply for Business" : "Apply for Business",
                style: AppTextStyles.buttonText.copyWith(
                  color: AppColors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.mode, required this.onChanged});

  final AppViewMode mode;
  final ValueChanged<AppViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color.fromRGBO(26, 26, 46, 0.06)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeSegment(
              label: 'Personal',
              icon: Icons.person,
              selected: mode == AppViewMode.personal,
              onTap: () => onChanged(AppViewMode.personal),
            ),
          ),
          Expanded(
            child: _ModeSegment(
              label: 'Business',
              icon: Icons.business_center,
              selected: mode == AppViewMode.business,
              onTap: () => onChanged(AppViewMode.business),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeSegment extends StatelessWidget {
  const _ModeSegment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
          decoration: BoxDecoration(
            gradient: selected ? AppColors.primaryGradient : null,
            color: selected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.30),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? AppColors.white : AppColors.primaryBlue,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTextStyles.labelMedium.copyWith(
                  color: selected ? AppColors.white : AppColors.primaryBlue,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.primary,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: primary ? AppColors.primaryGradient : null,
            color: primary ? null : AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: primary
                ? null
                : Border.all(color: const Color.fromRGBO(26, 26, 46, 0.10)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: primary ? 16 : 20,
                color: primary ? AppColors.white : AppColors.primaryBlue,
              ),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  label,
                  style: AppTextStyles.buttonText.copyWith(
                    color: primary ? AppColors.white : AppColors.primaryBlue,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: selected ? AppColors.primaryGradient : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              style: AppTextStyles.labelMedium.copyWith(
                color: selected ? AppColors.white : AppColors.textDark,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MoreMenuRow extends StatelessWidget {
  const _MoreMenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.red : AppColors.textDark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 14),
              Text(
                label,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
