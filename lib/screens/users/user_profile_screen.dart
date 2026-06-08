import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/friendship_model.dart';
import '../../models/post_model.dart';
import '../../services/auth_service.dart';
import '../../services/feed_service.dart';
import '../../services/user_profile_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/home/comments_sheet.dart';
import '../../widgets/home/post_card.dart';
import '../../widgets/home/post_image_viewer.dart';
import '../../widgets/full_image_viewer.dart';
import '../../widgets/home/report_sheet.dart';
import '../../services/messaging_service.dart';
import '../../widgets/cached_image.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Viewing another user's profile (not the logged-in user — that's the
/// regular ProfileScreen). Surfaces:
///   - cover + avatar + name + age
///   - friendship action (Add / Pending / Accept / Friends)
///   - Message button → opens a chat
///   - For non-private profiles: bio, location, recent posts grid
///   - For private profiles (is_discoverable=false): name + age only
class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  PublicUserProfile? _profile;
  Friendship? _friendship;
  List<Post> _posts = const [];
  bool _loading = true;
  bool _friendBusy = false;
  String? _error;

  String? get _viewerId => AuthService.currentUser?.id;
  bool get _isSelf => _viewerId == widget.userId;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final results = await Future.wait([
        UserProfileService.fetch(widget.userId),
        FeedService.fetchMyFriendships(),
      ]);
      if (!mounted) return;
      final profile = results[0] as PublicUserProfile?;
      final friendships = results[1] as List<Friendship>;
      Friendship? f;
      for (final candidate in friendships) {
        if (candidate.involves(widget.userId)) {
          f = candidate;
          break;
        }
      }
      setState(() {
        _profile = profile;
        _friendship = f;
        _loading = false;
        _error = profile == null ? 'Profile not found.' : null;
      });

      // Posts load is best-effort — RLS already filters friends-only
      // posts so we can issue the same query for everyone.
      if (profile != null && profile.isDiscoverable) {
        _loadPosts();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load this profile.';
      });
    }
  }

  Future<void> _loadPosts() async {
    try {
      final all = await FeedService.fetchFeed(limit: 120);
      if (!mounted) return;
      setState(() {
        _posts = all.where((p) => p.authorId == widget.userId).toList();
      });
    } catch (_) {
      // ignore — empty posts state is fine.
    }
  }

  Future<void> _addFriend() async {
    setState(() => _friendBusy = true);
    try {
      final created = await FeedService.sendRequest(widget.userId);
      if (!mounted) return;
      setState(() {
        _friendship = created;
        _friendBusy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _friendBusy = false);
      _showError('Could not send friend request.');
    }
  }

  Future<void> _cancelOrUnfriend() async {
    final f = _friendship;
    if (f == null) return;
    final wasAccepted = f.isAccepted;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          wasAccepted ? 'Unfriend?' : 'Cancel friend request?',
          style:
              AppTextStyles.titleLarge.copyWith(fontWeight: FontWeight.w700),
        ),
        content: Text(
          wasAccepted
              ? 'You\'ll no longer see each other\'s friends-only posts.'
              : 'The pending request to ${_profile?.fullName ?? "this member"} will be withdrawn.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Keep',
              style: AppTextStyles.buttonText.copyWith(
                color: ctx.palette.text,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: Text(wasAccepted ? 'Unfriend' : 'Cancel request'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _friendBusy = true);
    try {
      await FeedService.removeFriendship(f.id);
      if (!mounted) return;
      setState(() {
        _friendship = null;
        _friendBusy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _friendBusy = false);
      _showError('Could not update friendship.');
    }
  }

  Future<void> _acceptIncoming() async {
    final f = _friendship;
    if (f == null) return;
    setState(() => _friendBusy = true);
    try {
      await FeedService.acceptRequest(f.id);
      if (!mounted) return;
      setState(() {
        _friendship = Friendship(
          id: f.id,
          requesterId: f.requesterId,
          addresseeId: f.addresseeId,
          status: FriendshipStatus.accepted,
          createdAt: f.createdAt,
        );
        _friendBusy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _friendBusy = false);
      _showError('Could not accept request.');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.red,
        content: Text(
          msg,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        ),
      ),
    );
  }

  Future<void> _openChat() async {
    final profile = _profile;
    if (profile == null) return;
    // WhatsApp behaviour: tap the contact, land directly inside an
    // empty chat with them — no "Hi {name} 👋" auto-message, no
    // confirmation sheet. The user types their own opener.
    try {
      final convo = await MessagingService.createConversation(
        otherUserId: widget.userId,
        otherUserName: profile.fullName,
        source: 'direct',
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      context.pushNamed(
        'chat',
        pathParameters: {'id': convo.id},
        extra: convo,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not open chat. Please try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  Future<void> _reportUser() async {
    final sent = await showReportSheet(
      context,
      contentType: 'profile',
      contentId: widget.userId,
      contentLabel: 'this profile',
    );
    if (!mounted || sent != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.successGreen,
        content: Text(
          'Report sent. The admin team will review it.',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.lightGrey,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primaryBlue),
        ),
      );
    }
    if (_error != null || _profile == null) {
      return Scaffold(
        backgroundColor: AppColors.lightGrey,
        appBar: AppBar(
          backgroundColor: AppColors.darkNavy,
          foregroundColor: AppColors.white,
        ),
        body: Center(
          child: Text(
            _error ?? 'Profile not found.',
            style: AppTextStyles.bodyMedium,
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.lightGrey,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHero(),
            const SizedBox(height: 56),
            _buildNameBlock(),
            const SizedBox(height: 16),
            if (!_isSelf) _buildActionToolbar(),
            const SizedBox(height: 18),
            if (_profile!.isDiscoverable)
              ..._buildPublicSections()
            else
              _buildPrivateNotice(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildHero() {
    final cover = _profile!.coverPhotoUrl;
    return SizedBox(
      height: 220,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Cover image / gradient placeholder. Tap to expand.
          GestureDetector(
            onTap: (cover != null && cover.isNotEmpty)
                ? () => FullImageViewer.show(context, cover)
                : null,
            child: Container(
              height: 180,
              decoration: BoxDecoration(
                gradient: AppColors.appBarGradient,
                image: cover != null && cover.isNotEmpty
                    ? DecorationImage(
                        image: CachedNetworkImageProvider(cover),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
            ),
          ),
          // Back button.
          Positioned(
            top: 12,
            left: 12,
            child: SafeArea(
              child: CircleAvatar(
                backgroundColor: Colors.black.withValues(alpha: 0.35),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.white),
                  onPressed: () => context.canPop()
                      ? context.pop()
                      : context.goNamed('home'),
                ),
              ),
            ),
          ),
          // Report (only when viewing someone else's profile).
          if (!_isSelf)
            Positioned(
              top: 12,
              right: 12,
              child: SafeArea(
                child: CircleAvatar(
                  backgroundColor: Colors.black.withValues(alpha: 0.35),
                  child: IconButton(
                    icon: const Icon(
                      Icons.flag_outlined,
                      color: AppColors.white,
                    ),
                    onPressed: _reportUser,
                  ),
                ),
              ),
            ),
          // Avatar overlapping the cover bottom.
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 112,
                height: 112,
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: AppColors.white,
                  shape: BoxShape.circle,
                ),
                child: GestureDetector(
                  onTap: (_profile!.profilePhotoUrl != null &&
                          _profile!.profilePhotoUrl!.isNotEmpty)
                      ? () => FullImageViewer.show(
                          context, _profile!.profilePhotoUrl)
                      : null,
                  child: ClipOval(
                    child: _profile!.profilePhotoUrl != null &&
                            _profile!.profilePhotoUrl!.isNotEmpty
                        ? CachedImage(
                            _profile!.profilePhotoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => _initialAvatar(),
                          )
                        : _initialAvatar(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _initialAvatar() {
    final initial = _profile!.fullName.trim().isEmpty
        ? '?'
        : _profile!.fullName.trim().substring(0, 1).toUpperCase();
    return Container(
      decoration: BoxDecoration(gradient: AppColors.primaryGradient),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: AppTextStyles.displayLarge.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w700,
          fontSize: 42,
        ),
      ),
    );
  }

  Widget _buildNameBlock() {
    final age = _profile!.age;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  _profile!.fullName,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.displayMedium.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                  ),
                ),
              ),
              if (_profile!.isVerified) ...[
                const SizedBox(width: 6),
                const Icon(Icons.verified,
                    color: AppColors.goldAccent, size: 20),
              ],
              if (_profile!.isBusiness) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Business',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.primaryBlue,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (age != null && (_isSelf || _profile!.showAge)) ...[
            const SizedBox(height: 4),
            Text(
              '$age years old',
              style: AppTextStyles.bodySmall.copyWith(
                color: context.palette.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionToolbar() {
    final f = _friendship;
    final isIncomingPending =
        f != null && _viewerId != null && f.isIncomingPendingFor(_viewerId!);

    final (String label, IconData icon, VoidCallback? onTap) = (() {
      if (_friendBusy) return ('Working…', Icons.hourglass_empty, null);
      if (f == null) return ('Add friend', Icons.person_add_alt_1, _addFriend);
      if (f.isAccepted) return ('Friends', Icons.check, _cancelOrUnfriend);
      if (isIncomingPending) return ('Accept', Icons.check, _acceptIncoming);
      return ('Requested', Icons.hourglass_top_rounded, _cancelOrUnfriend);
    })();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: _PrimaryButton(
              icon: icon,
              label: label,
              onTap: onTap,
              highlighted: f?.isAccepted ?? false,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 1,
            child: _SquareButton(
              icon: Icons.chat_bubble_outline,
              onTap: _openChat,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPublicSections() {
    return [
      if ((_profile!.bio ?? '').trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            _profile!.bio!.trim(),
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(height: 1.5),
          ),
        ),
      const SizedBox(height: 14),
      if ((_profile!.city ?? '').isNotEmpty ||
          (_profile!.province ?? '').isNotEmpty ||
          (_profile!.churchName ?? '').isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if ((_profile!.churchName ?? '').isNotEmpty)
                _InfoChip(
                  icon: Icons.church_outlined,
                  label: _profile!.churchName!,
                ),
              if ((_profile!.city ?? '').isNotEmpty)
                _InfoChip(
                  icon: Icons.location_on_outlined,
                  label: [_profile!.city, _profile!.province]
                      .where((s) => (s ?? '').isNotEmpty)
                      .join(', '),
                ),
            ],
          ),
        ),
      const SizedBox(height: 24),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Text(
              'Posts',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${_posts.length}',
              style: AppTextStyles.bodySmall.copyWith(
                color: context.palette.textMuted,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      if (_posts.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Text(
            'Nothing posted yet.',
            style: AppTextStyles.bodySmall.copyWith(
              color: context.palette.textMuted,
              fontStyle: FontStyle.italic,
            ),
          ),
        )
      else
        Column(
          children: [
            for (final post in _posts)
              PostCard(
                post: post,
                viewerId: _viewerId,
                onLikeToggled: () => _toggleLike(post),
                onCommentsTapped: () => _openComments(post),
                onImageTapped: () => _openImage(post),
              ),
          ],
        ),
    ];
  }

  /// Optimistic like/unlike — same pattern as home_screen so the
  /// search-to-profile path supports liking instead of the empty
  /// `() {}` no-op it had before.
  Future<void> _toggleLike(Post post) async {
    final newLiked = !post.viewerLiked;
    final newCount = (post.likeCount + (newLiked ? 1 : -1)).clamp(0, 1 << 30);
    setState(() {
      _posts = _posts
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
        _posts = _posts
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
      postAuthorId: post.authorId,
      onCommentCountChanged: (newCount) {
        if (!mounted) return;
        setState(() {
          _posts = _posts
              .map((p) =>
                  p.id == post.id ? p.copyWith(commentCount: newCount) : p)
              .toList();
        });
      },
    );
  }

  Widget _buildPrivateNotice() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.palette.divider),
        ),
        child: Column(
          children: [
            const Icon(Icons.lock_outline,
                color: AppColors.primaryBlue, size: 32),
            const SizedBox(height: 10),
            Text(
              'This profile is private',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Only their name and age are shown. Send a friend request '
              'to see their bio, posts and more.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                color: context.palette.textMuted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openImage(Post post) async {
    final url = post.imageUrl;
    if (url == null || url.isEmpty) return;
    await PostImageViewer.show(
      context,
      imageUrl: url,
      heroTag: 'post_image_${post.id}',
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool highlighted;

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
            gradient: highlighted ? null : AppColors.primaryGradient,
            color: highlighted ? context.palette.cardMuted : null,
            borderRadius: BorderRadius.circular(12),
            border: highlighted
                ? Border.all(color: context.palette.divider)
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: highlighted ? context.palette.text : AppColors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppTextStyles.buttonText.copyWith(
                  color: highlighted ? context.palette.text : AppColors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({required this.icon, required this.onTap});

  final IconData icon;
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
            color: context.palette.cardMuted,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.palette.divider),
          ),
          child: Icon(icon, color: AppColors.primaryBlue, size: 20),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.palette.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.primaryBlue),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.labelMedium.copyWith(
              color: context.palette.text,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
