import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_version.dart';
import '../../models/advent_news_model.dart';
import '../../models/devotion_model.dart';
import '../../models/church_model.dart';
import '../../models/event_model.dart';
import '../../models/friendship_model.dart';
import '../../models/job_model.dart';
import '../../models/library_item_model.dart';
import '../../models/member_directory_model.dart';
import '../../models/message_model.dart';
import '../../models/post_model.dart';
import '../../models/prayer_model.dart';
import '../../models/product_model.dart';
import '../../models/story_model.dart';
import '../../services/advent_news_service.dart';
import '../../services/auth_service.dart';
import '../../services/cache_service.dart';
import '../../services/church_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/directory_service.dart';
import '../../services/gallery_service.dart';
import '../../services/devotion_service.dart';
import '../../services/event_service.dart';
import '../../services/feed_service.dart';
import '../../services/force_update_service.dart';
import '../../services/job_service.dart';
import '../../services/library_service.dart';
import '../../services/marketplace_service.dart';
import '../../services/messaging_service.dart';
import '../../services/notification_service.dart';
import '../../services/prayer_service.dart';
import '../../services/rating_prompt_service.dart';
import '../../services/sabbath_service.dart';
import '../../services/urgent_banner_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/ads/native_ad_card.dart';
import '../../widgets/home/advent_chat_bubble.dart';
import '../../widgets/screen_shell.dart';
import '../../widgets/home/comments_sheet.dart';
import '../../widgets/home/composer_sheet.dart';
import '../../widgets/home/featured_church_events.dart';
import '../../widgets/home/signup_survey_sheet.dart';
import '../../widgets/home/edit_post_dialog.dart';
import '../../widgets/home/invite_friends_card.dart';
import '../../widgets/home/post_card.dart';
import '../../widgets/home/post_image_viewer.dart';
import '../../widgets/job_card.dart';
import '../../widgets/product_card.dart';
import '../../widgets/home/report_sheet.dart';
import '../../widgets/home/stories_rail.dart';
import '../../widgets/home/live_banner.dart';
import '../../widgets/verified_tick.dart';
import '../../widgets/youtube/youtube_video_card.dart';
import '../../models/youtube_video.dart';
import '../../services/youtube_service.dart';
import '../../widgets/last_updated_strip.dart';
import '../../widgets/motion/content_reveal.dart';
import '../../widgets/motion/hide_on_scroll.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/motion/staggered_reveal.dart';
import '../../widgets/home/story_viewer.dart';
import '../../widgets/chat_contact_sheet.dart';
import '../../widgets/shimmer_loaders.dart';
import '../widgets/main_bottom_nav.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with NavVisibilityMixin {
  List<Event> _events = [];
  List<Church> _churches = [];
  List<MemberDirectoryEntry> _suggestedMembers = [];
  List<AdventNews> _topNews = const [];
  Devotion? _devotion;
  List<Prayer> _prayers = const [];
  Set<String> _followedChurchIds = <String>{};
  Set<String> _rsvpedEventIds = <String>{};
  int _unreadNotifications = 0;
  List<Post> _posts = [];
  List<Story> _stories = [];
  Set<String> _viewedStoryIds = const {};
  List<Product> _products = const [];
  List<Job> _jobs = const [];
  // Watch (YouTube): the current live stream for the LIVE banner + a page
  // of recent videos interleaved into the feed as individual cards.
  YoutubeVideo? _liveVideo;
  List<YoutubeVideo> _homeVideos = const [];
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
  // Realtime watcher on messages so the chat-bubble badge clears
  // when the user reads messages inside the chat and bounces back
  // here, and lights up when a new inbound message arrives without
  // requiring a manual pull-to-refresh. Debounced so a burst of
  // events doesn't hammer the inbox count query.
  StreamSubscription<List<Map<String, dynamic>>>? _msgActivitySub;
  Timer? _unreadRefreshDebounce;

  @override
  void initState() {
    super.initState();
    // (Entrance animation now lives in _buildScrollableContent's
    // StaggeredReveal sections — no screen-level controller needed.)
    // Today's devotion — paint the cached copy instantly (survives a slow /
    // offline open since the card is pinned to the top), then refresh.
    _devotion = DevotionService.cachedToday();
    DevotionService.fetchToday().then((d) {
      if (mounted && d != null) setState(() => _devotion = d);
    });
    // Paint the cached LIVE banner instantly (no late pop-in), then refresh.
    _liveVideo = YoutubeService.cachedLive();
    // Watch content — live stream + recent videos. Independent of the main
    // bootstrap so a slow YouTube read never delays the rest of Home.
    _loadWatch();
    _msgActivitySub = MessagingService.streamInboxActivity().listen((_) {
      _unreadRefreshDebounce?.cancel();
      _unreadRefreshDebounce = Timer(const Duration(milliseconds: 600), () {
        if (mounted) _refreshUnreadBadge();
      });
    }, onError: (_) {});
    // Rebuild whenever the user's profile metadata changes (e.g. after a
    // save in Edit Profile) so the greeting / welcome card refresh without
    // requiring the user to relaunch the app.
    _authSub = AuthService.authStateChanges.listen((_) {
      if (mounted) setState(() {});
    });
    _bootstrap();
    // A newer build is out but we're still inside the grace window — nudge
    // once per session (the splash already hard-blocks once grace expires).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeShowUpdateNudge();
    });
    // First-run welcome survey ("how did you hear about us"). One-shot, gated
    // locally; shown a moment after home settles so it doesn't fight the
    // update nudge for the screen.
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) SignupSurveySheet.maybeShow(context);
    });
    // Once home has settled, gently ask long-term users to rate the app.
    // Gated + best-effort; Google's native sheet handles "already rated".
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) RatingPromptService.maybeRequestReview();
    });
  }

  /// Dismissible "update available" prompt shown when ForceUpdateService
  /// flagged a newer build that's still inside its grace window. Shown at
  /// most once per app session; after the grace days elapse the splash
  /// gate hard-blocks instead.
  Future<void> _maybeShowUpdateNudge() async {
    if (ForceUpdateService.softPromptShownThisSession) return;
    final update = ForceUpdateService.last;
    if (update.level != UpdateLevel.recommended) return;
    ForceUpdateService.softPromptShownThisSession = true;
    if (!mounted) return;
    final days = update.daysLeft;
    final window = days <= 1 ? '1 day' : '$days days';
    final palette = context.palette;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(
              Icons.system_update,
              color: AppColors.primaryBlue,
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Update available',
                style: AppTextStyles.titleMedium.copyWith(
                  color: palette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'A newer version of Advent Connect is available. You have $window '
          'to update before it becomes required.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: palette.textMuted,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Later',
              style: AppTextStyles.buttonText.copyWith(
                color: palette.textMuted,
              ),
            ),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _openStore();
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Update now'),
          ),
        ],
      ),
    );
  }

  Future<void> _openStore() async {
    final market = Uri.parse('market://details?id=$kAndroidPackageId');
    final web = Uri.parse(
      'https://play.google.com/store/apps/details?id=$kAndroidPackageId',
    );
    if (!await launchUrl(market, mode: LaunchMode.externalApplication)) {
      await launchUrl(web, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _unreadRefreshDebounce?.cancel();
    _msgActivitySub?.cancel();
    super.dispose();
  }

  /// Lightweight refetch for the chat-bubble badge. Refreshes BOTH
  /// the unread-messages sum AND the pending-friend-request count
  /// — otherwise the badge stayed stuck on a stale total whenever
  /// the user accepted / declined requests from another screen and
  /// bounced back to home. Source of the "chat shows 6 but inbox
  /// is empty" complaint.
  Future<void> _refreshUnreadBadge() async {
    try {
      final results = await Future.wait([
        MessagingService.fetchConversations(),
        FeedService.pendingRequestCount(),
      ]);
      if (!mounted) return;
      final convos = results[0] as List<Conversation>;
      final pending = results[1] as int;
      var unread = 0;
      for (final c in convos) {
        unread += c.unreadCount;
      }
      setState(() {
        _unreadMessages = unread;
        _pendingFriendRequests = pending;
      });
    } catch (_) {
      // Silent — badge accuracy is best-effort.
    }
  }

  Future<void> _bootstrap() async {
    // Refresh Watch content (live banner + feed videos) on pull-to-refresh.
    unawaited(_loadWatch());
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
        // The pull-to-refresh nonce reshuffles the personalised
        // jitter so each refresh hands the user a visibly different
        // feed order, even on identical content. Without it the
        // sort was stable per session and refresh felt like a
        // no-op.
        FeedService.fetchFeed(
          refreshNonce: DateTime.now().millisecondsSinceEpoch,
        ),
        FeedService.fetchStories(),
        FeedService.fetchMyFriendships(),
        FeedService.pendingRequestCount(),
        MessagingService.fetchConversations(),
        AdventNewsService.fetchTopNews(limit: 3),
        PrayerService.fetchPrayers(),
        MarketplaceService.fetchProducts(),
        JobService.fetchJobs(),
        FeedService.fetchMyViewedStoryIds(),
      ]);
      if (!mounted) return;
      // Drop events whose start time is more than a few hours in the
      // past — `upcomingOnly: true` filters by start_date (date-only),
      // so today's already-ended events would otherwise still appear
      // on the home screen until midnight rolls over.
      final now = DateTime.now();
      final stillUpcoming = (results[0] as List<Event>)
          .where(
            (e) => e.startsAt.isAfter(now.subtract(const Duration(hours: 6))),
          )
          .toList();
      final events = stillUpcoming.take(8).toList();
      // Show a per-user RANDOM selection of churches (stable for a given user,
      // but different between users) instead of the same alphabetical first-6
      // for everyone — so smaller/newer churches also get discovered.
      final allChurches = List<Church>.of(results[1] as List<Church>);
      allChurches.shuffle(
        Random((AuthService.currentUser?.id ?? 'guest').hashCode),
      );
      final churches = allChurches.take(6).toList();
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
        _viewedStoryIds = results[16] as Set<String>;
        _friendshipsByUser = friendsByUser;
        _pendingFriendRequests = results[10] as int;
        _unreadMessages = unreadMessages;
        _topNews = results[12] as List<AdventNews>;
        _prayers = (results[13] as List<Prayer>).take(5).toList();
        _products = (results[14] as List<Product>).take(10).toList();
        _jobs = (results[15] as List<Job>).take(8).toList();
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
        // Cache stories too — testers reported the rail occasionally
        // rendering empty on a flaky fetch until a manual refresh.
        // Painting the last-known set first hides that gap.
        'stories': _stories.map((s) => s.toJson()).toList(),
        // Advent News card + the "N churches followed" stat — so they
        // paint instantly on launch instead of popping in after the fetch.
        'news': _topNews.map((n) => n.toJson()).toList(),
        'followedChurchIds': _followedChurchIds.toList(),
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
          .map(
            (p) => Post.fromJson(p as Map<String, dynamic>, viewerId: viewerId),
          )
          .toList();
      // Drop any cached stories that have since expired (24h window).
      final stories = ((decoded['stories'] as List?) ?? const [])
          .map((s) => Story.fromJson(s as Map<String, dynamic>))
          .where((s) => !s.isExpired)
          .toList();
      final news = ((decoded['news'] as List?) ?? const [])
          .map((n) => AdventNews.fromJson(n as Map<String, dynamic>))
          .toList();
      final followed = ((decoded['followedChurchIds'] as List?) ?? const [])
          .map((e) => e.toString())
          .toSet();
      if (!mounted) return;
      setState(() {
        if (_events.isEmpty) _events = events;
        if (_churches.isEmpty) _churches = churches;
        if (_posts.isEmpty) _posts = posts;
        if (_stories.isEmpty) _stories = stories;
        if (_topNews.isEmpty) _topNews = news;
        if (_followedChurchIds.isEmpty) _followedChurchIds = followed;
        // Paint instantly when cache hits — no spinner.
        if (events.isNotEmpty ||
            churches.isNotEmpty ||
            posts.isNotEmpty ||
            stories.isNotEmpty ||
            news.isNotEmpty) {
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

  bool get _hasUnreadChat => _unreadMessages > 0 || _pendingFriendRequests > 0;

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

  Future<void> _openStoryViewer(List<Story> reel) async {
    // Optimistically grey the ring for the reel we're opening, so it
    // doesn't keep showing as unviewed after you've seen it.
    setState(() {
      _viewedStoryIds = {..._viewedStoryIds, ...reel.map((s) => s.id)};
    });
    // The rail hands us a play-order (oldest-first) reel — including
    // auto-advance across unviewed authors — so show it as-is.
    await StoryViewer.show(context, reel);
    // Reconcile with the server when the viewer closes (covers reels you
    // exited early, or views from another device) so the ring is accurate.
    try {
      final ids = await FeedService.fetchMyViewedStoryIds();
      if (mounted) setState(() => _viewedStoryIds = ids);
    } catch (_) {}
  }

  List<Story> _storiesForAuthor(String authorId) =>
      _stories.where((s) => s.authorId == authorId).toList();

  bool _authorHasStory(String authorId) =>
      _stories.any((s) => s.authorId == authorId);

  /// The viewed set to paint rings with: this screen's loaded set unioned
  /// with the app-wide persisted cache, so rings stay correct before the
  /// load finishes and reflect stories watched from any other surface.
  Set<String> get _allViewedIds =>
      _viewedStoryIds.union(FeedService.viewedStoryIdsCached());

  /// True when EVERY active story by [authorId] has been watched — drives
  /// the post-card avatar ring. Derived from the persisted cache so it no
  /// longer forgets across app restarts.
  bool _authorStoryViewed(String authorId) {
    final stories = _storiesForAuthor(authorId);
    if (stories.isEmpty) return false;
    final viewed = _allViewedIds;
    return stories.every((s) => viewed.contains(s.id));
  }

  /// Quick profile preview (avatar tap on a post).
  void _previewAuthor(Post post) {
    final me = AuthService.currentUser?.id;
    if (post.authorId == me) {
      context.goNamed('profile');
      return;
    }
    showChatContactSheet(
      context,
      userId: post.authorId,
      fallbackName: post.authorName,
      fallbackPhotoUrl: post.authorPhotoUrl,
    );
  }

  /// Tapping a post author's story ring — view the story or the profile.
  Future<void> _onAuthorStoryRing(Post post) async {
    final stories = _storiesForAuthor(post.authorId);
    if (stories.isEmpty) {
      _previewAuthor(post);
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(
                Icons.auto_stories_outlined,
                color: AppColors.primaryBlue,
              ),
              title: const Text('View story'),
              onTap: () => Navigator.pop(ctx, 'story'),
            ),
            ListTile(
              leading: const Icon(
                Icons.person_outline,
                color: AppColors.primaryBlue,
              ),
              title: const Text('View profile'),
              onTap: () => Navigator.pop(ctx, 'profile'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'story') {
      // _storiesForAuthor is newest-first; play oldest-first.
      // _openStoryViewer greys the ring optimistically (via the shared
      // viewed cache) for both the rail AND this post-card avatar.
      await _openStoryViewer(stories.reversed.toList());
    } else if (choice == 'profile') {
      _openAuthorProfile(post);
    }
  }

  Future<void> _toggleLike(Post post) async {
    final newLiked = !post.viewerLiked;
    final newCount = (post.likeCount + (newLiked ? 1 : -1)).clamp(0, 1 << 30);
    setState(() {
      _posts = _posts
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
      // Revert on failure.
      setState(() {
        _posts = _posts
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
          _posts = _posts
              .map(
                (p) => p.id == post.id ? p.copyWith(commentCount: newCount) : p,
              )
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
      backgroundColor: context.palette.scaffoldBg,
      body: NotificationListener<UserScrollNotification>(
        onNotification: handleNavScroll,
        child: Stack(
          children: [
            _buildScrollableContent(),
            // Exactly one floating bubble: Advent Chat (with its unread
            // badge). The old Prayer quick-access bubble that stacked on top
            // was removed — Prayer is reached from the Stories section link
            // and the Prayer tab.
            Positioned(
              right: 16,
              bottom: 24,
              child: AdventChatBubble(
                hasUnread: _hasUnreadChat,
                unreadCount: _chatBadgeCount,
                onTap: () async {
                  await context.pushNamed('messages');
                  // Returning from the inbox refreshes the badge — covers the
                  // case where the user read every unread message inside the
                  // chat and the FAB would otherwise stay red until the next
                  // realtime activity event.
                  if (mounted) await _refreshUnreadBadge();
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: HideOnScroll(
        visible: navVisible,
        child: const MainBottomNav(
          currentIndex: 0,
          // No chat badge on the Profile tab — the floating Advent Chat
          // bubble (bottom-right) already surfaces unread counts, and
          // tapping Profile doesn't actually take the user to messages,
          // which made the badge misleading ("6 unread shown but
          // nothing in profile when I open it").
        ),
      ),
    );
  }

  Future<void> _loadWatch() async {
    final results = await Future.wait<Object?>([
      YoutubeService.fetchCurrentLive(),
      YoutubeService.fetchFeed(limit: 30),
    ]);
    if (!mounted) return;
    // Rotate the home video sample on each refresh so it doesn't look stale:
    // pull the latest ~30 and shuffle a fresh handful in.
    final pool = List<YoutubeVideo>.from(results[1] as List<YoutubeVideo>);
    pool.shuffle();
    setState(() {
      _liveVideo = results[0] as YoutubeVideo?;
      _homeVideos = pool.take(8).toList();
    });
  }

  void _openVideo(YoutubeVideo v) => context.pushNamed(
    'watch_video',
    pathParameters: {'id': v.videoId},
    extra: v,
  );

  Widget _buildScrollableContent() {
    // Staggered entrance: each section fades in and rises ~70ms after
    // the previous one, so Home assembles itself instead of appearing as
    // one block — this is the receiving end of the profile-setup
    // completion handoff.
    return BrandedRefreshIndicator(
      color: AppColors.primaryBlue,
      onRefresh: _bootstrap,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StaggeredReveal(index: 0, rise: 16, child: _buildHeader()),
            StaggeredReveal(
              index: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // LIVE now — collapses to nothing when no channel is live.
                  LiveBanner(live: _liveVideo, onTap: _openVideo),
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
                  // What's on your mind + Stories + Devotion always sit at
                  // the top, right under the header. Everything else (news,
                  // product pick, the feed) follows.
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _ComposerEntry(
                      photoUrl: _viewerPhotoUrl(),
                      name: _displayFullName(),
                      onTap: _openPostComposer,
                    ),
                  ),
                ],
              ),
            ),
            StaggeredReveal(
              index: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  _buildSectionHeader(
                    'Stories',
                    'Prayer',
                    onAction: () => context.pushNamed('prayer'),
                  ),
                  const SizedBox(height: 10),
                  StoriesRail(
                    stories: _stories,
                    viewerId: AuthService.currentUser?.id ?? '',
                    viewerName: _displayFullName(),
                    viewerPhotoUrl: _viewerPhotoUrl(),
                    onAddStory: _openStoryComposer,
                    onAuthorTapped: (_, list) => _openStoryViewer(list),
                    viewedStoryIds: _allViewedIds,
                  ),
                ],
              ),
            ),
            StaggeredReveal(
              index: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Devotion CARD depends on the network fetch — only show it
                  // when we have it.
                  if (_devotion != null) ...[
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _DevotionCard(
                        devotion: _devotion!,
                        onOpenLibrary: () => context.pushNamed('library'),
                      ),
                    ),
                  ],
                  // Library chips (Bible / Hymnal / EGW / Music) are static
                  // navigation — ALWAYS show them, even on poor network when
                  // the devotion fetch fails (previously they were nested in
                  // the devotion block and vanished with it).
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: _LibraryChips(),
                  ),
                ],
              ),
            ),
            // Official church-posted events, featured prominently with the
            // church's name + gold tick. Self-hides when there are none.
            const StaggeredReveal(
              index: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 16),
                  FeaturedChurchEvents(),
                  SizedBox(height: 6),
                ],
              ),
            ),
            // Advent News + Music now live INSIDE the shuffled discovery
            // feed (see _buildDiscoveryCards) so their position varies
            // per user instead of being pinned to the same spot here.
            // _buildFeedList() is now a Facebook-style mixed feed:
            // posts intercalated with discovery cards (suggested
            // people, events, prayer prompt, churches, invite
            // friends, quick stats). The standalone sections that
            // used to live below this point were folded into the
            // feed so the user gets one continuous scroll instead
            // of jumping between mode-locked panels.
            StaggeredReveal(index: 5, child: _buildFeedList()),
            const SizedBox(height: 24),
            // Bottom padding so the floating chat bubble + plus FAB
            // don't sit on top of the last bit of feed content.
            const SizedBox(height: 96),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    // Slim compact bar: avatar + greeting + Sabbath chip on a single navy
    // row. Replaces the old 240px header + floating welcome card, which
    // repeated the user's name three times and pushed Stories/Devotion down.
    final photoUrl = _profilePhotoUrl();
    return FlatStatusBar(
      child: Container(
        color: context.palette.scaffoldBg,
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
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 26),
                child: Row(
                  children: [
                    // Tapping the avatar jumps to the profile screen — same
                    // affordance the old welcome card had.
                    GestureDetector(
                      onTap: () => context.goNamed('profile'),
                      child: Container(
                        width: 46,
                        height: 46,
                        clipBehavior: Clip.antiAlias,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          shape: BoxShape.circle,
                        ),
                        child: photoUrl == null
                            ? Text(
                                _initials(),
                                style: AppTextStyles.titleLarge.copyWith(
                                  color: AppColors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              )
                            : CachedImage(
                                photoUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    Text(
                                      _initials(),
                                      style: AppTextStyles.titleLarge.copyWith(
                                        color: AppColors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _greeting().toUpperCase(),
                            style: AppTextStyles.labelSmall.copyWith(
                              color: context.palette.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Hello, ${_firstName()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.headlineLarge.copyWith(
                              color: context.palette.text,
                              fontSize: 20,
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
              onTap: () => context.pushNamed('events'),
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
    // Skeleton crossfades into content — no pop-in from blank.
    return ContentReveal(
      loading: _loading && _events.isEmpty,
      skeleton: SizedBox(height: 200, child: ShimmerLoaders.cardList(count: 2)),
      child: _buildEventsRowContent(),
    );
  }

  Widget _buildEventsRowContent() {
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
        separatorBuilder: (context, index) => const SizedBox(width: 12),
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

  Widget _buildPrayersStrip() {
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _prayers.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final p = _prayers[i];
          return _PrayerHomeCard(
            prayer: p,
            onTap: () => context.pushNamed(
              'prayer_details',
              pathParameters: {'id': p.id},
              extra: p,
            ),
          );
        },
      ),
    );
  }

  /// Horizontal rail of marketplace products for the mixed home feed.
  /// ProductCard is built to stretch in a grid, so each is width-boxed
  /// to behave like the events / prayers rails.
  Widget _buildProductsRow() {
    return SizedBox(
      height: 252,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _products.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final p = _products[i];
          return SizedBox(
            width: 168,
            child: ProductCard(
              product: p,
              onTap: () => context.pushNamed(
                'product_details',
                pathParameters: {'id': p.id},
                extra: p,
              ),
            ),
          );
        },
      ),
    );
  }

  /// Horizontal rail of open job listings for the mixed home feed.
  Widget _buildJobsRow() {
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _jobs.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final j = _jobs[i];
          return SizedBox(
            width: 290,
            child: JobCard(
              job: j,
              onTap: () => context.pushNamed(
                'job_details',
                pathParameters: {'id': j.id},
                extra: j,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChurchGrid() {
    return ContentReveal(
      loading: _loading && _churches.isEmpty,
      skeleton: SizedBox(height: 160, child: ShimmerLoaders.cardList(count: 2)),
      child: _buildChurchGridContent(),
    );
  }

  Widget _buildChurchGridContent() {
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
        separatorBuilder: (context, index) => const SizedBox(width: 12),
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
    // Shimmering post-shaped skeletons (avatar + name + tall media
    // block) that crossfade into the real feed — replaces the old flat
    // grey boxes that snapped to content.
    return ContentReveal(
      loading: _loading && _posts.isEmpty,
      skeleton: ShimmerLoaders.postColumn(count: 2),
      child: _buildFeedListContent(),
    );
  }

  Widget _buildFeedListContent() {
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
              color: context.palette.textMuted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }
    final viewerId = AuthService.currentUser?.id;
    final cachedAt = CacheService.cachedAt('home_feed');
    final discoveryCards = _buildDiscoveryCards();
    // Shuffle with a per-account seed so the discovery cards (incl. the
    // marketplace pick) land in a stable-but-varied order per user instead
    // of the marketplace pick always being last (tester: "mix it up").
    if (discoveryCards.length > 1) {
      discoveryCards.shuffle(Random((viewerId ?? 'x').hashCode));
    }

    // Facebook-style mixed feed: real posts intercalated with discovery
    // cards (suggested people / events / churches / prayer prompt /
    // invite friends / quick stats). One discovery card after every
    // [_discoveryEveryNPosts] posts, then any remaining cards are
    // appended at the end so the user always sees the full set even
    // when the post backlog is short.
    final children = <Widget>[];
    if (cachedAt != null) {
      children.add(const SizedBox(height: 4));
      children.add(
        LastUpdatedStrip(
          timestamp: cachedAt,
          isOnline: ConnectivityService.isOnline,
          onRefresh: _bootstrap,
        ),
      );
    }
    var cardIdx = 0;
    var adsInserted = 0;
    var videoIdx = 0;
    for (var i = 0; i < _posts.length; i++) {
      final post = _posts[i];
      children.add(
        PostCard(
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
          onAuthorAvatarTapped: () => _previewAuthor(post),
          hasStory: _authorHasStory(post.authorId),
          storyViewed: _authorStoryViewed(post.authorId),
          onStoryRingTapped: () => _onAuthorStoryRing(post),
          onSaveImage: () => _savePostImage(post),
        ),
      );
      if ((i + 1) % _discoveryEveryNPosts == 0 &&
          cardIdx < discoveryCards.length) {
        children.add(discoveryCards[cardIdx++]);
      }
      // Individual YouTube video cards from Watch, interleaved into the
      // feed (one at a time, paced) — tap opens the in-app player.
      if ((i + 1) % _videoEveryNPosts == 0 && videoIdx < _homeVideos.length) {
        final v = _homeVideos[videoIdx++];
        children.add(YoutubeVideoCard(video: v, onTap: () => _openVideo(v)));
      }
      // Sponsored native ad after every _adEveryNPosts posts, capped at
      // _maxFeedAds per render so we don't fire dozens of ad requests on
      // a long scroll. The card self-hides until/unless an ad loads.
      if ((i + 1) % _adEveryNPosts == 0 && adsInserted < _maxFeedAds) {
        children.add(const NativeAdCard());
        adsInserted++;
      }
    }
    while (cardIdx < discoveryCards.length) {
      children.add(discoveryCards[cardIdx++]);
    }
    // Append any remaining videos so they still surface when the post
    // backlog is short.
    while (videoIdx < _homeVideos.length) {
      final v = _homeVideos[videoIdx++];
      children.add(YoutubeVideoCard(video: v, onTap: () => _openVideo(v)));
    }
    return Column(children: children);
  }

  // Cadence for the Facebook-style mixed feed. Smaller = more
  // discovery cards interrupting posts; larger = posts feel more
  // continuous. 3 lands close to what Instagram does for sponsored
  // breakers.
  static const _discoveryEveryNPosts = 3;

  // Cadence for individual YouTube video cards interleaved into the feed.
  static const _videoEveryNPosts = 4;

  // Sponsored native-ad cadence in the home feed. First ad after ~6 posts,
  // then every 6, capped per render so a long scroll doesn't spawn dozens
  // of ad requests.
  static const _adEveryNPosts = 6;
  static const _maxFeedAds = 4;

  /// Maps an onboarding-interest label (the user-facing strings from
  /// _PersonalizationPage._interestOptions) to the discovery slot
  /// keys it should boost. Unknown labels yield an empty list so the
  /// neutral per-viewer shuffle still picks an order for them.
  static List<String> _interestToSlotKeys(String label) {
    switch (label) {
      case 'Events':
        return const ['events'];
      case 'Prayer requests':
        return const ['prayers'];
      case 'Church announcements':
        return const ['churches'];
      case 'Youth content':
      case 'Evangelism':
      case 'Music':
        // Social-leaning interests rank "people to meet" higher.
        return const ['people'];
      default:
        return const [];
    }
  }

  /// Builds the discovery-card pool and shuffles it deterministically
  /// per viewer. Same content, different order per account — so two
  /// users on the same data don't see identical feeds. Invite + Quick
  /// stats are pinned to the end (they're filler / always-show items,
  /// not discovery) so the personalized portion stays at the top of
  /// the interspersed slots where it has the most impact.
  List<Widget> _buildDiscoveryCards() {
    final discoverable = <_DiscoverySlot>[];
    // Advent News + Music live in the shuffled pool so their position
    // varies per user (no longer pinned to a fixed spot up top).
    if (_topNews.isNotEmpty) {
      discoverable.add(
        _DiscoverySlot(
          key: 'news',
          widget: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: _AdventNewsHero(items: _topNews),
          ),
        ),
      );
    }
    discoverable.add(
      const _DiscoverySlot(key: 'music', widget: _HomeMusicStrip()),
    );
    if (_hasNonFriendSuggestions) {
      discoverable.add(
        _DiscoverySlot(
          key: 'people',
          widget: _discoverySection(
            title: 'People to meet',
            child: _buildSuggestedMembersRow(),
          ),
        ),
      );
    }
    if (_events.isNotEmpty) {
      discoverable.add(
        _DiscoverySlot(
          key: 'events',
          widget: _discoverySection(
            title: 'Upcoming events',
            action: 'See all',
            onAction: () => context.pushNamed('events'),
            child: _buildEventsRow(),
          ),
        ),
      );
    }
    discoverable.add(
      _DiscoverySlot(
        key: 'prayers',
        widget: _discoverySection(
          title: 'Active prayers',
          action: _prayers.isEmpty ? null : 'See all',
          onAction: _prayers.isEmpty ? null : () => context.pushNamed('prayer'),
          child: _prayers.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _PrayersEmpty(
                    onTap: () => context.pushNamed('prayer'),
                  ),
                )
              : _buildPrayersStrip(),
        ),
      ),
    );
    if (_products.isNotEmpty) {
      discoverable.add(
        _DiscoverySlot(
          key: 'product_pick',
          widget: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _FeaturedProductCard(
              product: _products.first,
              onTap: () => context.pushNamed(
                'product_details',
                pathParameters: {'id': _products.first.id},
                extra: _products.first,
              ),
            ),
          ),
        ),
      );
    }
    if (_churches.isNotEmpty) {
      discoverable.add(
        _DiscoverySlot(
          key: 'churches',
          widget: _discoverySection(
            title: 'Discover churches',
            action: 'See all',
            onAction: () => context.goNamed('churches'),
            child: _buildChurchGrid(),
          ),
        ),
      );
    }
    if (_products.isNotEmpty) {
      discoverable.add(
        _DiscoverySlot(
          key: 'marketplace',
          widget: _discoverySection(
            title: 'From the marketplace',
            action: 'See all',
            onAction: () => context.goNamed('marketplace'),
            child: _buildProductsRow(),
          ),
        ),
      );
    }
    if (_jobs.isNotEmpty) {
      discoverable.add(
        _DiscoverySlot(
          key: 'jobs',
          widget: _discoverySection(
            title: 'Jobs & opportunities',
            action: 'See all',
            onAction: () => context.goNamed('jobs'),
            child: _buildJobsRow(),
          ),
        ),
      );
    }
    // Stable per-viewer shuffle, weighted by onboarding interests so
    // the rails the user said they wanted ("Show me more of Events /
    // Prayer requests / Church announcements" in the onboarding
    // personalization page) rise to the top. Cards the user didn't
    // pick still appear, just lower. Within the same priority bucket
    // we fall back to the previous viewer-deterministic shuffle so
    // two users with identical interests still see different orders.
    final viewerId = AuthService.currentUser?.id ?? '';
    final meta = AuthService.currentUser?.userMetadata ?? const {};
    final rawInterests = (meta['interests'] as List?) ?? const [];
    final interestKeys = <String>{
      for (final i in rawInterests)
        ..._interestToSlotKeys((i ?? '').toString()),
    };
    discoverable.sort((a, b) {
      final aWanted = interestKeys.contains(a.key) ? 0 : 1;
      final bWanted = interestKeys.contains(b.key) ? 0 : 1;
      if (aWanted != bWanted) return aWanted.compareTo(bWanted);
      final seedA = '${viewerId}_${a.key}'.hashCode;
      final seedB = '${viewerId}_${b.key}'.hashCode;
      return seedA.compareTo(seedB);
    });
    return [
      for (final slot in discoverable) slot.widget,
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: InviteFriendsCard(),
      ),
      _discoverySection(title: 'Quick stats', child: _buildQuickStats()),
    ];
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
      final updated = await FeedService.updatePost(
        post.id,
        visibility: newVisibility,
      );
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
    final newBody = await showEditPostDialog(
      context,
      initialBody: post.body ?? '',
    );
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
        separatorBuilder: (context, index) => const SizedBox(width: 12),
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
                    _pendingFriendRequests = (_pendingFriendRequests - 1).clamp(
                      0,
                      1 << 30,
                    );
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
                AppColors.goldAccent,
                AppColors.goldAccent.withValues(alpha: 0.80),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.goldAccent.withValues(alpha: 0.9),
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.auto_awesome,
                size: 13,
                color: AppColors.darkNavy,
              ),
              const SizedBox(width: 6),
              Text(
                'Happy Sabbath',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.darkNavy,
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
          color: AppColors.goldAccent.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.goldAccent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.brightness_3,
              size: 13,
              color: AppColors.darkNavy,
            ),
            const SizedBox(width: 6),
            Text(
              'Sabbath in ${_format(remaining)}',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.darkNavy,
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
      color: context.palette.card,
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      child: InkWell(
        onTap: onOpenProfile,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
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
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              _MemberAvatar(photoUrl: entry.profilePhotoUrl, name: name),
              const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  if (entry.isVerified) const VerifiedTick(size: 13),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(
                  color: context.palette.textMuted,
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
    return PressEffect(
      child: Material(
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
    return PressEffect(
      child: Material(
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
          errorBuilder: (context, error, stackTrace) => _initialsBox(initials),
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
    final parts = name
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
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
                    color: context.palette.text,
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
    return PressEffect(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Circular frosted chip — matches the search button so the
          // header icons read as one family.
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? context.palette.cardMuted
                      : const Color(0xFFE4E9F2),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.notifications_none_rounded,
                  color: context.palette.text,
                  size: 21,
                ),
              ),
            ),
          ),
          if (unread > 0)
            Positioned(
              top: -3,
              right: -3,
              child: Container(
                constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: AppColors.red,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.palette.scaffoldBg, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
              ),
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
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];

  @override
  Widget build(BuildContext context) {
    return PressEffect(
      child: SizedBox(
        width: 160,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                color: context.palette.card,
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
                              color: AppColors.surface,
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
                              Icon(
                                Icons.place_outlined,
                                size: 11,
                                color: context.palette.textMuted,
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
                                    color: context.palette.textMuted,
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
    return PressEffect(
      child: Material(
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
                                church.city.isEmpty ? 'Zimbabwe' : church.city,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: const Color.fromRGBO(
                                    255,
                                    255,
                                    255,
                                    0.85,
                                  ),
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
      errorBuilder: (context, error, stackTrace) => Container(
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
          color: context.palette.cardMuted,
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

class _PrayerHomeCard extends StatelessWidget {
  const _PrayerHomeCard({required this.prayer, required this.onTap});

  final Prayer prayer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final author = prayer.authorName.trim().isNotEmpty
        ? prayer.authorName.trim()
        : 'A member';
    return PressEffect(
      child: SizedBox(
        width: 260,
        child: Material(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.front_hand_outlined,
                          size: 18,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.titleMedium.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Text(
                      prayer.content,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: context.palette.textMuted,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.favorite_outline,
                        size: 14,
                        color: AppColors.primaryBlue,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${prayer.prayerCount} praying',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: context.palette.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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

class _PrayersEmpty extends StatelessWidget {
  const _PrayersEmpty({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
                    color: context.palette.textMuted,
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
    return PressEffect(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? context.palette.cardMuted
                  : const Color(0xFFE4E9F2),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: context.palette.text, size: 20),
          ),
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
    return PressEffect(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: context.palette.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.palette.divider),
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
                    color: context.palette.text,
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
                      color: context.palette.textMuted,
                      fontSize: 11.5,
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
    return PressEffect(
      child: Material(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: context.palette.card,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: context.palette.divider),
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
                          errorBuilder: (context, error, stackTrace) => Text(
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
                      color: context.palette.textMuted,
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
        color: context.palette.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.palette.divider),
      ),
      child: Row(
        children: [
          Icon(icon, color: context.palette.textMuted, size: 28),
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
                    color: context.palette.textMuted,
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

/// Pairs a discovery card widget with a stable `key` so the
/// per-viewer shuffle is reproducible. Two users hash the same
/// pool differently, but the same user sees the same order on
/// every rebuild (no jumpy reshuffle).
class _DiscoverySlot {
  const _DiscoverySlot({required this.key, required this.widget});
  final String key;
  final Widget widget;
}

/// Magazine-style hero for the editorial Advent News feed. Renders
/// the top news item with cover photo + title + summary and links
/// out to /news for the full list. Pinned at the very top of the
/// home feed so members see "what's trending in the Adventist
/// community in Zimbabwe" before scrolling through user posts.
/// Home card: today's devotion — a KJV verse + an Ellen G. White quote.
/// The whole card is tappable and opens the Library (Bible tab).
class _DevotionCard extends StatelessWidget {
  const _DevotionCard({required this.devotion, required this.onOpenLibrary});
  final Devotion devotion;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpenLibrary,
      child: Container(
        width: double.infinity,
        // Slightly tighter than before (14/12) — the card was tall
        // enough to collide with the floating prayer bubble.
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: AppColors.appBarGradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: AppColors.darkNavy.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.auto_stories_outlined,
                  color: AppColors.goldAccent,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  "TODAY'S DEVOTION",
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.goldAccent,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              '"${devotion.bibleText}"',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.white,
                height: 1.45,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              devotion.bibleRef,
              style: AppTextStyles.labelMedium.copyWith(
                color: AppColors.white.withValues(alpha: 0.85),
                fontWeight: FontWeight.w700,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Divider(
                color: AppColors.white.withValues(alpha: 0.18),
                height: 1,
              ),
            ),
            Text(
              devotion.egwQuote,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.white.withValues(alpha: 0.92),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '— Ellen G. White, ${devotion.egwSource}',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.white.withValues(alpha: 0.7),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Premium launcher chips under the devotion card → open the Library to a
/// specific tab (0=Bible, 1=Hymnal, 2=EGW, 3=Music).
class _LibraryChips extends StatelessWidget {
  const _LibraryChips();

  // Tab index, or -1 for the Bible Quiz (its own /quiz route).
  static const _items = <(String, IconData, int)>[
    ('Bible', Icons.menu_book_rounded, 0),
    ('Hymnal', Icons.queue_music_rounded, 1),
    ('EGW', Icons.auto_stories_rounded, 2),
    ('Music', Icons.headphones_rounded, 3),
    ('Quiz', Icons.quiz_rounded, -1),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        for (var i = 0; i < _items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: PressEffect(
              pressedScale: 0.93,
              child: GestureDetector(
                onTap: () => _items[i].$3 == -1
                    ? context.pushNamed('quiz')
                    : context.pushNamed('library', extra: _items[i].$3),
                // Compact chips (12->9 vertical, smaller icon/label) so
                // the Library row doesn't crowd the prayer bubble.
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: palette.card,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: palette.divider),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _items[i].$2,
                        color: AppColors.primaryBlue,
                        size: 19,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _items[i].$1,
                        style: AppTextStyles.labelSmall.copyWith(
                          fontWeight: FontWeight.w700,
                          color: palette.text,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Horizontal strip of recent Library music on the home feed. Hidden when
/// there's no music yet. Tapping opens the Library Music tab.
class _HomeMusicStrip extends StatefulWidget {
  const _HomeMusicStrip();

  @override
  State<_HomeMusicStrip> createState() => _HomeMusicStripState();
}

class _HomeMusicStripState extends State<_HomeMusicStrip> {
  List<LibraryItem> _items = const [];

  @override
  void initState() {
    super.initState();
    LibraryService.fetchItems('music').then((m) {
      if (mounted) setState(() => _items = m.take(10).toList());
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              const Icon(
                Icons.headphones_rounded,
                color: AppColors.primaryBlue,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Music',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.pushNamed('library', extra: 3),
                child: Text(
                  'See all',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 152,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final item = _items[i];
              return GestureDetector(
                onTap: () => context.pushNamed('library', extra: 3),
                child: Container(
                  width: 130,
                  decoration: BoxDecoration(
                    color: palette.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: palette.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                        child: SizedBox(
                          height: 96,
                          width: double.infinity,
                          child:
                              (item.coverUrl != null &&
                                  item.coverUrl!.isNotEmpty)
                              ? CachedImage(item.coverUrl!, fit: BoxFit.cover)
                              : const DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: AppColors.primaryGradient,
                                  ),
                                  child: Icon(
                                    Icons.music_note_rounded,
                                    color: AppColors.white,
                                    size: 34,
                                  ),
                                ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.labelMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              color: palette.text,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// A single random marketplace product, showcased on Home (separate from
/// the products discovery row). Tapping opens the product.
class _FeaturedProductCard extends StatelessWidget {
  const _FeaturedProductCard({required this.product, required this.onTap});
  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final img = product.firstImage;
    return Material(
      color: context.palette.card,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            SizedBox(
              width: 104,
              height: 104,
              child: img.isNotEmpty
                  ? CachedImage(img, fit: BoxFit.cover)
                  : Container(
                      color: AppColors.primaryBlue.withValues(alpha: 0.10),
                      child: const Icon(
                        Icons.shopping_bag_outlined,
                        color: AppColors.primaryBlue,
                      ),
                    ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MARKETPLACE PICK',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.goldAccent,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.formatPrice(),
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(
                Icons.chevron_right,
                color: context.palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdventNewsHero extends StatefulWidget {
  const _AdventNewsHero({required this.items});

  final List<AdventNews> items;

  @override
  State<_AdventNewsHero> createState() => _AdventNewsHeroState();
}

class _AdventNewsHeroState extends State<_AdventNewsHero> {
  final PageController _pc = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items.take(5).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Material(
      color: context.palette.card,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 8.5,
            child: PageView.builder(
              controller: _pc,
              itemCount: items.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => _card(context, items[i]),
            ),
          ),
          _footer(context, items.length),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, AdventNews item) {
    final hasCover = (item.coverPhotoUrl ?? '').isNotEmpty;
    return InkWell(
      onTap: () => context.pushNamed(
        'news_details',
        pathParameters: {'id': item.id},
        extra: item,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasCover)
            CachedImage(item.coverPhotoUrl!, fit: BoxFit.cover)
          else
            const DecoratedBox(
              decoration: BoxDecoration(gradient: AppColors.appBarGradient),
              child: Center(
                child: Icon(Icons.newspaper, color: AppColors.white, size: 48),
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
                      Colors.black.withValues(alpha: 0.15),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.65),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.goldAccent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bolt, color: AppColors.darkNavy, size: 12),
                  const SizedBox(width: 4),
                  Text(
                    'ADVENT NEWS',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.darkNavy,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                item.category.label.toUpperCase(),
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.headlineSmall.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.white.withValues(alpha: 0.88),
                    height: 1.35,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context, int count) {
    return InkWell(
      onTap: () => context.pushNamed('news'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            for (int i = 0; count > 1 && i < count; i++)
              Container(
                width: i == _page ? 16 : 6,
                height: 6,
                margin: const EdgeInsets.only(right: 3),
                decoration: BoxDecoration(
                  color: i == _page
                      ? AppColors.primaryBlue
                      : context.palette.divider,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            const Spacer(),
            Text(
              'See all',
              style: AppTextStyles.labelMedium.copyWith(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
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
    );
  }
}
