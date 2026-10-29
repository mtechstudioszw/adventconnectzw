import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../config/countries.dart';
import '../../utils/photo_url.dart';
import '../../models/friendship_model.dart';
import '../../models/member_directory_model.dart';
import '../../models/ministry_tag_model.dart';
import '../../models/post_model.dart';
import '../../services/directory_service.dart';
import '../../services/ministry_service.dart';
import '../../widgets/friend_qr_sheet.dart';
import '../../widgets/ministry_chips.dart';
import '../../utils/date_format.dart';
import '../../services/auth_service.dart';
import '../../services/block_service.dart';
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
import '../../widgets/screen_shell.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../services/seller_service.dart';
import '../../widgets/moderation_actions.dart';
import '../../config/share_config.dart';
import '../../services/follow_service.dart';
import '../../widgets/profile/post_alerts.dart';
import '../../widgets/profile/profile_header.dart';
import 'package:share_plus/share_plus.dart';

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

  /// patch_166. Church + mutual-friend COUNT for the person being viewed.
  /// The same signal the chat header carries — "do we belong to the same
  /// congregation, and do we know any of the same people" is the question
  /// a profile should answer first. The RPC returns a count only, never
  /// the identities, so the friend graph stays private.
  ({String? churchName, int mutualFriends})? _peerContext;

  /// The mutual friends themselves (patch_182) — faces and names, not
  /// just the count above. A number tells you there is common ground;
  /// seeing *who* is what actually makes a stranger's profile feel
  /// placed. Empty until the RPC resolves, and for your own profile.
  List<MemberDirectoryEntry> _mutuals = const [];
  int _mutualTotal = 0;

  /// Their ministry involvement + spiritual gifts (patch_168). RLS
  /// returns nothing for a non-discoverable profile, so this stays
  /// empty and the section renders nothing.
  List<MinistryTag> _tags = const [];

  /// patch_274. Null until loaded, and stays null when following isn't
  /// available yet — the header then leaves Follow out instead of
  /// showing a button that can't work.
  FollowStats? _follow;
  bool _followBusy = false;

  /// Whether the VIEWER blocked this member (for the ⋯ menu's
  /// Block / Unblock). If they blocked the viewer, the screen never gets
  /// this far.
  bool _iBlocked = false;

  String? get _viewerId => AuthService.currentUser?.id;
  bool get _isSelf => _viewerId == widget.userId;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    if (FollowService.mutedAlerts.value == null) {
      FollowService.loadAlertMutes();
    }
    SellerService.isCurrentUserSuperAdmin().then((admin) {
      if (mounted && admin) setState(() => _isSuperAdmin = true);
    });
  }

  bool _isSuperAdmin = false;

  Future<void> _adminModeratePost(Post post) async {
    final updated = await moderatePost(context, post);
    if (updated == null || !mounted) return;
    // Admins can still read a hidden post, so here it stays, with its
    // banner, and the menu offers Restore.
    setState(() {
      _posts = [for (final p in _posts) p.id == post.id ? updated : p];
    });
  }

  Future<void> _bootstrap() async {
    try {
      final results = await Future.wait([
        UserProfileService.fetch(widget.userId),
        FeedService.fetchMyFriendships(),
        BlockService.hasBlockedMe(widget.userId),
      ]);
      if (!mounted) return;
      // If THEY blocked the viewer, their profile reads as unavailable
      // (no photo, cover, about, posts or stories — those are RLS-hidden
      // too).
      //
      // One-directional on purpose. This used to ask the SYMMETRIC
      // `is_blocked_by`, so blocking somebody also hid them from YOU —
      // including this screen, which is the only place the Unblock
      // button lives. See patch_266.
      if (results[2] as bool) {
        setState(() {
          _loading = false;
          _error = 'This account is unavailable.';
        });
        return;
      }
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
      // Peer context is useful even on a private profile — knowing you
      // share a church is exactly what helps you decide whether to send
      // the request that would open it up.
      if (profile != null && !_isSelf) {
        _loadPeerContext();
      }
      if (profile != null) {
        _loadMinistryTags();
        _loadFollow();
        if (!_isSelf) _loadBlocked();
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
      // Profile posts are strictly newest-first (NOT the personalised
      // home-feed order) so the profile reads latest → oldest.
      final posts = await FeedService.fetchPostsByAuthor(widget.userId);
      if (!mounted) return;
      setState(() {
        _posts = posts;
      });
    } catch (_) {
      // ignore — empty posts state is fine.
    }
  }

  Future<void> _loadPeerContext() async {
    try {
      final ctx = await MessagingService.fetchPeerContext(widget.userId);
      if (!mounted) return;
      setState(() => _peerContext = ctx);
    } catch (_) {
      // Best-effort — the strip just doesn't render.
    }
    // Who those mutuals actually are. Separate call so a failure here
    // never costs the church/count strip above.
    final mutual = await DirectoryService.fetchMutualFriends(widget.userId);
    if (!mounted) return;
    setState(() {
      _mutuals = mutual.people;
      _mutualTotal = mutual.total;
    });
  }

  Future<void> _loadFollow() async {
    try {
      final stats = await FollowService.stats(widget.userId);
      if (!mounted) return;
      setState(() => _follow = stats);
    } catch (_) {
      // Before patch_274 (or offline) the header simply has no follow
      // numbers or button.
    }
  }

  Future<void> _loadBlocked() async {
    try {
      final mine = await BlockService.fetchMyBlocked();
      if (!mounted) return;
      setState(() => _iBlocked = mine.any((b) => b.blockedId == widget.userId));
    } catch (_) {}
  }

  /// Private accounts (patch_274) show posts to the owner, friends and
  /// approved followers. The server enforces it; this only decides
  /// whether to explain the empty space.
  bool get _canSeeContent {
    final p = _profile;
    if (p == null) return false;
    if (_isSelf || !p.isPrivate) return true;
    if (_friendship?.isAccepted ?? false) return true;
    return _follow?.state == FollowState.following;
  }

  Future<void> _toggleFollow() async {
    final current = _follow;
    if (current == null || _followBusy) return;
    if (current.state != FollowState.none) {
      final following = current.state == FollowState.following;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            following ? 'Unfollow?' : 'Withdraw request?',
            style: AppTextStyles.titleLarge.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            following
                ? "You'll stop seeing ${_profile!.fullName}'s public posts "
                      'in your feed. They are not told.'
                : 'Your request to follow ${_profile!.fullName} will be '
                      'withdrawn.',
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
              child: Text(following ? 'Unfollow' : 'Withdraw'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _followBusy = true);
    try {
      FollowState next;
      if (current.state == FollowState.none) {
        next = await FollowService.follow(widget.userId);
      } else {
        await FollowService.unfollow(widget.userId);
        next = FollowState.none;
      }
      if (!mounted) return;
      final wasCounted = current.state == FollowState.following;
      final nowCounted = next == FollowState.following;
      setState(() {
        _followBusy = false;
        _follow = FollowStats(
          followers:
              current.followers + (nowCounted ? 1 : 0) - (wasCounted ? 1 : 0),
          following: current.following,
          state: next,
          followsMe: current.followsMe,
        );
      });
      // Following a private account that just let you in, or leaving one,
      // changes what the posts list may show.
      if (nowCounted != wasCounted && _profile!.isPrivate) _loadPosts();
    } on FollowNotAllowed {
      if (!mounted) return;
      setState(() => _followBusy = false);
      _showError(
        _profile?.whoCanFollow == WhoCanFollow.friends
            ? 'Only their friends can follow them.'
            : "They aren't taking followers.",
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _followBusy = false);
      _showError(
        FollowService.available
            ? 'Could not update follow. Please try again.'
            : 'Following needs a database update before it can be used.',
      );
    }
  }

  Future<void> _shareProfile() async {
    final p = _profile;
    if (p == null) return;
    await Share.share(
      '${p.fullName} on Adventist Super App\n${friendShareUrl(p.id)}',
      subject: p.fullName,
    );
  }

  Future<void> _toggleBlock() async {
    final name = _profile?.fullName ?? 'this member';
    final blocking = !_iBlocked;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          blocking ? 'Block $name?' : 'Unblock $name?',
          style: AppTextStyles.titleLarge.copyWith(fontWeight: FontWeight.w700),
        ),
        content: Text(
          blocking
              ? "They won't be able to message you, follow you or see your "
                    "posts. They aren't told."
              : 'They will be able to find you, message you and follow you '
                    'again.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: AppTextStyles.buttonText.copyWith(color: ctx.palette.text),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: blocking ? AppColors.red : AppColors.primaryBlue,
            ),
            child: Text(blocking ? 'Block' : 'Unblock'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      if (blocking) {
        await BlockService.block(widget.userId);
      } else {
        await BlockService.unblock(widget.userId);
      }
      if (!mounted) return;
      setState(() => _iBlocked = blocking);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(blocking ? '$name blocked.' : '$name unblocked.'),
        ),
      );
    } catch (_) {
      if (mounted) _showError('Could not update. Please try again.');
    }
  }

  Future<void> _openMoreMenu() async {
    final palette = context.palette;
    // Post alerts only make sense once you follow them (patch_283).
    final muted = _follow?.state == FollowState.following
        ? alertsMuted('user', widget.userId)
        : null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: const Text('Share profile'),
              onTap: () => Navigator.pop(ctx, 'share'),
            ),
            if (muted != null)
              ListTile(
                leading: Icon(
                  muted
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                ),
                title: Text(
                  muted ? 'Turn post alerts back on' : 'Mute post alerts',
                ),
                subtitle: Text(
                  muted
                      ? "You're not notified when they post."
                      : "Stop notifications when they post. You'll still "
                            'follow them.',
                ),
                onTap: () => Navigator.pop(ctx, 'alerts'),
              ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Report'),
              onTap: () => Navigator.pop(ctx, 'report'),
            ),
            ListTile(
              leading: Icon(
                _iBlocked ? Icons.lock_open_rounded : Icons.block_rounded,
                color: _iBlocked ? null : AppColors.red,
              ),
              title: Text(
                _iBlocked ? 'Unblock' : 'Block',
                style: TextStyle(color: _iBlocked ? null : AppColors.red),
              ),
              onTap: () => Navigator.pop(ctx, 'block'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'share':
        await _shareProfile();
      case 'alerts':
        await toggleAlertMute(
          context,
          type: 'user',
          id: widget.userId,
          name: (_profile?.fullName ?? 'they').split(' ').first,
        );
      case 'report':
        await _reportUser();
      case 'block':
        await _toggleBlock();
    }
  }

  Future<void> _loadMinistryTags() async {
    try {
      final tags = await MinistryService.fetchForProfile(widget.userId);
      if (!mounted) return;
      setState(() => _tags = tags);
    } catch (_) {
      // Best-effort — the section just doesn't render.
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
          style: AppTextStyles.titleLarge.copyWith(fontWeight: FontWeight.w700),
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
              style: AppTextStyles.buttonText.copyWith(color: ctx.palette.text),
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
      context.pushNamed('chat', pathParameters: {'id': convo.id}, extra: convo);
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
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: const Center(child: BrandSpinner(size: 30)),
      );
    }
    if (_error != null || _profile == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(),
        body: Center(
          child: Text(
            _error ?? 'Profile not found.',
            style: AppTextStyles.bodyMedium,
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProfileGlow(
              photoUrl: _profile!.profilePhotoUrl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [_buildTopBar(), _buildHeader()],
              ),
            ),
            const SizedBox(height: 18),
            // Shared church + mutual friends, above the bio — it is the
            // context you read the rest of the profile through.
            ?_buildPeerContextStrip(),
            ?_buildMutualFriendsRow(),
            if (!_profile!.isDiscoverable)
              _buildPrivateNotice()
            else if (!_canSeeContent)
              _buildPrivateNotice(followGate: true)
            else
              ..._buildPublicSections(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  /// Back + title row. Flat, transparent, in the normal flow (CLAUDE.md).
  Widget _buildTopBar() {
    return FlatStatusBar(
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
          child: Row(
            children: [
              const ScreenHeroBackButton(),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _profile!.username != null
                      ? '@${_profile!.username}'
                      : _profile!.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: context.palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _initials {
    final words = _profile!.fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    return words.isEmpty
        ? '?'
        : words.take(2).map((w) => w[0].toUpperCase()).join();
  }

  Widget _buildHeader() {
    final p = _profile!;
    final cover = p.coverPhotoUrl;
    final photo = p.profilePhotoUrl;
    final follow = _follow;
    final age = p.age;
    final place = <String?>[
      p.city,
      Countries.nameOf(p.country),
    ].where((s) => (s ?? '').isNotEmpty).join(', ');
    // A non-discoverable profile shows name and age only — that rule
    // predates the redesign and still holds.
    final open = p.isDiscoverable;

    String? note;
    if (!_isSelf) {
      if (_friendship?.isAccepted ?? false) {
        note = follow?.followsMe == true ? 'Friends · Follows you' : 'Friends';
      } else if (follow?.followsMe == true) {
        note = 'Follows you';
      }
    }

    void openList(String tab) => context.pushNamed(
      'follows',
      pathParameters: {'userId': p.id},
      queryParameters: {'tab': tab, 'name': p.fullName},
    );

    return ProfileHeader(
      name: p.fullName,
      initials: _initials,
      username: p.username,
      photoUrl: photo,
      coverUrl: open ? cover : null,
      bio: open ? p.bio : null,
      verified: p.showsVerifiedTick,
      relationNote: note,
      badges: [
        if (p.isBusiness)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
        if (p.isPrivate)
          Icon(
            Icons.lock_outline_rounded,
            size: 16,
            color: context.palette.textMuted,
          ),
      ],
      facts: [
        if (open && (p.churchName ?? '').isNotEmpty)
          ProfileFact(Icons.church_outlined, p.churchName!),
        if (open && place.isNotEmpty)
          ProfileFact(
            Icons.location_on_outlined,
            '${Countries.flagOf(p.country)} $place'.trim(),
          ),
        if (open && p.website != null)
          ProfileFact(
            Icons.link_rounded,
            websiteLabel(p.website!),
            onTap: () => openProfileWebsite(p.website!),
          ),
        if (age != null && (_isSelf || p.showAge))
          ProfileFact(Icons.cake_outlined, '$age years old'),
        if (open && p.joinedAt != null)
          ProfileFact(
            Icons.calendar_today_outlined,
            'Joined ${formatJoinDate(p.joinedAt!)}',
          ),
      ],
      stats: [
        ProfileStat(
          _posts.length == 1 ? 'Post' : 'Posts',
          open && _canSeeContent ? _posts.length : null,
        ),
        // Following turned off (patch_282): no follower count either — "0
        // followers" with no way to follow reads as a broken profile.
        if (_isSelf || p.whoCanFollow != WhoCanFollow.nobody)
          ProfileStat(
            'Followers',
            follow?.followers,
            onTap: () => openList('followers'),
          ),
        ProfileStat(
          'Following',
          follow?.following,
          onTap: () => openList('following'),
        ),
      ],
      onAvatarTap: (photo ?? '').isEmpty
          ? null
          : () => FullImageViewer.show(context, photoUrlAtSize(photo, 1024)),
      onCoverTap: (cover ?? '').isEmpty
          ? null
          : () => FullImageViewer.show(context, cover),
      actions: _isSelf ? _selfActions() : _visitorActions(),
    );
  }

  /// Opened your own profile through search or a link: send them to the
  /// real one rather than offering to follow yourself.
  List<Widget> _selfActions() => [
    ProfileActionButton(
      label: 'Open my profile',
      icon: Icons.person_outline,
      primary: true,
      onTap: () => context.goNamed('profile'),
    ),
  ];

  List<Widget> _visitorActions() {
    final follow = _follow;
    final f = _friendship;
    final incoming =
        f != null && _viewerId != null && f.isIncomingPendingFor(_viewerId!);
    final (String friendLabel, VoidCallback friendTap) = (() {
      if (f == null) return ('Add friend', _addFriend);
      if (f.isAccepted) return ('Friends', _cancelOrUnfriend);
      if (incoming) return ('Accept', _acceptIncoming);
      return ('Requested', _cancelOrUnfriend);
    })();
    // Their "who can follow me" setting (patch_282). Someone who already
    // follows keeps the button so they can still unfollow.
    final who = _profile?.whoCanFollow ?? WhoCanFollow.everyone;
    final followAllowed =
        who == WhoCanFollow.everyone ||
        (who == WhoCanFollow.friends && (f?.isAccepted ?? false));
    final showFollow =
        follow != null && (followAllowed || follow.state != FollowState.none);
    return [
      if (showFollow)
        ProfileActionButton(
          label: switch (follow.state) {
            FollowState.none => follow.followsMe ? 'Follow back' : 'Follow',
            FollowState.requested => 'Requested',
            FollowState.following => 'Following',
          },
          primary: follow.state == FollowState.none,
          busy: _followBusy,
          onTap: _toggleFollow,
        ),
      ProfileActionButton(
        label: friendLabel,
        // Primary when following isn't available, so the row still has
        // one clear first action.
        primary: !showFollow && (f == null || incoming),
        icon: !showFollow ? Icons.person_add_alt_1 : null,
        busy: _friendBusy,
        onTap: friendTap,
      ),
      ProfileActionButton.icon(
        icon: Icons.chat_bubble_outline,
        label: 'Message',
        onTap: _openChat,
      ),
      // Their QR card, to share their profile (owner, 29 Oct 2026).
      ProfileActionButton.icon(
        icon: Icons.qr_code_2_rounded,
        label: 'QR code',
        onTap: () => showFriendQrSheet(
          context,
          userId: widget.userId,
          name: _profile?.fullName,
        ),
      ),
      ProfileActionButton.icon(
        icon: Icons.more_horiz,
        label: 'More',
        onTap: _openMoreMenu,
      ),
    ];
  }

  /// Overlapping faces + names of the friends you have in common, the way
  /// Facebook does it: "Rutendo, Blessing and 6 others".
  ///
  /// Only the intersection is ever fetched (patch_182), so this shows the
  /// viewer people they already know — it never discloses who else this
  /// member is friends with. Renders nothing when there are none, rather
  /// than announcing "0 mutual friends".
  Widget? _buildMutualFriendsRow() {
    if (_isSelf || _mutuals.isEmpty) return null;
    final shown = _mutuals.take(3).toList();
    final names = shown
        .map((m) => (m.fullName ?? '').trim().split(RegExp(r'\s+')).first)
        .where((n) => n.isNotEmpty)
        .toList();
    if (names.isEmpty) return null;
    final others = _mutualTotal - names.length;
    final summary = others > 0
        ? '${names.join(', ')} and $others other${others == 1 ? '' : 's'}'
        : names.join(', ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          SizedBox(
            width: 28.0 + (shown.length - 1) * 18.0,
            height: 28,
            child: Stack(
              children: [
                for (var i = 0; i < shown.length; i++)
                  Positioned(
                    left: i * 18.0,
                    child: Container(
                      width: 28,
                      height: 28,
                      clipBehavior: Clip.antiAlias,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.primaryGradient,
                        border: Border.all(
                          color: context.palette.scaffoldBg,
                          width: 2,
                        ),
                      ),
                      child: (shown[i].profilePhotoUrl ?? '').isEmpty
                          ? Center(child: _miniInitial(shown[i].fullName))
                          : CachedImage(
                              shown[i].profilePhotoUrl!,
                              fit: BoxFit.cover,
                              width: 28,
                              height: 28,
                              errorBuilder: (_, _, _) => Center(
                                child: _miniInitial(shown[i].fullName),
                              ),
                            ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$summary ${others > 0 || names.length > 1 ? 'are' : 'is'} '
              'mutual friend${_mutualTotal == 1 ? '' : 's'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall.copyWith(
                color: context.palette.textMuted,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniInitial(String? name) {
    final trimmed = (name ?? '').trim();
    return Text(
      trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase(),
      textAlign: TextAlign.center,
      style: AppTextStyles.labelSmall.copyWith(
        color: AppColors.white,
        fontWeight: FontWeight.w800,
        fontSize: 11,
        height: 1,
      ),
    );
  }

  /// "You both go to Glen View SDA · 3 mutual friends" — the two facts
  /// that answer "who is this to me". Renders nothing when the RPC hasn't
  /// resolved or has nothing to say, rather than showing "0 mutual
  /// friends", which reads as a judgement.
  Widget? _buildPeerContextStrip() {
    final ctx = _peerContext;
    if (ctx == null) return null;
    final church = ctx.churchName?.trim();
    final mutual = ctx.mutualFriends;
    final bits = <({IconData icon, String label})>[
      if (church != null && church.isNotEmpty)
        (icon: Icons.church_outlined, label: church),
      if (mutual > 0)
        (
          icon: Icons.people_alt_outlined,
          label: '$mutual mutual friend${mutual == 1 ? '' : 's'}',
        ),
    ];
    if (bits.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.primaryBlue.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.primaryBlue.withValues(alpha: 0.16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < bits.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Container(
                    width: 3,
                    height: 3,
                    decoration: BoxDecoration(
                      color: context.palette.textMuted,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              Icon(bits[i].icon, size: 14, color: AppColors.primaryBlue),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  bits[i].label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: context.palette.text,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPublicSections() {
    return [
      // Ministry & gifts (patch_168) — read-only here. Turns "who is
      // this" into "who can help with this", which is the question a
      // church directory exists to answer.
      if (_tags.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: MinistrySection(tags: _tags, isOwn: false),
        ),
      ],
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
                onImageTapped: (_) => _openImage(post),
                // Posts on someone's profile had no menu at all, so they
                // could not be reported (Apple 1.2).
                onReport: () => showReportSheet(
                  context,
                  contentType: 'post',
                  contentId: post.id,
                  contentLabel: 'this post',
                ),
                onAdminModerate: _isSuperAdmin
                    ? () => _adminModeratePost(post)
                    : null,
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
        _posts = _posts
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
          _posts = _posts
              .map(
                (p) => p.id == post.id ? p.copyWith(commentCount: newCount) : p,
              )
              .toList();
        });
      },
    );
  }

  Widget _buildPrivateNotice({bool followGate = false}) {
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
            const Icon(
              Icons.lock_outline,
              color: AppColors.primaryBlue,
              size: 32,
            ),
            const SizedBox(height: 10),
            Text(
              followGate
                  ? 'This account is private'
                  : 'This profile is private',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              followGate
                  ? 'Follow this account or become friends to see their '
                        'posts.'
                  : 'Only their name and age are shown. Send a friend '
                        'request to see their bio, posts and more.',
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
