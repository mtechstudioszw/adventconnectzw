import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/friendship_model.dart';
import '../../models/church_model.dart';
import '../../models/ministry_tag_model.dart';
import '../../services/ministry_service.dart';
import '../../widgets/ministry_chips.dart';
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
import '../../widgets/friend_qr_sheet.dart';
import '../../widgets/screen_shell.dart';
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
  // Accepted friendships only — the stat strip shows "Friends", and a
  // count that included pending requests would overstate it.
  int _friendCount = 0;
  List<Post> _myPosts = const [];
  List<Church> _myChurches = const [];
  // Approved church-admin roles for this user (patch_112). Non-empty → show
  // the "Church admin dashboard" entry so it's reachable WITHOUT hunting for
  // the approval notification.
  List<ChurchAdminRole> _adminRoles = const [];
  // Ministry involvement + spiritual gifts (patch_168).
  List<MinistryTag> _myTags = const [];
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
    _loadMinistryTags();
  }

  Future<void> _loadMinistryTags() async {
    final id = AuthService.currentUser?.id;
    if (id == null) return;
    try {
      final tags = await MinistryService.fetchForProfile(id);
      if (mounted) setState(() => _myTags = tags);
    } catch (_) {
      // ignore — the section falls back to its "add" affordance.
    }
  }

  Future<void> _editMinistryTags() async {
    final saved = await showMinistryPicker(
      context,
      selected: _myTags.map((t) => t.id).toSet(),
    );
    // Null means dismissed without saving — leave what we have.
    if (saved == null || !mounted) return;
    // The sheet already wrote to the server; re-read so the chips render
    // in the vocabulary's sort order rather than tap order.
    await _loadMinistryTags();
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
        FeedService.fetchMyFriendships(),
      ]);
      if (!mounted) return;
      final followed = results[0] as Set<String>;
      final allPosts = results[2] as List<Post>;
      final allChurches = results[3] as List<Church>;
      final friends =
          (results[4] as List<Friendship>).where((f) => f.isAccepted).length;
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
        _friendCount = friends;
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

  /// The initials glyph for the big profile avatar. One builder for both
  /// the "no photo" and the "photo failed" paths so they can't drift.
  Widget _avatarInitials() => Text(
        _initials(),
        textAlign: TextAlign.center,
        style: AppTextStyles.displayMedium.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w700,
          fontSize: 38,
        ),
      );

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
                // Ministry & gifts (patch_168) — what you serve in and
                // what you bring. Sits above the tabs because it is
                // identity, not one of several views of your content.
                StaggeredReveal(
                  index: 3,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                    child: MinistrySection(
                      tags: _myTags,
                      isOwn: true,
                      onEdit: _editMinistryTags,
                    ),
                  ),
                ),
                StaggeredReveal(index: 4, child: _buildTabSelector()),
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

  /// Three-up stat strip. Replaces the old run-on sentence of counts —
  /// numbers set as numbers are scannable, and each cell is a tap target
  /// rather than decoration.
  ///
  /// Every figure here is real: friends and posts are counted from loaded
  /// data, churches from the followed set. "Prayers" is deliberately
  /// absent — nothing in this screen's data tells us how many prayers the
  /// user has posted, and a fabricated stat is worse than a missing one.
  Widget _buildInlineStats() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ScreenCard(
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            _StatCell(
              value: _friendCount,
              label: 'Friends',
              onTap: () => context.pushNamed('friends'),
            ),
            _StatDivider(),
            _StatCell(
              value: _myPosts.length,
              label: _myPosts.length == 1 ? 'Post' : 'Posts',
              onTap: () => setState(() => _tabIndex = 0),
            ),
            _StatDivider(),
            _StatCell(
              value: _churchesFollowed,
              label: _churchesFollowed == 1 ? 'Church' : 'Churches',
              onTap: () => setState(() => _tabIndex = 3),
            ),
            _StatDivider(),
            // Kept from the old strip: "Going" reads as an RSVP count,
            // which is what it is. "Events" was being misread as
            // authorship every time someone RSVP'd to one event.
            _StatCell(
              value: _eventsGoing,
              label: 'Going',
              onTap: () => context.pushNamed('events'),
            ),
          ],
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
            onImageTapped: (index) async {
              // Multi-photo posts hand back the tapped index; this screen
              // still opens the first photo full-screen.
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
                ? p.copyWith(
                    viewerReaction: newLiked ? PostReaction.like : null,
                    likeCount: newCount,
                  )
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
                      viewerReaction: post.viewerReaction,
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
    // The completeness card hides itself at 100%, so the gap after it has
    // to be conditional — a fixed SizedBox would leave a hole on a
    // finished profile. Without it the card sat flush against the About
    // card below, the only pair on the tab with no space between them.
    final showCompleteness =
        _completenessItems().any((i) => !i.value);
    return Column(
      children: [
        if (showCompleteness) ...[
          _buildCompletenessCard(),
          const SizedBox(height: 16),
        ],
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

  /// Flat header + optional cover band + avatar.
  ///
  /// The navy slab is gone (founder rule, 28 Jul 2026). What replaces it
  /// depends on whether there IS a cover photo:
  ///   - cover set   → an inset, rounded photo band under the flat header
  ///   - no cover    → nothing. The header simply sits on scaffoldBg and
  ///                   the identity card moves up. A missing photo is not
  ///                   a reason to paint a navy rectangle.
  ///
  /// Note the header is a `Container`, not a childless `DecoratedBox` —
  /// that collapses to zero height and paints nothing, which is exactly
  /// how the Watch header's gradient vanished.
  Widget _buildHeader() {
    final coverUrl = _coverPhotoUrl();
    final hasCover = coverUrl != null;
    return FlatStatusBar(
      child: Container(
        color: context.palette.scaffoldBg,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                child: Row(
                  children: [
                    Text(
                      'Profile',
                      style: AppTextStyles.displayMedium.copyWith(
                        color: context.palette.text,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    // Friend QR — Adventists meet in person, and scanning
                    // beats spelling a name into a search box in a noisy
                    // hall at camp meeting.
                    HeaderIconButton(
                      icon: Icons.qr_code_2,
                      tooltip: 'Your friend code',
                      onTap: () => showFriendQrSheet(context),
                    ),
                    const SizedBox(width: 8),
                    HeaderIconButton(
                      icon: Icons.settings_outlined,
                      tooltip: 'Settings',
                      onTap: () => context.pushNamed('settings'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Cover + avatar. When there's no cover the stack is just
              // the avatar, so the height collapses to the avatar itself.
              SizedBox(
                height: hasCover ? 190 : 124,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    if (hasCover)
                      Positioned(
                        top: 0,
                        left: 16,
                        right: 16,
                        height: 132,
                        child: GestureDetector(
                          onTap: () => FullImageViewer.show(context, coverUrl),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: CachedImage(
                              coverUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    color: context.palette.cardMuted,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(bottom: 0, child: _buildAvatar()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final photoUrl = _profilePhotoUrl();
    return Stack(
      alignment: Alignment.center,
      children: [
        // Completeness ring — only while the profile is incomplete. Gold
        // on the scaffold rather than on navy, so the track needs a
        // visible-on-light backing.
        if (_profileCompletion() < 1.0)
          SizedBox(
            width: 132,
            height: 132,
            child: CircularProgressIndicator(
              value: _profileCompletion(),
              strokeWidth: 4,
              backgroundColor: context.palette.divider,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.goldAccent,
              ),
            ),
          ),
        Container(
          width: 118,
          height: 118,
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: photoUrl == null ? AppColors.primaryGradient : null,
            color: photoUrl == null ? null : context.palette.cardMuted,
            shape: BoxShape.circle,
            border: Border.all(color: context.palette.scaffoldBg, width: 5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: photoUrl == null
              // No photo is itself an incomplete profile, so the tap
              // always goes to the editor here.
              ? GestureDetector(
                  onTap: () => context.pushNamed('edit_profile'),
                  child: Center(child: _avatarInitials()),
                )
              : GestureDetector(
                  // The avatar wears the completeness ring, so tapping it
                  // acts on that ring: an unfinished profile opens the
                  // editor to finish it, a finished one opens the photo.
                  onTap: () => _profileCompletion() < 1.0
                      ? context.pushNamed('edit_profile')
                      : FullImageViewer.show(context, photoUrl),
                  // Explicitly sized. The parent Container sets
                  // `alignment: Alignment.center`, which hands its child
                  // LOOSE constraints — so an unsized CachedImage laid
                  // itself out at the photo's own size and sat centred
                  // inside the circle, leaving a ring of card colour
                  // around it. That ring is the "white edges". With the
                  // box pinned to the circle, BoxFit.cover fills it.
                  child: CachedImage(
                    photoUrl,
                    fit: BoxFit.cover,
                    width: 118,
                    height: 118,
                    // Centred, because the error widget is handed TIGHT
                    // constraints of the image box and a bare Text then
                    // paints at the top-left of it — which is why the
                    // initial sat at the top of the circle whenever the
                    // photo failed to load (i.e. offline).
                    errorBuilder: (context, error, stackTrace) =>
                        Center(child: _avatarInitials()),
                  ),
                ),
        ),
      ],
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

/// One cell of the profile stat strip — a number set as a number, with
/// its label beneath. [onTap] is null where no destination exists, and
/// the cell then renders identically but inert.
class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label, this.onTap});

  final int value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
            child: Column(
              children: [
                Text(
                  '$value',
                  style: AppTextStyles.headlineMedium.copyWith(
                    color: context.palette.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 19,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: context.palette.textMuted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
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

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 30,
      color: context.palette.divider,
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
