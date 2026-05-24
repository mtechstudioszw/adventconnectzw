import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/church_model.dart';
import '../../models/event_model.dart';
import '../../models/friendship_model.dart';
import '../../models/member_directory_model.dart';
import '../../models/message_model.dart';
import '../../models/post_model.dart';
import '../../models/story_model.dart';
import '../../services/auth_service.dart';
import '../../services/cache_service.dart';
import '../../services/church_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/directory_service.dart';
import '../../services/gallery_service.dart';
import '../../services/event_service.dart';
import '../../services/feed_service.dart';
import '../../services/messaging_service.dart';
import '../../services/notification_service.dart';
import '../../services/sabbath_service.dart';
import '../../services/urgent_banner_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/home/advent_chat_bubble.dart';
import '../../widgets/home/comments_sheet.dart';
import '../../widgets/home/composer_sheet.dart';
import '../../widgets/home/edit_post_dialog.dart';
import '../../widgets/home/invite_friends_card.dart';
import '../../widgets/home/post_card.dart';
import '../../widgets/home/post_image_viewer.dart';
import '../../widgets/home/report_sheet.dart';
import '../../widgets/home/stories_rail.dart';
import '../../widgets/last_updated_strip.dart';
import '../../widgets/home/story_viewer.dart';
import '../../widgets/shimmer_loaders.dart';
import '../widgets/main_bottom_nav.dart';
import '../../widgets/cached_image.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  List<Event> _events = [];
  List<Church> _churches = [];
  List<MemberDirectoryEntry> _suggestedMembers = [];
  Set<String> _followedChurchIds = <String>{};
  Set<String> _rsvpedEventIds = <String>{};
  int _unreadNotifications = 0;
  List<Post> _posts = [];
  List<Story> _stories = [];
  // userId -> friendship row (if any) so the suggestion cards know
  // whether to show "Add friend" / "Pending" / "Friends".
  Map<String, Friendship> _friendshipsByUser = <String, Friendship>{};
  int _unreadMessages = 0;
  int _pendingFriendRequests = 0;
  UrgentBanner? _banner;
  // Banners dismissed in this session — kept in memory only so the
  // user sees fresh banners on relaunch but isn't pestered after they
  // already swiped one away.
  final Set<String> _dismissedBannerIds = <String>{};
  bool _loading = true;
  StreamSubscription<AuthState>? _authSub;

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
    // Rebuild whenever the user's profile metadata changes (e.g. after a
    // save in Edit Profile) so the greeting / welcome card refresh without
    // requiring the user to relaunch the app.
    _authSub = AuthService.authStateChanges.listen((_) {
      if (mounted) setState(() {});
    });
    _bootstrap();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    // Always hydrate from cache first so the screen paints real
    // content immediately, before the network call resolves.
    // Facebook-style: see something instantly, then silently refresh.
    if (_loading) {
      _hydrateFromCache();
    }

    try {
      final results = await Future.wait([
        EventService.fetchEvents(upcomingOnly: true),
        ChurchService.fetchChurches(),
        ChurchService.fetchUserFollowedChurchIds(),
        EventService.fetchUserRsvpedEventIds(),
        NotificationService.unreadCount(),
        UrgentBannerService.fetchActive(),
        DirectoryService.fetchSuggestedMembers(),
        FeedService.fetchFeed(),
        FeedService.fetchStories(),
        FeedService.fetchMyFriendships(),
        FeedService.pendingRequestCount(),
        MessagingService.fetchConversations(),
      ]);
      if (!mounted) return;
      // Drop events whose start time is more than a few hours in the
      // past — `upcomingOnly: true` filters by start_date (date-only),
      // so today's already-ended events would otherwise still appear
      // on the home screen until midnight rolls over.
      final now = DateTime.now();
      final stillUpcoming = (results[0] as List<Event>)
          .where((e) => e.startsAt.isAfter(now.subtract(const Duration(hours: 6))))
          .toList();
      final events = stillUpcoming.take(8).toList();
      final churches = (results[1] as List<Church>).take(6).toList();
      final friendships = results[9] as List<Friendship>;
      final viewerId = AuthService.currentUser?.id;
      final friendsByUser = <String, Friendship>{};
      if (viewerId != null) {
        for (final f in friendships) {
          friendsByUser[f.otherUserId(viewerId)] = f;
        }
      }
      final conversations = results[11] as List<Conversation>;
      int unreadMessages = 0;
      for (final c in conversations) {
        unreadMessages += c.unreadCount;
      }
      // Hide the viewer's own posts from the home feed — they already
      // see them in the Profile → Posts tab. Treating "home" as a feed
      // of *other* people's content matches what users expect from a
      // social timeline.
      final feedPosts = (results[7] as List<Post>)
          .where((p) => viewerId == null || p.authorId != viewerId)
          .toList();
      setState(() {
        _events = events;
        _churches = churches;
        _followedChurchIds = results[2] as Set<String>;
        _rsvpedEventIds = results[3] as Set<String>;
        _unreadNotifications = results[4] as int;
        _banner = results[5] as UrgentBanner?;
        _suggestedMembers = results[6] as List<MemberDirectoryEntry>;
        _posts = feedPosts;
        _stories = results[8] as List<Story>;
        _friendshipsByUser = friendsByUser;
        _pendingFriendRequests = results[10] as int;
        _unreadMessages = unreadMessages;
        _loading = false;
      });
      // Best-effort cache write — failures here must never surface.
      unawaited(_writeCache(events, churches, feedPosts));
    } catch (_) {
      if (!mounted) return;
      // Network failed. If we haven't hydrated from cache yet (e.g.
      // because we were online when _bootstrap started), try now.
      if (_events.isEmpty && _churches.isEmpty) {
        _hydrateFromCache();
      }
      setState(() => _loading = false);
    }
  }

  Future<void> _writeCache(
    List<Event> events,
    List<Church> churches,
    List<Post> posts,
  ) async {
    try {
      final payload = jsonEncode({
        'events': events.map((e) => e.toJson()).toList(),
        'churches': churches.map((c) => c.toJson()).toList(),
        'posts': posts.take(30).map((p) => p.toJson()).toList(),
      });
      await CacheService.writeString('home_feed', payload);
    } catch (_) {
      // Cache is decorative — never block.
    }
  }

  void _hydrateFromCache() {
    try {
      final raw = CacheService.readString('home_feed');
      if (raw == null) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final events = ((decoded['events'] as List?) ?? const [])
          .map((e) => Event.fromJson(e as Map<String, dynamic>))
          .toList();
      final churches = ((decoded['churches'] as List?) ?? const [])
          .map((c) => Church.fromJson(c as Map<String, dynamic>))
          .toList();
      final viewerId = AuthService.currentUser?.id;
      final posts = ((decoded['posts'] as List?) ?? const [])
          .map((p) => Post.fromJson(
                p as Map<String, dynamic>,
                viewerId: viewerId,
              ))
          .toList();
      if (!mounted) return;
      setState(() {
        if (_events.isEmpty) _events = events;
        if (_churches.isEmpty) _churches = churches;
        if (_posts.isEmpty) _posts = posts;
        // Paint instantly when cache hits — no spinner.
        if (events.isNotEmpty || churches.isNotEmpty || posts.isNotEmpty) {
          _loading = false;
        }
      });
    } catch (_) {
      // ignore — corrupt cache is just a missed-paint, not an error.
    }
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    if (h < 22) return 'Good evening';
    return 'Good night';
  }

  String _firstName() {
    final user = AuthService.currentUser;
    final meta = user?.userMetadata ?? const {};
    final raw = (meta['full_name'] as String?)?.trim() ?? '';
    if (raw.isEmpty) {
      final email = user?.email ?? '';
      final at = email.indexOf('@');
      return at > 0 ? email.substring(0, at) : 'Friend';
    }
    return raw.split(' ').first;
  }

  String _initials() {
    final user = AuthService.currentUser;
    final meta = user?.userMetadata ?? const {};
    final raw = (meta['full_name'] as String?)?.trim() ?? '';
    if (raw.isEmpty) return (user?.email ?? '?').substring(0, 1).toUpperCase();
    final parts = raw.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  bool get _hasUnreadChat =>
      _unreadMessages > 0 || _pendingFriendRequests > 0;

  int? get _chatBadgeCount {
    final total = _unreadMessages + _pendingFriendRequests;
    return total > 0 ? total : null;
  }

  Future<void> _openPostComposer() async {
    final post = await showPostComposer(context);
    if (!mounted || post == null) return;
    // The viewer's own posts are filtered out of the home feed (they
    // belong on Profile → Posts), so don't insert a fresh one here.
    // Surface a small confirmation instead so the user knows the post
    // landed and where to find it.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.successGreen,
        content: Text(
          'Posted — see it on your profile.',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        ),
      ),
    );
  }

  Future<void> _openStoryComposer() async {
    final story = await showStoryComposer(context);
    if (!mounted || story == null) return;
    setState(() => _stories = [story, ..._stories]);
  }

  Future<void> _openStoryViewer(List<Story> authorStories) {
    // Newest-first comes from the server; the viewer plays oldest→newest
    // like Facebook does, so flip the list before showing.
    return StoryViewer.show(context, authorStories.reversed.toList());
  }

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
      // Revert on failure.
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

  Future<void> _sendFriendRequest(MemberDirectoryEntry member) async {
    try {
      final f = await FeedService.sendRequest(member.userId);
      if (!mounted) return;
      setState(() => _friendshipsByUser[member.userId] = f);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Friend request sent to ${member.fullName ?? "Member"}.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not send request. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  String? _viewerPhotoUrl() {
    final user = AuthService.currentUser;
    final meta = user?.userMetadata ?? const {};
    final raw = (meta['profile_photo_url'] as String?)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGrey,
      body: Stack(
        children: [
          _buildScrollableContent(),
          Positioned(
            right: 16,
            bottom: 24,
            child: AdventChatBubble(
              hasUnread: _hasUnreadChat,
              unreadCount: _chatBadgeCount,
            ),
          ),
        ],
      ),
      bottomNavigationBar: MainBottomNav(
        currentIndex: 0,
        badges: {
          // Profile tab surfaces chat + friend-request badges because
          // messaging lives inside the Profile menu.
          if (_hasUnreadChat) 4: _unreadMessages + _pendingFriendRequests,
        },
      ),
    );
  }

  Widget _buildScrollableContent() {
    return RefreshIndicator(
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                if (_banner != null &&
                    !_dismissedBannerIds.contains(_banner!.id)) ...[
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _UrgentBannerCard(
                      banner: _banner!,
                      onDismiss: () => setState(
                        () => _dismissedBannerIds.add(_banner!.id),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                _buildSectionHeader('Stories', null),
                const SizedBox(height: 10),
                StoriesRail(
                  stories: _stories,
                  viewerId: AuthService.currentUser?.id ?? '',
                  viewerName: _displayFullName(),
                  viewerPhotoUrl: _viewerPhotoUrl(),
                  onAddStory: _openStoryComposer,
                  onAuthorTapped: (_, list) => _openStoryViewer(list),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _ComposerEntry(
                    photoUrl: _viewerPhotoUrl(),
                    name: _displayFullName(),
                    onTap: _openPostComposer,
                  ),
                ),
                const SizedBox(height: 6),
                // _buildFeedList() is now a Facebook-style mixed feed:
                // posts intercalated with discovery cards (suggested
                // people, events, prayer prompt, churches, invite
                // friends, quick stats). The standalone sections that
                // used to live below this point were folded into the
                // feed so the user gets one continuous scroll instead
                // of jumping between mode-locked panels.
                _buildFeedList(),
                const SizedBox(height: 24),
                const AdBanner(),
                // Bottom padding so the floating chat bubble + plus FAB
                // don't sit on top of the last bit of feed content.
                const SizedBox(height: 96),
              ],
            ),
          ),
        ),
      );
  }

  Widget _buildHeader() {
    return SizedBox(
      height: 240,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipPath(
            clipper: _HeaderClipper(),
            child: Container(
              height: 200,
              decoration: const BoxDecoration(
                gradient: AppColors.appBarGradient,
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(-0.6, -0.8),
                            radius: 1.0,
                            colors: [
                              AppColors.white.withValues(alpha: 0.07),
                              AppColors.white.withValues(alpha: 0.0),
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _greeting().toUpperCase(),
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: AppColors.white
                                        .withValues(alpha: 0.65),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.6,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Hello, ${_firstName()}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.headlineLarge.copyWith(
                                    color: AppColors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const _SabbathChip(),
                              ],
                            ),
                          ),
                          _HeaderIconButton(
                            icon: Icons.search,
                            onTap: () => context.pushNamed('search'),
                          ),
                          const SizedBox(width: 8),
                          _NotificationBell(
                            unread: _unreadNotifications,
                            onTap: () async {
                              await context.pushNamed('notification_centre');
                              if (mounted) _bootstrap();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 0,
            child: _WelcomeCard(
              initials: _initials(),
              fullName: _displayFullName(),
              followedCount: _followedChurchIds.length,
              photoUrl: _profilePhotoUrl(),
            ),
          ),
        ],
      ),
    );
  }

  String _displayFullName() {
    final user = AuthService.currentUser;
    final meta = user?.userMetadata ?? const {};
    final raw = (meta['full_name'] as String?)?.trim() ?? '';
    if (raw.isNotEmpty) return raw;
    return user?.email ?? 'Welcome';
  }

  /// True when there's at least one suggested member the viewer is
  /// NOT already friends with. Pending requests still count so the
  /// rail shows even when there's only an Accept-button card to show.
  bool get _hasNonFriendSuggestions {
    return _suggestedMembers.any((m) {
      final f = _friendshipsByUser[m.userId];
      if (f == null) return true;
      return f.status != FriendshipStatus.accepted;
    });
  }

  String? _profilePhotoUrl() {
    final user = AuthService.currentUser;
    final meta = user?.userMetadata ?? const {};
    final raw = (meta['profile_photo_url'] as String?)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  Widget _buildSectionHeader(
    String title,
    String? action, {
    VoidCallback? onAction,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.headlineMedium.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
              ),
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    action,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.primaryBlue,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickStats() {
    final upcomingForUser = _events
        .where((e) => _rsvpedEventIds.contains(e.id))
        .length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _CompactStatTile(
              icon: Icons.church_outlined,
              value: '${_followedChurchIds.length}',
              label: 'Churches',
              onTap: () => context.goNamed('churches'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _CompactStatTile(
              icon: Icons.event_available_outlined,
              value: '$upcomingForUser',
              label: 'Events',
              onTap: () => context.goNamed('events'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _CompactStatTile(
              icon: Icons.volunteer_activism_outlined,
              value: '0',
              label: 'Prayers',
              onTap: () => context.pushNamed('prayer'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventsRow() {
    if (_loading && _events.isEmpty) {
      return SizedBox(
        height: 200,
        child: ShimmerLoaders.cardList(count: 2),
      );
    }
    if (_events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _EmptyTile(
          icon: Icons.event_outlined,
          title: 'No upcoming events',
          subtitle: 'Check back soon — events post all week.',
        ),
      );
    }
    return SizedBox(
      height: 168,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _events.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final e = _events[i];
          return _HomeEventCard(
            event: e,
            isGoing: _rsvpedEventIds.contains(e.id),
            onTap: () async {
              await context.pushNamed(
                'event_details',
                pathParameters: {'id': e.id},
                extra: e,
              );
              if (mounted) _bootstrap();
            },
          );
        },
      ),
    );
  }

  Widget _buildChurchGrid() {
    if (_loading && _churches.isEmpty) {
      return SizedBox(
        height: 160,
        child: ShimmerLoaders.cardList(count: 2),
      );
    }
    if (_churches.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _EmptyTile(
          icon: Icons.church_outlined,
          title: 'No churches yet',
          subtitle: 'Once churches are added they\'ll show here.',
        ),
      );
    }
    // Horizontal scroller — matches the Events row's pattern and cuts
    // the section's vertical footprint roughly in half versus the
    // previous 2-column grid. User can flick through more churches
    // without taking over the home screen.
    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _churches.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final c = _churches[i];
          return SizedBox(
            width: 150,
            child: _HomeChurchTile(
              church: c,
              isFollowed: _followedChurchIds.contains(c.id),
              onTap: () async {
                await context.pushNamed(
                  'church_details',
                  pathParameters: {'id': c.id},
                  extra: c,
                );
                if (mounted) _bootstrap();
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildFeedList() {
    if (_loading && _posts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          children: [
            for (var i = 0; i < 2; i++) ...[
              Container(
                height: 240,
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ],
          ],
        ),
      );
    }
    if (_posts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: GestureDetector(
          onTap: _openPostComposer,
          behavior: HitTestBehavior.opaque,
          child: Text(
            'No updates yet — tap to share something.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.55),
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }
    final viewerId = AuthService.currentUser?.id;
    final cachedAt = CacheService.cachedAt('home_feed');
    final discoveryCards = _buildDiscoveryCards();

    // Facebook-style mixed feed: real posts intercalated with discovery
    // cards (suggested people / events / churches / prayer prompt /
    // invite friends / quick stats). One discovery card after every
    // [_discoveryEveryNPosts] posts, then any remaining cards are
    // appended at the end so the user always sees the full set even
    // when the post backlog is short.
    final children = <Widget>[];
    if (cachedAt != null) {
      children.add(const SizedBox(height: 4));
      children.add(LastUpdatedStrip(
        timestamp: cachedAt,
        isOnline: ConnectivityService.isOnline,
        onRefresh: _bootstrap,
      ));
    }
    var cardIdx = 0;
    for (var i = 0; i < _posts.length; i++) {
      final post = _posts[i];
      children.add(PostCard(
        post: post,
        viewerId: viewerId,
        onLikeToggled: () => _toggleLike(post),
        onCommentsTapped: () => _openComments(post),
        onImageTapped: () => _openImageViewer(post),
        onEdit: () => _editPost(post),
        onDelete: () => _confirmDeletePost(post),
        onToggleVisibility: () => _togglePostVisibility(post),
        onReport: () => _reportPost(post),
        onAuthorTapped: () => _openAuthorProfile(post),
        onSaveImage: () => _savePostImage(post),
      ));
      if ((i + 1) % _discoveryEveryNPosts == 0 &&
          cardIdx < discoveryCards.length) {
        children.add(discoveryCards[cardIdx++]);
      }
    }
    while (cardIdx < discoveryCards.length) {
      children.add(discoveryCards[cardIdx++]);
    }
    return Column(children: children);
  }

  // Cadence for the Facebook-style mixed feed. Smaller = more
  // discovery cards interrupting posts; larger = posts feel more
  // continuous. 3 lands close to what Instagram does for sponsored
  // breakers.
  static const _discoveryEveryNPosts = 3;

  /// Builds the ordered list of "discovery" cards (suggested people,
  /// upcoming events, prayer prompt, churches, invite friends, quick
  /// stats) that get sprinkled between posts in the feed. Empty
  /// sections are skipped so we don't waste a slot on, e.g., a "0
  /// upcoming events" card.
  List<Widget> _buildDiscoveryCards() {
    final cards = <Widget>[];
    if (_hasNonFriendSuggestions) {
      cards.add(_discoverySection(
        title: 'People to meet',
        child: _buildSuggestedMembersRow(),
      ));
    }
    if (_events.isNotEmpty) {
      cards.add(_discoverySection(
        title: 'Upcoming events',
        action: 'See all',
        onAction: () => context.goNamed('events'),
        child: _buildEventsRow(),
      ));
    }
    cards.add(_discoverySection(
      title: 'Active prayers',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _PrayersEmpty(onTap: () => context.pushNamed('prayer')),
      ),
    ));
    if (_churches.isNotEmpty) {
      cards.add(_discoverySection(
        title: 'Discover churches',
        action: 'See all',
        onAction: () => context.goNamed('churches'),
        child: _buildChurchGrid(),
      ));
    }
    cards.add(const Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: InviteFriendsCard(),
    ));
    cards.add(_discoverySection(
      title: 'Quick stats',
      child: _buildQuickStats(),
    ));
    return cards;
  }

  /// Wraps a discovery card body with its section header + consistent
  /// vertical spacing so they slot cleanly between PostCards in the
  /// mixed feed.
  Widget _discoverySection({
    required String title,
    required Widget child,
    String? action,
    VoidCallback? onAction,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        _buildSectionHeader(title, action, onAction: onAction),
        const SizedBox(height: 12),
        child,
        const SizedBox(height: 8),
      ],
    );
  }

  Future<void> _savePostImage(Post post) async {
    final url = post.imageUrl;
    if (url == null || url.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
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
    ScaffoldMessenger.of(context).showSnackBar(
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

  void _openAuthorProfile(Post post) {
    final viewerId = AuthService.currentUser?.id;
    // Tapping your own name goes to your profile tab, not a read-only
    // user-profile view of yourself.
    if (viewerId != null && post.authorId == viewerId) {
      context.goNamed('profile');
      return;
    }
    context.pushNamed(
      'user_profile',
      pathParameters: {'userId': post.authorId},
    );
  }

  Future<void> _reportPost(Post post) async {
    final sent = await showReportSheet(
      context,
      contentType: 'post',
      contentId: post.id,
      contentLabel: 'this post',
    );
    if (!mounted || sent != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.successGreen,
        content: Text(
          'Report sent. Thanks — the admin team will review it.',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        ),
      ),
    );
  }

  Future<void> _openImageViewer(Post post) async {
    final url = post.imageUrl;
    if (url == null || url.isEmpty) return;
    await PostImageViewer.show(
      context,
      imageUrl: url,
      heroTag: 'post_image_${post.id}',
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
        _posts = _posts.map((p) => p.id == updated.id ? updated : p).toList();
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
          content: Text(
            'Could not update post. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  Future<void> _editPost(Post post) async {
    final newBody = await showEditPostDialog(context, initialBody: post.body ?? '');
    if (newBody == null) return;
    try {
      final updated = await FeedService.updatePost(post.id, body: newBody);
      if (!mounted) return;
      setState(() {
        _posts = _posts.map((p) => p.id == updated.id ? updated : p).toList();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not save changes.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
          backgroundColor: AppColors.red,
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
        _posts = _posts.where((p) => p.id != post.id).toList();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not delete post.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  Widget _buildSuggestedMembersRow() {
    final viewerId = AuthService.currentUser?.id;
    // Hide people the viewer is already friends with — they no longer
    // belong in a "suggestions" rail. Pending requests (either
    // direction) stay visible so the viewer can react to them.
    final visibleSuggestions = _suggestedMembers.where((m) {
      final f = _friendshipsByUser[m.userId];
      if (f == null) return true;
      return f.status != FriendshipStatus.accepted;
    }).toList();
    return SizedBox(
      height: 210,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: visibleSuggestions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final m = visibleSuggestions[i];
          final friendship = _friendshipsByUser[m.userId];
          return SizedBox(
            width: 150,
            child: _SuggestedMemberTile(
              entry: m,
              friendship: friendship,
              viewerId: viewerId,
              onAddFriend: () => _sendFriendRequest(m),
              onAcceptRequest: () async {
                if (friendship == null) return;
                try {
                  await FeedService.acceptRequest(friendship.id);
                  if (!mounted) return;
                  setState(() {
                    _friendshipsByUser[m.userId] = Friendship(
                      id: friendship.id,
                      requesterId: friendship.requesterId,
                      addresseeId: friendship.addresseeId,
                      status: FriendshipStatus.accepted,
                      createdAt: friendship.createdAt,
                    );
                    _pendingFriendRequests =
                        (_pendingFriendRequests - 1).clamp(0, 1 << 30);
                  });
                } catch (_) {
                  // surface a quiet failure
                }
              },
              onCancelOrUnfriend: () async {
                if (friendship == null) return;
                try {
                  await FeedService.removeFriendship(friendship.id);
                  if (!mounted) return;
                  setState(() {
                    _friendshipsByUser.remove(m.userId);
                  });
                } catch (_) {
                  // ignore — next refresh corrects the state
                }
              },
              onOpenProfile: () => context.pushNamed(
                'user_profile',
                pathParameters: {'userId': m.userId},
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 24);
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width,
      size.height - 24,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Compact countdown to next Friday sundown. Hidden unless the user
/// has opted in (Settings → Sabbath countdown) AND we're within 7
/// days of the next sundown (always true at any given moment, but
/// kept as a guard in case the calculation falls through).
class _SabbathChip extends StatefulWidget {
  const _SabbathChip();

  @override
  State<_SabbathChip> createState() => _SabbathChipState();
}

class _SabbathChipState extends State<_SabbathChip> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Re-render once a minute so the countdown stays current. Cheap —
    // the widget is tiny and the rest of the header stays untouched.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!SabbathService.isEnabled()) return const SizedBox.shrink();
    final inSabbath = SabbathService.isSabbathNow();
    if (inSabbath) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.goldAccent.withValues(alpha: 0.55),
                AppColors.goldAccent.withValues(alpha: 0.30),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.goldAccent,
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.auto_awesome,
                size: 13,
                color: AppColors.white,
              ),
              const SizedBox(width: 6),
              Text(
                'Happy Sabbath',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final next = SabbathService.nextSabbathStart();
    if (next == null) return const SizedBox.shrink();
    final remaining = next.difference(DateTime.now().toUtc());
    if (remaining.isNegative) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.goldAccent.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.goldAccent.withValues(alpha: 0.45),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.brightness_3,
              size: 13,
              color: AppColors.goldAccent,
            ),
            const SizedBox(width: 6),
            Text(
              'Sabbath in ${_format(remaining)}',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _format(Duration d) {
    if (d.inDays >= 1) {
      return '${d.inDays}d ${d.inHours.remainder(24)}h';
    }
    if (d.inHours >= 1) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    }
    return '${d.inMinutes}m';
  }
}

class _SuggestedMemberTile extends StatelessWidget {
  const _SuggestedMemberTile({
    required this.entry,
    required this.friendship,
    required this.viewerId,
    required this.onAddFriend,
    required this.onAcceptRequest,
    required this.onCancelOrUnfriend,
    required this.onOpenProfile,
  });

  final MemberDirectoryEntry entry;
  final Friendship? friendship;
  final String? viewerId;
  final VoidCallback onAddFriend;
  final VoidCallback onAcceptRequest;
  final VoidCallback onCancelOrUnfriend;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final name = entry.fullName ?? 'Member';
    final subtitle = entry.profession?.trim().isNotEmpty == true
        ? entry.profession!.trim()
        : (entry.city?.trim().isNotEmpty == true
            ? entry.city!.trim()
            : 'Adventist member');
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      child: InkWell(
        onTap: onOpenProfile,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
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
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              _MemberAvatar(
                photoUrl: entry.profilePhotoUrl,
                name: name,
              ),
              const SizedBox(height: 10),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(
                  color: const Color.fromRGBO(26, 26, 46, 0.6),
                  fontSize: 11.5,
                ),
              ),
              const Spacer(),
              _friendButton(),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: onOpenProfile,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  alignment: Alignment.center,
                  child: Text(
                    'View profile',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: AppColors.primaryBlue,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _friendButton() {
    final f = friendship;
    // No relationship yet → primary "Add friend" CTA.
    if (f == null) {
      return _GradientPill(
        icon: Icons.person_add_alt_1,
        label: 'Add friend',
        onTap: onAddFriend,
      );
    }
    // Accepted → tap to unfriend.
    if (f.isAccepted) {
      return _OutlinePill(
        icon: Icons.check_circle_outline,
        label: 'Friends',
        color: AppColors.successGreen,
        onTap: onCancelOrUnfriend,
      );
    }
    // Pending: differs by direction.
    if (viewerId != null && f.isIncomingPendingFor(viewerId!)) {
      return _GradientPill(
        icon: Icons.check_rounded,
        label: 'Accept',
        onTap: onAcceptRequest,
      );
    }
    // Outgoing pending → tap to cancel.
    return _OutlinePill(
      icon: Icons.hourglass_empty_rounded,
      label: 'Cancel',
      color: AppColors.primaryBlue,
      onTap: onCancelOrUnfriend,
    );
  }
}

class _GradientPill extends StatelessWidget {
  const _GradientPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: AppColors.white),
              const SizedBox(width: 5),
              Text(
                label,
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.white,
                  fontSize: 12,
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

class _OutlinePill extends StatelessWidget {
  const _OutlinePill({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: AppTextStyles.labelMedium.copyWith(
                  color: color,
                  fontSize: 12,
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

class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({required this.photoUrl, required this.name});

  final String? photoUrl;
  final String name;

  @override
  Widget build(BuildContext context) {
    final initials = _initialsFrom(name);
    final radius = BorderRadius.circular(28);
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return Container(
        width: 56,
        height: 56,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: AppColors.primaryBlue.withValues(alpha: 0.2),
            width: 2,
          ),
        ),
        child: CachedImage(
          photoUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _initialsBox(initials),
        ),
      );
    }
    return _initialsBox(initials);
  }

  Widget _initialsBox(String initials) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(28),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: AppTextStyles.titleMedium.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
    );
  }

  String _initialsFrom(String name) {
    final parts =
        name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

class _UrgentBannerCard extends StatelessWidget {
  const _UrgentBannerCard({required this.banner, required this.onDismiss});

  final UrgentBanner banner;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.red,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        banner.title,
                        style: AppTextStyles.titleSmall.copyWith(
                          color: AppColors.red,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (banner.conference?.isNotEmpty == true)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.red.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          banner.conference!.toUpperCase(),
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.red,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  banner.body,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: const Color.fromRGBO(26, 26, 46, 0.85),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: AppColors.red.withValues(alpha: 0.7),
            visualDensity: VisualDensity.compact,
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.unread, required this.onTap});

  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.white.withValues(alpha: 0.10),
                ),
              ),
              child: const Icon(
                Icons.notifications_none_rounded,
                color: AppColors.white,
                size: 22,
              ),
            ),
          ),
        ),
        if (unread > 0)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.red,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.darkNavy, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({
    required this.initials,
    required this.fullName,
    required this.followedCount,
    required this.photoUrl,
  });

  final String initials;
  final String fullName;
  final int followedCount;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: photoUrl == null ? AppColors.primaryGradient : null,
              color: photoUrl == null ? null : AppColors.lightGrey,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: photoUrl == null
                ? Text(
                    initials,
                    style: AppTextStyles.titleLarge.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      letterSpacing: 0.4,
                    ),
                  )
                : CachedImage(
                    photoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Text(
                      initials,
                      style: AppTextStyles.titleLarge.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleLarge.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.church_outlined,
                      size: 14,
                      color: Color.fromRGBO(26, 26, 46, 0.6),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        followedCount == 0
                            ? 'No church set yet'
                            : '$followedCount church${followedCount == 1 ? '' : 'es'} followed',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: const Color.fromRGBO(26, 26, 46, 0.65),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            color: Color.fromRGBO(26, 26, 46, 0.4),
          ),
        ],
      ),
    );
  }
}

class _HomeEventCard extends StatelessWidget {
  const _HomeEventCard({
    required this.event,
    required this.isGoing,
    required this.onTap,
  });

  final Event event;
  final bool isGoing;
  final VoidCallback onTap;

  static const _months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Stack(
                    children: [
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: _CoverImage(
                          url: event.coverPhotoUrl,
                          fallbackIcon: Icons.event,
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.45),
                                ],
                                stops: const [0.5, 1.0],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _months[event.eventDate.month - 1],
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.primaryBlue,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                  height: 1,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                event.eventDate.day.toString(),
                                style: AppTextStyles.headlineMedium.copyWith(
                                  color: AppColors.darkNavy,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  height: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isGoing)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.successGreen,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.check_circle,
                                  color: AppColors.white,
                                  size: 12,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'GOING',
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: AppColors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          event.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.titleMedium.copyWith(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(
                              Icons.place_outlined,
                              size: 11,
                              color: Color.fromRGBO(26, 26, 46, 0.6),
                            ),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                (event.location ?? '').isEmpty
                                    ? 'Location TBA'
                                    : event.location!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: const Color.fromRGBO(26, 26, 46, 0.6),
                                  fontSize: 10.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
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
}

class _HomeChurchTile extends StatelessWidget {
  const _HomeChurchTile({
    required this.church,
    required this.isFollowed,
    required this.onTap,
  });

  final Church church;
  final bool isFollowed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _CoverImage(
                  url: church.coverPhotoUrl,
                  fallbackIcon: Icons.church,
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.7),
                          ],
                          stops: const [0.45, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                if (church.isVerified)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.darkNavy.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.verified,
                        size: 14,
                        color: AppColors.goldAccent,
                      ),
                    ),
                  ),
                if (isFollowed)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.successGreen,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'FOLLOWING',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.white,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        church.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleMedium.copyWith(
                          color: AppColors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.place_outlined,
                            size: 11,
                            color: Color.fromRGBO(255, 255, 255, 0.85),
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              church.city.isEmpty
                                  ? 'Zimbabwe'
                                  : church.city,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: const Color.fromRGBO(
                                    255, 255, 255, 0.85),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
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
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({this.url, required this.fallbackIcon});

  final String? url;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Container(
        decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        child: Center(
          child: Icon(
            fallbackIcon,
            color: AppColors.white.withValues(alpha: 0.55),
            size: 42,
          ),
        ),
      );
    }
    return CachedImage(
      url!,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(
        decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        child: Center(
          child: Icon(
            fallbackIcon,
            color: AppColors.white.withValues(alpha: 0.55),
            size: 42,
          ),
        ),
      ),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: AppColors.lightGrey,
          alignment: Alignment.center,
          child: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
    );
  }
}

class _PrayersEmpty extends StatelessWidget {
  const _PrayersEmpty({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.volunteer_activism_outlined,
              color: AppColors.primaryBlue,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Be the first to share a prayer',
                  style: AppTextStyles.titleMedium.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Pray together with the community.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: const Color.fromRGBO(26, 26, 46, 0.6),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Open',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.white.withValues(alpha: 0.18),
            ),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: AppColors.white, size: 20),
        ),
      ),
    );
  }
}

class _CompactStatTile extends StatelessWidget {
  const _CompactStatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color.fromRGBO(26, 26, 46, 0.06),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: AppColors.primaryBlue),
              const SizedBox(width: 8),
              Text(
                value,
                style: AppTextStyles.titleMedium.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: const Color.fromRGBO(26, 26, 46, 0.6),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComposerEntry extends StatelessWidget {
  const _ComposerEntry({
    required this.photoUrl,
    required this.name,
    required this.onTap,
  });

  final String? photoUrl;
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty
        ? '?'
        : name.trim().substring(0, 1).toUpperCase();
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: const Color.fromRGBO(26, 26, 46, 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: photoUrl == null || photoUrl!.isEmpty
                    ? Text(
                        initial,
                        style: AppTextStyles.titleMedium.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      )
                    : CachedImage(
                        photoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Text(
                          initial,
                          style: AppTextStyles.titleMedium.copyWith(
                            color: AppColors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'What\'s on your mind?',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: const Color.fromRGBO(26, 26, 46, 0.55),
                    fontSize: 14,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: AppColors.primaryBlue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyTile extends StatelessWidget {
  const _EmptyTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color.fromRGBO(26, 26, 46, 0.08),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: const Color.fromRGBO(26, 26, 46, 0.45),
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTextStyles.titleMedium.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: const Color.fromRGBO(26, 26, 46, 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
