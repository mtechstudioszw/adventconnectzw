import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show FloatingHeaderSnapConfiguration;
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
import '../../theme/app_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/ads/native_ad_card.dart';
import '../../widgets/premium/premium_promo_sheet.dart';
import '../../widgets/home/comments_sheet.dart';
import '../../widgets/home/composer_entry.dart';
import '../../widgets/home/composer_sheet.dart';
import '../../widgets/home/create_sheet.dart';
import '../../widgets/home/featured_church_events.dart';
import '../../widgets/home/home_header.dart';
import '../../widgets/home/library_tiles.dart';
import '../../widgets/home/music_card.dart';
import '../../widgets/home/section_header.dart';
import '../../widgets/home/signup_survey_sheet.dart';
import '../../widgets/home/edit_post_dialog.dart';
import '../../widgets/home/invite_friends_card.dart';
import '../../widgets/home/post_card.dart';
import '../../widgets/home/today_card.dart';
import '../../widgets/home/post_image_viewer.dart';
import '../../widgets/job_card.dart';
import '../../widgets/marketplace/product_tile.dart';
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
import '../../widgets/inline_action.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with NavVisibilityMixin, TickerProviderStateMixin {
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
  // Individual tracks interleaved into the feed, one card each.
  List<LibraryItem> _music = const [];
  // Watch (YouTube): every currently-live stream for the LIVE banner (it is
  // a swipeable deck when more than one channel is on air) + a page of recent
  // videos interleaved into the feed as individual cards.
  List<YoutubeVideo> _liveVideos = const [];
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
  // "People you may meet" cards swiped away this session. In memory only,
  // for the same reason as the banners: "not now" isn't "never", and
  // persisting it would need a table for a decision that costs one tap.
  final Set<String> _dismissedSuggestionIds = <String>{};
  // Friend requests currently in flight, so the card's Add shows a
  // spinner instead of accepting a second tap.
  final Set<String> _addingFriendIds = <String>{};
  bool _loading = true;

  // ---- Endless scroll ----------------------------------------------------
  // Wi-Fi loads forever; on mobile data we auto-load [_autoPagesOnCellular]
  // pages and then wait for an explicit tap, so an idle scroll can't quietly
  // eat someone's bundle. Same principle as Watch's "Wi-Fi only previews".
  static const int _pageSize = 15;
  static const int _autoPagesOnCellular = 2;
  final ScrollController _scroll = ScrollController();

  /// True once the greeting has scrolled out of the way, which swaps the
  /// header to the compact "Advent Connect ZW" bar.
  ///
  /// Hysteresis on purpose: it turns ON above 190 and OFF below 130, so a
  /// finger resting near the boundary can't flap the title back and forth.
  /// Both bounds sit above the header's own 96dp collapse range, so the
  /// extent change happens while the header is off-screen and invisible.
  bool _headerBranded = false;
  static const double _brandOnOffset = 190;
  static const double _brandOffOffset = 130;

  /// Lets a small scroll-up settle the floating header fully open rather
  /// than stranding it half-revealed.
  late final FloatingHeaderSnapConfiguration _headerSnap =
      FloatingHeaderSnapConfiguration(
    curve: AppMotion.easeOut,
    duration: const Duration(milliseconds: 220),
  );
  bool _loadingMore = false;
  bool _endOfFeed = false;
  int _pagesLoaded = 0;

  /// Batches "I've seen this" writes. A card marks itself locally as it
  /// builds; this flushes the whole buffer in one request a few seconds
  /// later, so a fast scroll past 30 posts costs one round-trip, not 30.
  Timer? _seenFlush;

  /// True once we've auto-loaded our cellular allowance and need a tap.
  bool get _needsManualLoad =>
      !ConnectivityService.isWifi && _pagesLoaded >= _autoPagesOnCellular;

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
    // Paint cached unread badges instantly so the notification bell + chat
    // bubble don't flash 0 → n on every open. Refreshed by the loads below.
    _hydrateBadgesFromCache();
    // Keep the suggestion cards' Add / Requested / Friends state honest
    // when a friendship changes on another screen.
    FeedService.friendshipsChanged.addListener(_onFriendshipsChanged);
    // Today's devotion — paint the cached copy instantly (survives a slow /
    // offline open since the card is pinned to the top), then refresh.
    _devotion = DevotionService.cachedToday();
    DevotionService.fetchToday().then((d) {
      if (mounted && d != null) setState(() => _devotion = d);
    });
    // Paint the cached LIVE banner instantly (no late pop-in), then refresh.
    _liveVideos = YoutubeService.cachedLiveNow();
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
    // The premium promo, last in the queue and latest of all the
    // delays: PremiumPromoService caps it at once per fortnight and
    // refuses outright if any other sheet is still up, so being last
    // costs nothing and guarantees it never talks over the others.
    Future.delayed(const Duration(seconds: 6), () {
      if (mounted) PremiumPromoSheet.maybeShow(context);
    });
    // "Finish your profile" nudge. The RPC re-checks completeness and
    // won't fire more than once a fortnight, so this is safe to call on
    // every launch and needs no local flag.
    unawaited(NotificationService.maybeNudgeProfileIncomplete());
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
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
                borderRadius: BorderRadius.circular(AppRadius.button),
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

  /// Re-read every friendship the viewer is party to, so a card that
  /// says "Requested" stops saying it the moment the request is accepted
  /// — wherever that happened.
  Future<void> _onFriendshipsChanged() async {
    if (!mounted) return;
    try {
      final links = await FeedService.fetchMyFriendships();
      if (!mounted) return;
      final me = AuthService.currentUser?.id;
      setState(() {
        _friendshipsByUser = {
          for (final f in links)
            (f.requesterId == me ? f.addresseeId : f.requesterId): f,
        };
      });
    } catch (_) {
      // The next full refresh will reconcile it.
    }
  }

  @override
  void dispose() {
    FeedService.friendshipsChanged.removeListener(_onFriendshipsChanged);
    _authSub?.cancel();
    _unreadRefreshDebounce?.cancel();
    _msgActivitySub?.cancel();
    _seenFlush?.cancel();
    // Leaving Home shouldn't lose the buffer — flush what's pending.
    unawaited(FeedService.flushSeen());
    _scroll.dispose();
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
      _cacheBadges();
    } catch (_) {
      // Silent — badge accuracy is best-effort.
    }
  }

  static const _badgeCacheKey = 'home_badges_v1';

  /// Paint the last-known unread counts instantly on the next home open so the
  /// bell + chat bubble don't flash 0 first. Cleared on sign-out with the rest
  /// of the user cache.
  void _hydrateBadgesFromCache() {
    final raw = CacheService.readStringStale(_badgeCacheKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _unreadNotifications = (m['n'] as num?)?.toInt() ?? 0;
      _unreadMessages = (m['m'] as num?)?.toInt() ?? 0;
      _pendingFriendRequests = (m['r'] as num?)?.toInt() ?? 0;
    } catch (_) {
      // Corrupt cache — ignore; the live load will set the real counts.
    }
  }

  void _cacheBadges() {
    unawaited(CacheService.writeString(
      _badgeCacheKey,
      jsonEncode({
        'n': _unreadNotifications,
        'm': _unreadMessages,
        'r': _pendingFriendRequests,
      }),
    ));
  }

  /// Loads Home in tiers instead of one 17-call `Future.wait`.
  ///
  /// The old version awaited every endpoint before a single `setState`, so
  /// one slow query (jobs, marketplace) held the entire screen hostage and
  /// everything painted at once or not at all. Now:
  ///
  ///   cache  → paints instantly, offline included
  ///   tier 0 → the tiny social sets the feed ranking needs
  ///   tier 1 → feed + stories + badges; clears the skeleton
  ///   tier 2 → discovery rails, each landing into its own section
  ///
  /// Tier 2 failures are swallowed per-tier: a dead marketplace must never
  /// blank the feed.
  Future<void> _bootstrap() async {
    // Refresh Watch content (live banner + feed videos) on pull-to-refresh.
    unawaited(_loadWatch());
    // Always hydrate from cache first so the screen paints real
    // content immediately, before the network call resolves.
    // Facebook-style: see something instantly, then silently refresh.
    if (_loading) {
      _hydrateFromCache();
    }
    // A refresh restarts pagination — otherwise "load more" would keep
    // paging from the old cursor into content the new sort already returned.
    _pagesLoaded = 0;
    _endOfFeed = false;

    final viewerId = AuthService.currentUser?.id;
    await _loadCritical(viewerId);
    if (!mounted) return;
    unawaited(_loadSecondary(viewerId));
  }

  /// Tier 0 + 1. Awaited, because it owns the skeleton→content moment.
  Future<void> _loadCritical(String? viewerId) async {
    try {
      // Tier 0: the two small queries the ranking needs. Cheap, and the
      // cache is already on screen while they run.
      final social = await Future.wait([
        FeedService.fetchMyFriendships(),
        ChurchService.fetchUserFollowedChurchIds(),
      ]);
      if (!mounted) return;
      final friendships = social[0] as List<Friendship>;
      final followedChurchIds = social[1] as Set<String>;
      final friendsByUser = <String, Friendship>{};
      final friendIds = <String>{};
      if (viewerId != null) {
        for (final f in friendships) {
          final other = f.otherUserId(viewerId);
          friendsByUser[other] = f;
          if (f.isAccepted) friendIds.add(other);
        }
      }

      // Seen history has to land BEFORE the feed request, because the
      // ranking reads it synchronously while sorting.
      await FeedService.fetchSeenPostIds();
      if (!mounted) return;

      // Tier 1: what the user actually came for.
      final results = await Future.wait([
        // The pull-to-refresh nonce reshuffles the personalised
        // jitter so each refresh hands the user a visibly different
        // feed order, even on identical content. Without it the
        // sort was stable per session and refresh felt like a
        // no-op.
        FeedService.fetchFeed(
          limit: _pageSize,
          refreshNonce: DateTime.now().millisecondsSinceEpoch,
          friendIds: friendIds,
          followedChurchIds: followedChurchIds,
        ),
        FeedService.fetchStories(),
        FeedService.fetchMyViewedStoryIds(),
        NotificationService.unreadCount(),
        UrgentBannerService.fetchActive(),
      ]);
      if (!mounted) return;
      // Hide the viewer's own posts from the home feed — they already
      // see them in the Profile → Posts tab. Treating "home" as a feed
      // of *other* people's content matches what users expect from a
      // social timeline.
      final feedPosts = (results[0] as List<Post>)
          .where((p) => viewerId == null || p.authorId != viewerId)
          .toList();
      setState(() {
        _friendshipsByUser = friendsByUser;
        _followedChurchIds = followedChurchIds;
        _posts = feedPosts;
        _stories = results[1] as List<Story>;
        _viewedStoryIds = results[2] as Set<String>;
        _unreadNotifications = results[3] as int;
        _banner = results[4] as UrgentBanner?;
        _pagesLoaded = 1;
        _endOfFeed = (results[0] as List<Post>).length < _pageSize;
        _loading = false;
      });
      _cacheBadges();
    } catch (_) {
      if (!mounted) return;
      // Network failed. If we haven't hydrated from cache yet (e.g.
      // because we were online when _bootstrap started), try now.
      if (_posts.isEmpty && _events.isEmpty) {
        _hydrateFromCache();
      }
      setState(() => _loading = false);
    }
  }

  /// Tier 2: everything that decorates the feed. Never awaited by the
  /// caller, and each group is independently guarded so one dead endpoint
  /// only costs its own rail.
  Future<void> _loadSecondary(String? viewerId) async {
    try {
      final results = await Future.wait([
        EventService.fetchEvents(upcomingOnly: true),
        ChurchService.fetchChurches(),
        EventService.fetchUserRsvpedEventIds(),
        // 18, not 8: the feed shows TWO people rails now (#13) and they draw
        // from disjoint slices of this pool. Eight would have left the
        // second rail with two people in it, which is a worse signal than
        // showing no second rail.
        DirectoryService.fetchSuggestedMembers(limit: 18),
        FeedService.pendingRequestCount(),
        MessagingService.fetchConversations(),
        AdventNewsService.fetchTopNews(limit: 3),
        PrayerService.fetchPrayers(),
        MarketplaceService.fetchProducts(),
        JobService.fetchJobs(),
        LibraryService.fetchItems('music'),
      ]);
      if (!mounted) return;
      // Drop events whose start time is more than a few hours in the
      // past — `upcomingOnly: true` filters by start_date (date-only),
      // so today's already-ended events would otherwise still appear
      // on the home screen until midnight rolls over.
      final now = DateTime.now();
      final events = (results[0] as List<Event>)
          .where(
            (e) => e.startsAt.isAfter(now.subtract(const Duration(hours: 6))),
          )
          .take(8)
          .toList();
      // Show a per-user RANDOM selection of churches (stable for a given user,
      // but different between users) instead of the same alphabetical first-6
      // for everyone — so smaller/newer churches also get discovered.
      final allChurches = List<Church>.of(results[1] as List<Church>);
      allChurches.shuffle(Random((viewerId ?? 'guest').hashCode));
      final churches = allChurches.take(6).toList();
      var unreadMessages = 0;
      for (final c in results[5] as List<Conversation>) {
        unreadMessages += c.unreadCount;
      }
      setState(() {
        _events = events;
        _churches = churches;
        _rsvpedEventIds = results[2] as Set<String>;
        _suggestedMembers = results[3] as List<MemberDirectoryEntry>;
        _pendingFriendRequests = results[4] as int;
        _unreadMessages = unreadMessages;
        _topNews = results[6] as List<AdventNews>;
        _prayers = (results[7] as List<Prayer>).take(5).toList();
        _products = (results[8] as List<Product>).take(10).toList();
        _jobs = (results[9] as List<Job>).take(8).toList();
        // Shuffled per refresh so the same few tracks don't lead the feed
        // every single time.
        _music = (List<LibraryItem>.of(results[10] as List<LibraryItem>)
              ..shuffle())
            .take(8)
            .toList();
      });
      // Best-effort cache write — failures here must never surface.
      unawaited(_writeCache(events, churches, _posts));
      _cacheBadges();
    } catch (_) {
      // Decorative content — the feed is already on screen.
    }
  }

  /// Fetches the next page using a keyset cursor (the oldest post we hold).
  /// Offset paging would be unsafe under the personalised ranking — see the
  /// note on [FeedService.fetchFeed].
  Future<void> _loadMore() async {
    if (_loadingMore || _endOfFeed || _posts.isEmpty) return;
    setState(() => _loadingMore = true);
    final viewerId = AuthService.currentUser?.id;
    try {
      var oldest = _posts.first.createdAt;
      for (final p in _posts) {
        if (p.createdAt.isBefore(oldest)) oldest = p.createdAt;
      }
      final friendIds = <String>{
        for (final e in _friendshipsByUser.entries)
          if (e.value.isAccepted) e.key,
      };
      final page = await FeedService.fetchFeed(
        limit: _pageSize,
        friendIds: friendIds,
        followedChurchIds: _followedChurchIds,
        before: oldest,
      );
      if (!mounted) return;
      final existing = _posts.map((p) => p.id).toSet();
      final fresh = page
          .where((p) => !existing.contains(p.id))
          .where((p) => viewerId == null || p.authorId != viewerId)
          .toList();
      setState(() {
        _posts = [..._posts, ...fresh];
        _pagesLoaded++;
        // Judge "the end" on what the server returned, not on what survived
        // our own filtering — a page of nothing but the viewer's own posts
        // isn't the end of the feed.
        _endOfFeed = page.length < _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Swap the header between the greeting and the branded bar.
  ///
  /// Rides the same scroll notification the nav already listens to, so
  /// this costs nothing extra, and only calls setState when the flag
  /// actually flips — not on every frame of a scroll.
  void _updateHeaderBrand() {
    if (!_scroll.hasClients) return;
    final offset = _scroll.offset;
    final next = _headerBranded
        ? offset > _brandOffOffset
        : offset > _brandOnOffset;
    if (next != _headerBranded) setState(() => _headerBranded = next);
  }

  /// Auto-paging trigger. Honours the cellular allowance.
  void _maybeAutoLoadMore() {
    if (_needsManualLoad || _loadingMore || _endOfFeed) return;
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 900) _loadMore();
  }

  /// Records a post as seen and schedules a batched write.
  ///
  /// Called from [_SeenReporter.initState], i.e. exactly when the sliver
  /// creates the card's element — which is when it's genuinely approaching
  /// the viewport, not when the widget object was constructed.
  void _noteSeen(String postId) {
    FeedService.markSeen(postId);
    _seenFlush?.cancel();
    _seenFlush = Timer(
      const Duration(seconds: 3),
      () => unawaited(FeedService.flushSeen()),
    );
  }

  /// Tapping the already-active Home tab returns to the top.
  void _scrollToTop() {
    if (!_scroll.hasClients) return;
    final distance = _scroll.offset;
    if (distance <= 0) return;
    _scroll.animateTo(
      0,
      // Scale with distance so a short hop isn't sluggish, capped so a
      // 200-post scroll doesn't take forever.
      duration: Duration(
        milliseconds: (distance / 6).clamp(220, 600).round(),
      ),
      curve: AppMotion.ease,
    );
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

  /// English greeting. This was Shona ("Mangwanani / Masikati / Manheru",
  /// "Sabata yakanaka") — reverted on the founder's instruction, 29 Jul
  /// 2026, so the header matches the English used everywhere else in the
  /// app rather than being the one localised string in it.
  String _greeting() {
    if (SabbathService.isSabbathNow()) return 'Happy Sabbath';
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
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

  /// What the Chat tab badges: unread messages plus friend requests waiting
  /// to be accepted, since both are answered from inside Advent Chat.
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
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
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
      // Revert on failure.
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

  /// Sets or clears the viewer's reaction, optimistically.
  ///
  /// The count only moves when the viewer goes from none→some or some→none;
  /// switching Like→Amen replaces the row in place (composite PK), so the
  /// total is unchanged.
  Future<void> _setReaction(Post post, PostReaction? next) async {
    final had = post.viewerReaction != null;
    final has = next != null;
    final delta = (has ? 1 : 0) - (had ? 1 : 0);
    final newCount = (post.likeCount + delta).clamp(0, 1 << 30);
    setState(() {
      _posts = _posts
          .map(
            (p) => p.id == post.id
                ? p.copyWith(viewerReaction: next, likeCount: newCount)
                : p,
          )
          .toList();
    });
    try {
      if (next == null) {
        await FeedService.removeReaction(post.id);
      } else {
        await FeedService.reactToPost(post.id, next);
      }
    } catch (_) {
      if (!mounted) return;
      // Revert. Note this is exactly the path that made an offline like
      // silently un-fill — the outbox in phase 2 replaces it with a queue.
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

  Future<void> _sendFriendRequest(MemberDirectoryEntry member) async {
    if (_addingFriendIds.contains(member.userId)) return;
    setState(() => _addingFriendIds.add(member.userId));
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
    } finally {
      if (mounted) {
        setState(() => _addingFriendIds.remove(member.userId));
      }
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
      // The nav is a floating island now, so the feed runs full-height and
      // scrolls UNDER its frosted glass. The last sliver reserves 96dp so
      // nothing important ends up trapped beneath it.
      extendBody: true,
      body: NotificationListener<ScrollNotification>(
        onNotification: (note) {
          if (note is UserScrollNotification) handleNavScroll(note);
          if (note is ScrollUpdateNotification) {
            _maybeAutoLoadMore();
            _updateHeaderBrand();
          }
          // Never swallow the notification — LiveBanner and the nav both
          // listen further up.
          return false;
        },
        // The floating Advent Chat bubble that used to sit here is gone
        // (2026-07-27). It was unreachable by construction: `extendBody` puts
        // the body under the island, so a bottom-anchored bubble rendered
        // beneath the nav and could not be tapped, and it slid away with the
        // island on scroll. Chat is a real tab now — see MainBottomNav.
        child: _buildScrollableContent(),
      ),
      // No NowPlayingBar here. The mini player belongs to the Music tab; away
      // from it, transport controls live where a real music player puts them
      // — the Android media notification and the iOS lock screen / Control
      // Centre, both driven by the media session in MusicPlayerService.
      bottomNavigationBar: HideOnScroll(
        visible: navVisible,
        child: MainBottomNav(
          currentIndex: 0,
          // Tapping Home while already on Home returns to the top — the
          // only way back up from an endless feed.
          onReselect: _scrollToTop,
          // Home's own count is richer than the app-wide unread total the
          // nav falls back to: it also folds in pending friend requests,
          // which is the other thing waiting for you inside Chat.
          badges: {MainBottomNav.chatIndex: _chatBadgeCount ?? 0},
        ),
      ),
    );
  }

  /// Routes a pick from the create chooser to the right composer or screen.
  Future<void> _handleCreate(CreateKind kind) async {
    switch (kind) {
      case CreateKind.post:
        await _openPostComposer();
      case CreateKind.story:
        await _openStoryComposer();
      case CreateKind.event:
        await context.pushNamed('post_event');
      case CreateKind.prayer:
        await context.pushNamed('post_prayer');
      case CreateKind.news:
        await context.pushNamed('post_news');
      case CreateKind.notice:
        await context.pushNamed('post_notice');
      case CreateKind.job:
        await context.pushNamed('post_job');
      case CreateKind.product:
        await context.pushNamed('add_product');
    }
    if (mounted) _bootstrap();
  }

  Future<void> _loadWatch() async {
    final results = await Future.wait<Object?>([
      // Every live channel, not just the first: the banner is a deck now, and
      // silently dropping a second congregation's stream was a real loss on
      // Sabbath morning when several are on air at once.
      YoutubeService.fetchLiveNow(),
      YoutubeService.fetchFeed(limit: 30),
    ]);
    if (!mounted) return;
    // Rotate the home video sample on each refresh so it doesn't look stale:
    // pull the latest ~30 and shuffle a fresh handful in.
    final pool = List<YoutubeVideo>.from(results[1] as List<YoutubeVideo>);
    pool.shuffle();
    setState(() {
      _liveVideos = results[0] as List<YoutubeVideo>;
      _homeVideos = pool.take(8).toList();
    });
  }

  void _openVideo(YoutubeVideo v) => context.pushNamed(
    'watch_video',
    pathParameters: {'id': v.videoId},
    extra: v,
  );

  Widget _buildScrollableContent() {
    // CustomScrollView, not SingleChildScrollView + Column. The old version
    // laid out EVERY post, rail, video and ad before the first frame —
    // hundreds of widgets on open. Slivers build them as they approach the
    // viewport, which is the single biggest reason Home now scrolls smoothly
    // on a mid-range Android.
    //
    // Staggered entrance: each top section fades in and rises ~70ms after the
    // previous one, so Home assembles itself instead of appearing as one
    // block. Feed cards reuse the same widget with no delay — in a lazy
    // sliver, "on mount" IS "on scroll into view".
    return BrandedRefreshIndicator(
      color: AppColors.primaryBlue,
      onRefresh: _bootstrap,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // FLOATING, not pinned. Scrolling down takes the header away
          // with the content the way the bottom nav goes; any scroll up
          // brings it straight back, branded. Pinned meant "Hello
          // Tanatswa" sat on screen for the entire feed.
          SliverPersistentHeader(
            floating: true,
            delegate: HomeHeaderDelegate(
              branded: _headerBranded,
              snapConfiguration: _headerSnap,
              topInset: MediaQuery.paddingOf(context).top,
              greeting: _greeting(),
              firstName: _firstName(),
              initials: _initials(),
              photoUrl: _profilePhotoUrl(),
              unreadNotifications: _unreadNotifications,
              sabbath: SabbathStatus.resolve(),
              onAvatarTap: () => context.goNamed('profile'),
              onSearchTap: () => context.pushNamed('search'),
              onBellTap: () async {
                await context.pushNamed('notification_centre');
                if (mounted) _bootstrap();
              },
            ),
          ),
          SliverToBoxAdapter(
            child: StaggeredReveal(
              index: 0,
              rise: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // LIVE now — collapses to nothing when no channel is live,
                  // and becomes a swipeable deck when several are.
                  LiveBanner(live: _liveVideos, onTap: _openVideo),
                  if (_banner != null &&
                      !_dismissedBannerIds.contains(_banner!.id)) ...[
                    const SizedBox(height: AppSpace.md),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.lg,
                      ),
                      child: _UrgentBannerCard(
                        banner: _banner!,
                        onDismiss: () => setState(
                          () => _dismissedBannerIds.add(_banner!.id),
                        ),
                      ),
                    ),
                  ],
                  // The standalone search field that used to sit here is gone
                  // — it duplicated the header's search button one thumb away
                  // from it, and cost a whole row between the live card and
                  // the composer. Search is the header glyph now, full stop.
                  const SizedBox(height: AppSpace.md),
                  ComposerEntry(
                    photoUrl: _viewerPhotoUrl(),
                    name: _displayFullName(),
                    onCreate: _handleCreate,
                  ),
                  // Navigation, not authoring — so these sit UNDER the
                  // composer card rather than inside it. Order here is
                  // fixed by the founder (28 Jul): header, live banner,
                  // composer, these chips, stories, devotion, library
                  // tiles, feed.
                  HomeShortcutChips(
                    onChurches: () => context.pushNamed('churches'),
                    onEvents: () => context.pushNamed('events'),
                    onDonate: () => context.pushNamed('donate'),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: StaggeredReveal(
              index: 1,
              child: HomeSection(
                title: 'Stories',
                action: 'Prayer',
                onAction: () => context.pushNamed('prayer'),
                child: StoriesRail(
                  stories: _stories,
                  viewerId: AuthService.currentUser?.id ?? '',
                  viewerName: _displayFullName(),
                  viewerPhotoUrl: _viewerPhotoUrl(),
                  onAddStory: _openStoryComposer,
                  onAuthorTapped: (_, list) => _openStoryViewer(list),
                  viewedStoryIds: _allViewedIds,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: StaggeredReveal(
              index: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpace.lg),
                  // Devotion + Sabbath School + hymn / music / EGW of the
                  // day. Self-hides only if every source is empty, which the
                  // bundled hymnal makes very unlikely.
                  TodayCard(devotion: _devotion),
                  const SizedBox(height: AppSpace.md),
                  // Library launcher. This is the ONLY route into /quiz —
                  // see LibraryTiles before reordering it.
                  const LibraryTiles(),
                ],
              ),
            ),
          ),
          // Official church-posted events, featured prominently with the
          // church's name + gold tick. Self-hides when there are none.
          const SliverToBoxAdapter(
            child: StaggeredReveal(
              index: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: AppSpace.lg),
                  FeaturedChurchEvents(),
                ],
              ),
            ),
          ),
          // Advent News + Music live INSIDE the shuffled discovery feed
          // (see _buildDiscoveryCards) so their position varies per user
          // instead of being pinned to the same spot here. The feed is a
          // Facebook-style mix: posts intercalated with discovery cards,
          // Watch videos and sponsored slots, in one continuous scroll.
          _buildFeedSliver(),
          SliverToBoxAdapter(child: _buildFeedFooter()),
          // Bottom padding so the floating nav island doesn't sit on top of
          // the last bit of feed content — `extendBody` runs the feed
          // underneath it. Matches the ~96dp MainBottomNav asks for.
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
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

  /// Suggested members the viewer is NOT already friends with.
  ///
  /// Pending requests either way still count, so the rail shows even when
  /// all it has is an Accept button. Cards dismissed this session drop out.
  List<MemberDirectoryEntry> get _openSuggestions {
    return _suggestedMembers.where((m) {
      if (_dismissedSuggestionIds.contains(m.userId)) return false;
      final f = _friendshipsByUser[m.userId];
      if (f == null) return true;
      return f.status != FriendshipStatus.accepted;
    }).toList();
  }

  /// How many people the first rail takes before the second one starts.
  static const _firstRailSize = 6;

  /// Splits [_openSuggestions] between the two "people to meet" rails (#13).
  ///
  /// `DirectoryService.fetchSuggestedMembers` already returns the pool
  /// tiered by real overlap — same church, then same city, then same
  /// province, then everyone else — so taking the head and the tail is
  /// exactly the split we want: the first rail is the people the viewer
  /// plausibly knows of, the second is the wider community.
  ///
  /// The second rail needs at least three people to be worth its heading. A
  /// rail of one is a lonelier signal than no rail at all, especially on a
  /// network this size, so below that everyone stays in the first rail.
  List<MemberDirectoryEntry> _suggestionsForRail({required bool first}) {
    final all = _openSuggestions;
    if (all.length < _firstRailSize + 3) {
      return first ? all : const [];
    }
    return first
        ? all.take(_firstRailSize).toList()
        : all.skip(_firstRailSize).toList();
  }

  String? _profilePhotoUrl() {
    final user = AuthService.currentUser;
    final meta = user?.userMetadata ?? const {};
    final raw = (meta['profile_photo_url'] as String?)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
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
              // Pushed, not `go`n: Churches is no longer a nav tab, so it
              // needs a back stack to return to Home.
              onTap: () => context.pushNamed('churches'),
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
    // The card asks for three lines of prayer text; at 132 it only had
    // room for two, so the third was sliced through the middle of the
    // letters — not ellipsised, cut. Height is derived from the real line
    // height so the three lines it promises actually fit, at any system
    // font size.
    //   14+14 padding · 34 header · 8 · 3 lines · 8 · 18 footer
    final lineHeight = MediaQuery.textScalerOf(context).scale(13) * 1.4;
    final height = 28 + 34 + 8 + (lineHeight * 3) + 8 + 18;
    return SizedBox(
      height: height,
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
  /// [ProductTile] sizes itself from its width, so each is width-boxed to
  /// behave like the events / prayers rails.
  ///
  /// Uses the same tile as every marketplace surface — a product should
  /// not change shape depending on which screen you meet it on.
  Widget _buildProductsRow() {
    return SizedBox(
      height: 268,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _products.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final p = _products[i];
          return SizedBox(
            width: 156,
            child: ProductTile(
              product: p,
              // Matches the tag on the detail carousel's first image, so the
              // photo expands into the detail screen instead of the page
              // simply replacing itself.
              heroTag: 'product_image_${p.id}',
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

  /// The feed, as a lazy sliver.
  ///
  /// `SliverChildBuilderDelegate` only creates elements and render objects
  /// for cards near the viewport, so a 200-post feed costs the same on open
  /// as a 15-post one. Keep-alives are off so scrolled-past cards release
  /// their image decodes instead of pinning them for the session.
  Widget _buildFeedSliver() {
    if (_loading && _posts.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpace.lg),
          child: ShimmerLoaders.postColumn(count: 3),
        ),
      );
    }
    if (_posts.isEmpty) {
      return SliverToBoxAdapter(child: _buildEmptyFeed());
    }
    final children = _buildFeedChildren();
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) => children[i],
        childCount: children.length,
        addAutomaticKeepAlives: false,
      ),
    );
  }

  /// Day-one state. A brand-new member with no friends and no followed
  /// churches used to get one line of italic text as their entire first
  /// impression of the app.
  Widget _buildEmptyFeed() {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.xl,
        AppSpace.lg,
        AppSpace.lg,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpace.xl),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: palette.divider),
        ),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.groups_outlined,
                color: AppColors.primaryBlue,
                size: 34,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            Text(
              'Your feed starts here',
              textAlign: TextAlign.center,
              style: AppTextStyles.headlineSmall.copyWith(
                color: palette.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              'Follow a church or add a few friends and their updates will '
              'appear here. Or be the first to share something.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: palette.textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.pushNamed('churches'),
                    icon: const Icon(Icons.church_outlined, size: 18),
                    label: const Text('Find churches'),
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _handleCreate(CreateKind.post),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Post'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// End-of-feed affordance: a spinner while paging, a tap target when the
  /// cellular allowance is used up, or the caught-up marker.
  Widget _buildFeedFooter() {
    if (_posts.isEmpty) return const SizedBox.shrink();
    final palette = context.palette;
    if (_loadingMore) {
      // Post-shaped shimmer rather than a spinner: the next page arrives
      // into the shape it will occupy, so nothing jumps when it lands.
      return ShimmerLoaders.postColumn(count: 1);
    }
    if (_endOfFeed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xl),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.successGreen.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: AppColors.successGreen,
                size: 22,
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              "You're all caught up",
              style: AppTextStyles.titleSmall.copyWith(
                color: palette.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              "You've seen everything new.",
              style: AppTextStyles.caption.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: AppSpace.lg),
            // The feed does NOT loop back and re-serve posts the viewer has
            // already read. On a network this size that would be obvious
            // within one scroll, and a feed caught recycling reads as a feed
            // with nothing in it. What the end of the feed can honestly do
            // is point somewhere there IS more.
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => context.pushNamed('member_directory'),
                  icon: const Icon(Icons.people_outline_rounded, size: 18),
                  label: const Text('Meet people'),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.pushNamed('events'),
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: const Text('Events'),
                ),
              ],
            ),
          ],
        ),
      );
    }
    if (_needsManualLoad) {
      // On mobile data we stop auto-paging after the allowance so an idle
      // scroll can't quietly eat someone's bundle — they choose to spend it.
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.lg,
          AppSpace.lg,
          AppSpace.xl,
        ),
        child: Column(
          children: [
            OutlinedButton.icon(
              onPressed: _loadMore,
              icon: const Icon(Icons.expand_more_rounded, size: 20),
              label: const Text('Load more posts'),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              "You're on mobile data",
              style: AppTextStyles.caption.copyWith(color: palette.textMuted),
            ),
          ],
        ),
      );
    }
    // Auto-paging is about to fire — hold the space so the scroll doesn't
    // jump when the next page lands.
    return const SizedBox(height: 80);
  }

  List<Widget> _buildFeedChildren() {
    final viewerId = AuthService.currentUser?.id;
    final cachedAt = CacheService.cachedAt('home_feed');
    final discoveryCards = _buildDiscoveryCards();
    // NOTE: no shuffle here.
    //
    // There used to be a `discoveryCards.shuffle(Random(viewerId.hashCode))`
    // on this line, and it was the whole of #14. `_buildDiscoveryCards`
    // ends by sorting the modules by requested depth, then by the viewer's
    // onboarding interests, then by a per-viewer seed — and this line threw
    // all three away and re-ordered them at random. The shuffle was seeded,
    // so the result was stable per account and looked deliberate; what it
    // actually meant was that asking for "more events" during onboarding
    // changed nothing, and that no module could be relied on to appear
    // anywhere in particular. The ordering is computed once, properly, and
    // is now allowed to survive.

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
    // Discovery modules are paced to the content that actually EXISTS, not
    // to a fixed "one card every five posts".
    //
    // That constant is the other half of #14. With a full feed it is right.
    // With the post backlog this network actually has, it meant that after
    // six posts exactly one module had been interleaved and the remaining
    // seven were dumped in a block at the very bottom — past the end of the
    // posts, where nobody scrolls. From the outside that is "the modules
    // don't come back". They were coming back; they were being stacked
    // somewhere no one looks.
    //
    // Spreading them evenly over however many posts there are means every
    // module lands between two posts on any feed length, and a long feed
    // still gets the original 5-post rhythm because of the cap.
    final discoverySpacing = discoveryCards.isEmpty || _posts.isEmpty
        ? _discoveryEveryNPosts
        : (_posts.length ~/ (discoveryCards.length + 1))
            .clamp(2, _discoveryEveryNPosts);

    var cardIdx = 0;
    var adsInserted = 0;
    var videoIdx = 0;
    var musicIdx = 0;
    for (var i = 0; i < _posts.length; i++) {
      final post = _posts[i];
      children.add(
        // Fades in and rises as it scrolls into view. In a lazy sliver the
        // card's ELEMENT is created just before it becomes visible, so a
        // mount-triggered reveal IS a scroll-triggered one — and that same
        // moment is when _SeenReporter records the view.
        _SeenReporter(
          key: ValueKey('seen_${post.id}'),
          postId: post.id,
          onSeen: _noteSeen,
          child: StaggeredReveal(
          rise: 16,
          child: RepaintBoundary(
            child: PostCard(
              post: post,
              viewerId: viewerId,
              onLikeToggled: () => _toggleLike(post),
              onReactionSelected: (r) => _setReaction(post, r),
              onCommentsTapped: () => _openComments(post),
              onImageTapped: (index) => _openImageViewer(post, index),
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
          ),
          ),
        ),
      );
      if ((i + 1) % discoverySpacing == 0 && cardIdx < discoveryCards.length) {
        children.add(discoveryCards[cardIdx++]);
      }
      // Individual YouTube video cards from Watch, interleaved into the
      // feed (one at a time, paced) — tap opens the in-app player.
      if ((i + 1) % _videoEveryNPosts == 0 && videoIdx < _homeVideos.length) {
        final v = _homeVideos[videoIdx++];
        children.add(YoutubeVideoCard(video: v, onTap: () => _openVideo(v)));
      }
      // One track at a time, same treatment as the videos.
      if ((i + 1) % _musicEveryNPosts == 0 && musicIdx < _music.length) {
        children.add(HomeMusicCard(item: _music[musicIdx++]));
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
    return children;
  }

  // Interruption cadence for the mixed feed. These were 3 / 4 / 6 with a cap
  // of 4, which meant twelve posts carried NINE interruptions — four
  // discovery cards, three videos and two ads. Relaxed so the scroll reads
  // as a feed with breaks rather than breaks with a feed.
  //
  // Smaller = more interruption; larger = posts feel more continuous.
  static const _discoveryEveryNPosts = 5;

  // Cadence for individual YouTube video cards interleaved into the feed.
  static const _videoEveryNPosts = 8;

  // Individual music tracks, offset from the video cadence so a track and a
  // video never land back to back.
  static const _musicEveryNPosts = 6;

  // Sponsored native-ad cadence. Capped per render so a long scroll doesn't
  // spawn dozens of ad requests. Deliberately a revenue trade for feel.
  static const _adEveryNPosts = 8;
  static const _maxFeedAds = 3;

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
    // Music is NO LONGER a discovery rail. Ten tracks crowded into one
    // horizontal strip scrolled past as a blur; each track now gets its own
    // card interleaved into the feed (see _musicEveryNPosts).
    // #13 — two rows of people, surfaced at different depths.
    //
    // One rail was doing two jobs badly. The people worth meeting first are
    // the ones the viewer overlaps with — same congregation, same city —
    // and those are exactly the ones buried at the far end of a horizontal
    // scroll nobody finishes. Splitting the pool means the near tier gets a
    // rail of its own near the top, and the wider community gets a second
    // one further down where "who else is on here" is the question the
    // viewer is actually asking.
    //
    // The two rails draw from DISJOINT slices, so the second is never a
    // repeat of the first. If there aren't enough people to fill both, the
    // second simply doesn't build — better one honest rail than the same
    // faces twice under two different headings.
    final nearby = _suggestionsForRail(first: true);
    final wider = _suggestionsForRail(first: false);
    if (nearby.isNotEmpty) {
      discoverable.add(
        _DiscoverySlot(
          key: 'people',
          depth: _SlotDepth.early,
          widget: _discoverySection(
            title: 'People you may meet',
            child: _buildSuggestedMembersRow(nearby),
          ),
        ),
      );
    }
    if (wider.isNotEmpty) {
      discoverable.add(
        _DiscoverySlot(
          key: 'people_more',
          depth: _SlotDepth.late,
          widget: _discoverySection(
            title: 'More of the community',
            action: 'See all',
            onAction: () => context.pushNamed('member_directory'),
            child: _buildSuggestedMembersRow(wider),
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
            onAction: () => context.pushNamed('churches'),
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
      // Depth outranks everything: a module that asked to be early or late
      // asked for a reason, and interest weighting must not drag the second
      // people rail up next to the first one.
      if (a.depth != b.depth) return a.depth.index.compareTo(b.depth.index);
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
    // Routes through the one shared HomeSection so discovery rails keep the
    // same header grammar and vertical rhythm as everything else on Home.
    return HomeSection(title: title, action: action, onAction: onAction,
        child: child);
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

  Future<void> _openImageViewer(Post post, [int index = 0]) async {
    final images = post.imageUrls;
    if (images.isEmpty) return;
    final safe = index.clamp(0, images.length - 1);
    await PostImageViewer.show(
      context,
      imageUrl: images[safe],
      // Only the first photo carries the shared tag in the card. Deeper
      // pages get their own unique tag so two Heroes never claim the same
      // one — with no counterpart it simply cross-fades instead of flying.
      heroTag: safe == 0
          ? 'post_image_${post.id}'
          : 'post_image_${post.id}_$safe',
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

  /// One "people to meet" rail. The caller decides WHICH people — there are
  /// two rails now (#13) and they must show disjoint slices, so the
  /// filtering lives in [_suggestionsForRail] rather than here.
  Widget _buildSuggestedMembersRow(
    List<MemberDirectoryEntry> visibleSuggestions,
  ) {
    final viewerId = AuthService.currentUser?.id;
    // The text block below the photo takes its natural height and the
    // photo absorbs whatever is left (see _SuggestedMemberTile), so the
    // card cannot overflow when the system font is scaled up — it just
    // crops a little more of the picture.
    return SizedBox(
      height: 280,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: visibleSuggestions.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final m = visibleSuggestions[i];
          final friendship = _friendshipsByUser[m.userId];
          return SizedBox(
            width: 168,
            child: _SuggestedMemberTile(
              entry: m,
              friendship: friendship,
              viewerId: viewerId,
              busy: _addingFriendIds.contains(m.userId),
              onDismiss: () =>
                  setState(() => _dismissedSuggestionIds.add(m.userId)),
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
            borderRadius: BorderRadius.circular(AppRadius.lg),
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
                  fontSize: 12,
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
          borderRadius: BorderRadius.circular(AppRadius.lg),
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
                fontSize: 12,
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

/// One "People you may meet" card: a big square photo, the name, ONE
/// reason, and a full-width Add.
///
/// It used to be a 62dp circular avatar floating in a mostly-empty card,
/// with a profession subtitle that was usually "Adventist member" and two
/// competing actions (a pill AND a "View profile" link). You cannot
/// decide whether to meet someone from a thumbnail that small — the photo
/// IS the content here, so it takes the whole top of the card, and the
/// card as a whole is the tap target for their profile.
class _SuggestedMemberTile extends StatelessWidget {
  const _SuggestedMemberTile({
    required this.entry,
    required this.friendship,
    required this.viewerId,
    required this.busy,
    required this.onAddFriend,
    required this.onAcceptRequest,
    required this.onCancelOrUnfriend,
    required this.onOpenProfile,
    required this.onDismiss,
  });

  final MemberDirectoryEntry entry;
  final Friendship? friendship;
  final String? viewerId;
  final bool busy;
  final VoidCallback onAddFriend;
  final VoidCallback onAcceptRequest;
  final VoidCallback onCancelOrUnfriend;
  final VoidCallback onOpenProfile;
  final VoidCallback onDismiss;

  /// Exactly one line, and only if it is true. The service tiers people
  /// by their real overlap with the viewer and tags the winning reason;
  /// city or profession stand in when there is no overlap, and a person
  /// we know nothing about gets nothing rather than filler.
  String? get _reason {
    final r = entry.suggestionReason?.trim();
    if (r != null && r.isNotEmpty) return r;
    final p = entry.profession?.trim();
    if (p != null && p.isNotEmpty) return p;
    final c = entry.city?.trim();
    if (c != null && c.isNotEmpty) return c;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final name = entry.fullName ?? 'Member';
    final reason = _reason;
    return Pressable(
      onTap: onOpenProfile,
      pressedScale: 0.97,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: palette.divider),
          boxShadow: AppShadows.card(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          // max, not min — Expanded below needs the full bounded height
          // the rail hands down.
          children: [
            // Expanded, not AspectRatio: the name / reason / button block
            // claims its natural height first and the photo takes the
            // rest. A fixed square plus a text block that grows with the
            // system font size is exactly how this card overflowed.
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _MemberPhoto(
                    photoUrl: entry.profilePhotoUrl,
                    name: name,
                  ),
                // Dismiss. Session-only: nothing persists it, so the
                // person can return on the next refresh. Storing it would
                // need a table, and "not right now" is not "never".
                Positioned(
                  top: 6,
                  right: 6,
                  child: Pressable(
                    onTap: onDismiss,
                    haptics: true,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.titleMedium.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (entry.isVerified) const VerifiedTick(size: 13),
                    ],
                  ),
                  // Reserved whether or not there's a reason, so the Add
                  // buttons line up across a row of mixed cards.
                  SizedBox(
                    height: 18,
                    child: reason == null
                        ? null
                        : Text(
                            reason,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: palette.textMuted,
                              fontSize: 11.5,
                            ),
                          ),
                  ),
                  const SizedBox(height: 8),
                  _friendButton(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _friendButton() {
    final f = friendship;
    // No relationship yet → the primary action.
    if (f == null) {
      return InlineAction(
        icon: Icons.person_add_alt_1,
        label: 'Add',
        expand: true,
        busy: busy,
        onTap: onAddFriend,
      );
    }
    // Accepted → tap to unfriend.
    if (f.isAccepted) {
      return InlineAction(
        icon: Icons.check_circle_outline,
        label: 'Friends',
        expand: true,
        filled: false,
        tint: AppColors.successGreen,
        onTap: onCancelOrUnfriend,
      );
    }
    // Pending: differs by direction.
    if (viewerId != null && f.isIncomingPendingFor(viewerId!)) {
      return InlineAction(
        icon: Icons.check_rounded,
        label: 'Accept',
        expand: true,
        onTap: onAcceptRequest,
      );
    }
    // Outgoing pending → tap to cancel.
    return InlineAction(
      icon: Icons.hourglass_empty_rounded,
      label: 'Requested',
      expand: true,
      filled: false,
      tint: AppColors.primaryBlue,
      onTap: onCancelOrUnfriend,
    );
  }
}

/// Full-bleed square photo for a suggestion card. Falls back to the
/// member's initials on the brand gradient — never a grey box.
class _MemberPhoto extends StatelessWidget {
  const _MemberPhoto({required this.photoUrl, required this.name});

  final String? photoUrl;
  final String name;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
      child: Text(
        _initialsFrom(name),
        style: AppTextStyles.displayMedium.copyWith(
          color: AppColors.white,
          fontSize: 30,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    if (photoUrl == null || photoUrl!.isEmpty) return fallback;
    return CachedImage(
      photoUrl!,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

/// "Tendai Moyo" → "TM". Used by the suggestion cards when a member has
/// no photo.
String _initialsFrom(String name) {
  final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

/// Reports its post as seen the moment the sliver creates this element.
///
/// Has to be a StatefulWidget. `_buildFeedChildren` constructs every widget
/// OBJECT up front, so hooking the constructor would mark the whole page as
/// seen the instant it was assembled — including posts the user never
/// scrolled to. Element creation is the part slivers actually do lazily, and
/// `initState` is the hook for it.
class _SeenReporter extends StatefulWidget {
  const _SeenReporter({
    super.key,
    required this.postId,
    required this.onSeen,
    required this.child,
  });

  final String postId;
  final void Function(String postId) onSeen;
  final Widget child;

  @override
  State<_SeenReporter> createState() => _SeenReporterState();
}

class _SeenReporterState extends State<_SeenReporter> {
  @override
  void initState() {
    super.initState();
    widget.onSeen(widget.postId);
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
        borderRadius: BorderRadius.circular(AppRadius.card),
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
                          borderRadius: BorderRadius.circular(AppRadius.sm),
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
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Container(
              decoration: BoxDecoration(
                color: context.palette.card,
                borderRadius: BorderRadius.circular(AppRadius.card),
                boxShadow: AppShadows.card(context),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Stack(
                      children: [
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          // Flies into the event detail screen's 260px
                          // header. Only THIS rail tags event covers —
                          // FeaturedChurchEvents deliberately doesn't, since
                          // two Heroes sharing a tag on one screen throws.
                          child: Hero(
                            tag: 'event_cover_${event.id}',
                            child: _CoverImage(
                              url: event.coverPhotoUrl,
                              fallbackIcon: Icons.event,
                            ),
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
                              borderRadius: BorderRadius.circular(AppRadius.sm),
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
                                borderRadius: BorderRadius.circular(AppRadius.sm),
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
                              fontSize: 13,
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
                                    fontSize: 11,
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
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: AppShadows.card(context),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
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
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(
                          'FOLLOWING',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.white,
                            fontSize: 9,
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
          borderRadius: BorderRadius.circular(AppRadius.card),
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
                          borderRadius: BorderRadius.circular(AppRadius.sm),
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
                        fontSize: 13,
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
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.card(context),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.button),
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
          borderRadius: BorderRadius.circular(AppRadius.button),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: context.palette.card,
              borderRadius: BorderRadius.circular(AppRadius.button),
              border: Border.all(color: context.palette.divider),
              boxShadow: AppShadows.card(context),
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
                      fontSize: 12,
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
        borderRadius: BorderRadius.circular(AppRadius.lg),
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
/// How deep into the feed a discovery module wants to sit.
///
/// Most modules don't care and take whatever the per-viewer ordering gives
/// them. The two exceptions are the "people to meet" rails (#13): the feed
/// shows two of them and they must not land next to each other, or they read
/// as one long list that got wrapped rather than as two separate invitations
/// to look.
enum _SlotDepth {
  /// Near the top, where a new member is still deciding whether this app
  /// has anyone on it.
  early,

  /// No opinion — ordered by interest weighting and the per-viewer seed.
  any,

  /// Deliberately further down, for a second look at something the viewer
  /// has already been offered once.
  late,
}

class _DiscoverySlot {
  const _DiscoverySlot({
    required this.key,
    required this.widget,
    this.depth = _SlotDepth.any,
  });
  final String key;
  final Widget widget;
  final _SlotDepth depth;
}

/// Magazine-style hero for the editorial Advent News feed. Renders
/// the top news item with cover photo + title + summary and links
/// out to /news for the full list. Pinned at the very top of the
/// home feed so members see "what's trending in the Adventist
/// community in Zimbabwe" before scrolling through user posts.
/// The Marketplace Pick — one product, given real presence.
///
/// This used to be a 104px thumbnail beside two lines of text, which read as
/// a list row rather than a curated choice. A "pick" has to look picked: the
/// product photo goes full-bleed at 4:3, the price sits large over a scrim,
/// and the seller gets a line. Same slot in the feed, ten times the presence.
class _FeaturedProductCard extends StatelessWidget {
  const _FeaturedProductCard({required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final img = product.firstImage;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.985,
      child: Container(
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: AppShadows.card(context),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (img.isEmpty)
                    Container(
                      color: AppColors.primaryBlue.withValues(alpha: 0.10),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.shopping_bag_outlined,
                        color: AppColors.primaryBlue,
                        size: 44,
                      ),
                    )
                  else
                    CachedImage(img, fit: BoxFit.cover),
                  // Scrim so the price and title stay readable on any photo.
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.30),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.72),
                          ],
                          stops: const [0.0, 0.42, 1.0],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: AppSpace.md,
                    left: AppSpace.md,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.md,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.storefront_rounded,
                            size: 13,
                            color: AppColors.white,
                          ),
                          const SizedBox(width: AppSpace.xs + 1),
                          Text(
                            'MARKETPLACE PICK',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: AppSpace.lg,
                    right: AppSpace.lg,
                    bottom: AppSpace.md,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          product.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.headlineSmall.copyWith(
                            color: AppColors.white,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: AppSpace.xs),
                        Text(
                          product.formatPrice(),
                          style: AppTextStyles.headlineMedium.copyWith(
                            color: AppColors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.md,
                AppSpace.md,
                AppSpace.md,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 16,
                    color: palette.textMuted,
                  ),
                  const SizedBox(width: AppSpace.sm - 2),
                  Flexible(
                    child: Text(
                      product.sellerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                  if (product.sellerVerified) ...[
                    const SizedBox(width: AppSpace.xs),
                    const Icon(
                      Icons.verified,
                      size: 14,
                      color: AppColors.goldAccent,
                    ),
                  ],
                  const Spacer(),
                  Text(
                    'View item',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.primaryBlue,
                  ),
                ],
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
      borderRadius: BorderRadius.circular(AppRadius.lg),
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
                borderRadius: BorderRadius.circular(AppRadius.lg),
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
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                item.category.label.toUpperCase(),
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.white,
                  fontSize: 10,
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
                    fontSize: 13,
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
                fontSize: 13,
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
