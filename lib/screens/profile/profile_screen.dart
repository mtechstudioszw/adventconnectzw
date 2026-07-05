import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/church_model.dart';
import '../../models/post_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/auth_service.dart';
import '../../widgets/verified_tick.dart';
import '../../utils/date_format.dart';
import '../../services/cache_service.dart';
import '../../services/church_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/event_service.dart';
import '../../services/feed_service.dart';
import '../../services/gallery_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/home/comments_sheet.dart';
import '../../widgets/home/edit_post_dialog.dart';
import '../../widgets/home/invite_friends_card.dart';
import '../../widgets/home/post_card.dart';
import '../../widgets/home/post_image_viewer.dart';
import '../../widgets/full_image_viewer.dart';
import '../../widgets/last_updated_strip.dart';
import '../widgets/main_bottom_nav.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/motion/staggered_reveal.dart';
import '../../widgets/motion/hide_on_scroll.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with NavVisibilityMixin {
  int _churchesFollowed = 0;
  int _eventsGoing = 0;
  List<Post> _myPosts = const [];
  List<Church> _myChurches = const [];
  // Approved church-admin roles for this user (patch_112). Non-empty → show
  // the "Church admin dashboard" entry so it's reachable WITHOUT hunting for
  // the approval notification.
  List<ChurchAdminRole> _adminRoles = const [];
  // The viewer is a verified account (church admin or the super-admin
  // founder) — shows the gold tick on their own profile.
  bool _isVerified = false;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _loadAdminRoles();
    _loadVerified();
  }

  /// Best-effort load of the user's approved church-admin roles so the
  /// dashboard entry can appear. Silent on failure (the entry just stays
  /// hidden, exactly as for non-admins).
  Future<void> _loadAdminRoles() async {
    try {
      final roles = await ChurchService.fetchMyAdminRoles();
      if (mounted) setState(() => _adminRoles = roles);
    } catch (_) {
      // ignore — entry stays hidden.
    }
  }

  /// Whether the viewer is a verified account (church admin / super-admin
  /// founder), so we can show the gold tick on their own profile.
  Future<void> _loadVerified() async {
    final id = AuthService.currentUser?.id;
    if (id == null) return;
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('is_verified, is_verified_admin')
          .eq('id', id)
          .maybeSingle();
      final v =
          row?['is_verified'] == true || row?['is_verified_admin'] == true;
      if (mounted) setState(() => _isVerified = v);
    } catch (_) {
      // ignore — tick stays hidden.
    }
  }

  /// Open the church-admin dashboard. One role → straight in. Multiple
  /// (rare) → let the admin pick which church first.
  Future<void> _openAdminDashboard() async {
    if (_adminRoles.isEmpty) return;
    if (_adminRoles.length == 1) {
      context.pushNamed('admin_dashboard', extra: _adminRoles.first);
      return;
    }
    final picked = await showModalBottomSheet<ChurchAdminRole>(
      context: context,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Text(
              'Choose a church',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (final role in _adminRoles)
              ListTile(
                leading: const Icon(
                  Icons.church_outlined,
                  color: AppColors.primaryBlue,
                ),
                title: Text(
                  role.churchName,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'Admin · ${role.role}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: ctx.palette.textMuted,
                  ),
                ),
                onTap: () => Navigator.pop(ctx, role),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      context.pushNamed('admin_dashboard', extra: picked);
    }
  }

  Future<void> _bootstrap() async {
    _hydrateFromCache();
    final viewerId = AuthService.currentUser?.id;
    try {
      final results = await Future.wait([
        ChurchService.fetchUserFollowedChurchIds(),
        EventService.fetchUserRsvpedEventIds(),
        // Own posts newest-first (profile order), NOT the home feed's
        // personalised order.
        FeedService.fetchPostsByAuthor(AuthService.currentUser?.id ?? ''),
        ChurchService.fetchChurches(),
      ]);
      if (!mounted) return;
      final followed = results[0] as Set<String>;
      final allPosts = results[2] as List<Post>;
      final allChurches = results[3] as List<Church>;
      final myPosts = viewerId == null
          ? const <Post>[]
          : allPosts.where((p) => p.authorId == viewerId).toList();
      final myChurches = allChurches
          .where((c) => followed.contains(c.id))
          .toList();
      setState(() {
        _churchesFollowed = followed.length;
        _eventsGoing = (results[1] as Set).length;
        _myPosts = myPosts;
        _myChurches = myChurches;
      });
      unawaited(_writeCache(myPosts, myChurches));
    } catch (_) {
      // ignore — UI just keeps showing whatever it has from cache.
    }
  }

  static const _cacheKey = 'profile_self';

  void _hydrateFromCache() {
    try {
      final raw = CacheService.readString(_cacheKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final viewerId = AuthService.currentUser?.id;
      final posts = ((decoded['posts'] as List?) ?? const [])
          .map(
            (p) => Post.fromJson(p as Map<String, dynamic>, viewerId: viewerId),
          )
          .toList();
      final churches = ((decoded['churches'] as List?) ?? const [])
          .map((c) => Church.fromJson(c as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() {
        if (_myPosts.isEmpty) _myPosts = posts;
        if (_myChurches.isEmpty) _myChurches = churches;
      });
    } catch (_) {
      // ignore — corrupt cache is just a missed paint.
    }
  }

  Future<void> _writeCache(List<Post> posts, List<Church> churches) async {
    try {
      final payload = jsonEncode({
        'posts': posts.take(50).map((p) => p.toJson()).toList(),
        'churches': churches.map((c) => c.toJson()).toList(),
      });
      await CacheService.writeString(_cacheKey, payload);
    } catch (_) {}
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
    final parts = name
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
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

  /// The date this account joined, from the Supabase auth user's created_at.
  DateTime? _joinedAt() {
    final raw = AuthService.currentUser?.createdAt;
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  /// Parses the user's date of birth from metadata (stored as an ISO
  /// string at signup / age-verification). Returns null if absent or
  /// malformed.
  DateTime? _birthDate() {
    final meta = AuthService.currentUser?.userMetadata ?? const {};
    final raw = (meta['date_of_birth'] ?? meta['birth_date'])?.toString();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  /// Age in whole years, or null if no birth date / out of range.
  int? _age() {
    final dob = _birthDate();
    if (dob == null) return null;
    final now = DateTime.now();
    var age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age -= 1;
    }
    return age < 0 || age > 120 ? null : age;
  }

  /// True when today (month + day) matches the user's birthday.
  bool _isBirthdayToday() {
    final dob = _birthDate();
    if (dob == null) return false;
    final now = DateTime.now();
    return now.month == dob.month && now.day == dob.day;
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
                color: context.palette.text,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
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
      backgroundColor: context.palette.scaffoldBg,
      body: NotificationListener<UserScrollNotification>(
        onNotification: handleNavScroll,
        child: BrandedRefreshIndicator(
          color: AppColors.primaryBlue,
          onRefresh: _bootstrap,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            // Sections cascade in instead of the old one-block fade.
            child: Column(
              children: [
                StaggeredReveal(index: 0, rise: 14, child: _buildHeader()),
                StaggeredReveal(
                  index: 1,
                  child: Column(
                    children: [
                      _buildIdentity(),
                      const SizedBox(height: 10),
                      _buildInlineStats(),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                StaggeredReveal(
                  index: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildActionToolbar(),
                  ),
                ),
                const SizedBox(height: 18),
                StaggeredReveal(index: 3, child: _buildTabSelector()),
                const SizedBox(height: 12),
                StaggeredReveal(index: 4, child: _buildTabContent()),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: HideOnScroll(
        visible: navVisible,
        child: const MainBottomNav(currentIndex: 4),
      ),
    );
  }

  Widget _buildInlineStats() {
    final parts = <String>[
      '$_churchesFollowed Church${_churchesFollowed == 1 ? '' : 'es'} followed',
      '${_myPosts.length} Post${_myPosts.length == 1 ? '' : 's'}',
      // Label this "Going" so it's clearly an RSVP count, not the
      // number of events the user POSTED. The previous label
      // ("X Events") was being misread as authorship attribution
      // every time someone RSVP'd to one event and saw "1 Event".
      '$_eventsGoing Going',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        parts.join('  ·  '),
        textAlign: TextAlign.center,
        style: AppTextStyles.bodySmall.copyWith(
          color: context.palette.textMuted,
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
          decoration: BoxDecoration(
            color: context.palette.sheet,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: context.palette.divider,
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
        color: context.palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.palette.divider),
      ),
      padding: const EdgeInsets.all(5),
      child: Row(
        children: [
          _TabPill(
            label: 'Posts',
            selected: _tabIndex == 0,
            onTap: () => setState(() => _tabIndex = 0),
          ),
          const SizedBox(width: 5),
          _TabPill(
            label: 'About',
            selected: _tabIndex == 1,
            onTap: () => setState(() => _tabIndex = 1),
          ),
          const SizedBox(width: 5),
          _TabPill(
            label: 'Photos',
            selected: _tabIndex == 2,
            onTap: () => setState(() => _tabIndex = 2),
          ),
          const SizedBox(width: 5),
          _TabPill(
            label: 'Churches',
            selected: _tabIndex == 3,
            onTap: () => setState(() => _tabIndex = 3),
          ),
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
            color: context.palette.textMuted,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    final viewerId = AuthService.currentUser?.id;
    final cachedAt = CacheService.cachedAt(_cacheKey);
    return Column(
      children: [
        if (cachedAt != null) ...[
          const SizedBox(height: 4),
          LastUpdatedStrip(
            timestamp: cachedAt,
            isOnline: ConnectivityService.isOnline,
            onRefresh: _bootstrap,
          ),
          const SizedBox(height: 4),
        ],
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
    final newCount = (post.likeCount + (newLiked ? 1 : -1)).clamp(0, 1 << 30);
    setState(() {
      _myPosts = _myPosts
          .map(
            (p) => p.id == post.id
                ? p.copyWith(viewerLiked: newLiked, likeCount: newCount)
                : p,
          )
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
            .map(
              (p) => p.id == post.id
                  ? p.copyWith(
                      viewerLiked: post.viewerLiked,
                      likeCount: post.likeCount,
                    )
                  : p,
            )
            .toList();
      });
    }
  }

  Future<void> _openComments(Post post) {
    return showCommentsSheet(
      context,
      postId: post.id,
      postAuthorId: post.authorId,
      onCommentCountChanged: (newCount) {
        if (!mounted) return;
        setState(() {
          _myPosts = _myPosts
              .map(
                (p) => p.id == post.id ? p.copyWith(commentCount: newCount) : p,
              )
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
      final updated = await FeedService.updatePost(
        post.id,
        visibility: newVisibility,
      );
      if (!mounted) return;
      setState(() {
        _myPosts = _myPosts
            .map((p) => p.id == updated.id ? updated : p)
            .toList();
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
    final newBody = await showEditPostDialog(
      context,
      initialBody: post.body ?? '',
    );
    if (newBody == null) return;
    try {
      final updated = await FeedService.updatePost(post.id, body: newBody);
      if (!mounted) return;
      setState(() {
        _myPosts = _myPosts
            .map((p) => p.id == updated.id ? updated : p)
            .toList();
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
          style: AppTextStyles.titleLarge.copyWith(fontWeight: FontWeight.w700),
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
                color: context.palette.text,
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
        _buildCompletenessCard(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildBioCard(),
        ),
        if (_adminRoles.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildChurchAdminCard(),
        ],
        const SizedBox(height: 16),
        _buildAccountCard(),
        const SizedBox(height: 16),
        const InviteFriendsCard(),
      ],
    );
  }

  /// Church-admin dashboard entry (patch_112). Only shown when the user has
  /// at least one approved church-admin role, so a member who hasn't claimed
  /// a church never sees it.
  Widget _buildChurchAdminCard() {
    final multi = _adminRoles.length > 1;
    final subtitle = multi
        ? 'You manage ${_adminRoles.length} churches — post announcements, '
              'events and manage info.'
        : 'Post announcements, events and manage info for '
              '${_adminRoles.first.churchName}.';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.palette.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.verified_user_outlined,
                    color: AppColors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Church admin',
                        style: AppTextStyles.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: context.palette.textMuted,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _openAdminDashboard,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Open admin dashboard',
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
        ),
      ),
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
            color: context.palette.textMuted,
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
              child: CachedImage(post.imageUrl!, fit: BoxFit.cover),
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
            color: context.palette.textMuted,
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
                color: context.palette.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.palette.divider),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
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
                                    color: context.palette.textMuted,
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
                    ? const BoxDecoration(gradient: AppColors.appBarGradient)
                    : null,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (coverUrl != null)
                      GestureDetector(
                        onTap: () => FullImageViewer.show(context, coverUrl),
                        child: CachedImage(
                          coverUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                                decoration: const BoxDecoration(
                                  gradient: AppColors.appBarGradient,
                                ),
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
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Completeness ring — only while the profile is incomplete.
                  if (_profileCompletion() < 1.0)
                    SizedBox(
                      width: 134,
                      height: 134,
                      child: CircularProgressIndicator(
                        value: _profileCompletion(),
                        strokeWidth: 4,
                        backgroundColor: AppColors.white.withValues(
                          alpha: 0.35,
                        ),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.goldAccent,
                        ),
                      ),
                    ),
                  Container(
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
                        : GestureDetector(
                            onTap: () =>
                                FullImageViewer.show(context, photoUrl),
                            child: CachedImage(
                              photoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Text(
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
                ],
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
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  _displayName(),
                  textAlign: TextAlign.center,
                  style: AppTextStyles.headlineLarge.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_isVerified) const VerifiedTick(size: 20, leftGap: 6),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.email_outlined,
                size: 14,
                color: context.palette.textMuted,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  _email(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: context.palette.textMuted,
                  ),
                ),
              ),
            ],
          ),
          if (_joinedAt() != null) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 13,
                  color: context.palette.textMuted,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'Joined Advent Connect ZW · ${formatJoinDate(_joinedAt()!)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: context.palette.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_age() != null) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_age()} years old',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_isBirthdayToday()) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.goldAccent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '🎉 Happy Birthday!',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.goldAccent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Profile-completeness checklist. Each entry maps a friendly label to
  /// whether that field is filled in the user's metadata.
  List<MapEntry<String, bool>> _completenessItems() {
    final meta = AuthService.currentUser?.userMetadata ?? const {};
    String s(String k) => (meta[k] as String?)?.trim() ?? '';
    final church = meta['church_id'];
    return [
      MapEntry('Add a profile photo', s('profile_photo_url').isNotEmpty),
      MapEntry(
        'Set your home church',
        church != null && church.toString().isNotEmpty,
      ),
      MapEntry('Write a short bio', s('bio').isNotEmpty),
      MapEntry('Add your date of birth', _birthDate() != null),
      MapEntry('Add your full name', s('full_name').isNotEmpty),
    ];
  }

  /// Fraction (0..1) of the profile-completeness items that are done. Drives
  /// the ring around the avatar so an incomplete profile is obvious at a
  /// glance, without scrolling to the card.
  double _profileCompletion() {
    final items = _completenessItems();
    if (items.isEmpty) return 1.0;
    return items.where((i) => i.value).length / items.length;
  }

  /// A "Complete your profile" card with an animated progress bar + the
  /// remaining steps. Hides itself once the profile is 100% complete so a
  /// finished profile never sees clutter.
  Widget _buildCompletenessCard() {
    final items = _completenessItems();
    final done = items.where((i) => i.value).length;
    final total = items.length;
    if (done >= total) return const SizedBox.shrink();
    final pct = done / total;
    final missing = items.where((i) => !i.value).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () => context.pushNamed('edit_profile'),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: context.palette.card,
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
                Row(
                  children: [
                    Text(
                      'COMPLETE YOUR PROFILE',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: context.palette.textMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${(pct * 100).round()}%',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: pct),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, _) => LinearProgressIndicator(
                      value: v,
                      minHeight: 8,
                      backgroundColor: context.palette.cardMuted,
                      valueColor: const AlwaysStoppedAnimation(
                        AppColors.primaryBlue,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                ...missing
                    .take(3)
                    .map(
                      (i) => Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.radio_button_unchecked,
                              size: 16,
                              color: AppColors.primaryBlue,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                i.key,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: context.palette.text,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: context.palette.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                if (missing.length > 3)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '+ ${missing.length - 3} more',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: context.palette.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBioCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.palette.card,
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
              color: context.palette.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _bio(),
            style: AppTextStyles.bodyMedium.copyWith(
              color: context.palette.text,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard() {
    // Marketplace selling now goes through the seller flow directly —
    // no business-account indirection. This card surfaces a single CTA
    // into the seller dashboard / setup, and the dashboard handles
    // the pending / rejected / approved branching itself.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.palette.divider),
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
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.storefront,
                    color: AppColors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sell on the marketplace',
                        style: AppTextStyles.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Open a storefront in minutes — an admin reviews '
                        'your store profile once before it goes live.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: context.palette.textMuted,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => context.pushNamed('seller_dashboard'),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Open seller dashboard',
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
        ),
      ),
    );
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
    return PressEffect(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          // Frosted circle — same family as the Home header buttons so
          // back/search chips read consistently across every hero.
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.white.withValues(alpha: 0.25),
              ),
            ),
            child: Icon(icon, color: AppColors.white, size: 20),
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
    return PressEffect(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: primary ? AppColors.primaryGradient : null,
              color: primary ? null : context.palette.card,
              borderRadius: BorderRadius.circular(12),
              border: primary
                  ? null
                  : Border.all(color: context.palette.divider),
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
      child: PressEffect(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 11),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: selected ? AppColors.primaryGradient : null,
                borderRadius: BorderRadius.circular(10),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: selected ? AppColors.white : context.palette.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
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
    final color = destructive ? AppColors.red : context.palette.text;
    return PressEffect(
      child: Material(
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
      ),
    );
  }
}
