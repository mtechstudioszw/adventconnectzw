import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/church_model.dart';
import '../../models/event_model.dart';
import '../../models/friendship_model.dart';
import '../../services/auth_service.dart';
import '../../models/job_model.dart';
import '../../models/member_directory_model.dart';
import '../../models/post_model.dart';
import '../../models/product_model.dart';
import '../../services/church_service.dart';
import '../../services/directory_service.dart';
import '../../services/event_service.dart';
import '../../services/feed_service.dart';
import '../../services/youtube_service.dart';
import '../../models/youtube_video.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/youtube/youtube_video_card.dart';
import '../../services/job_service.dart';
import '../../services/marketplace_service.dart';
import '../../services/search_suggest_service.dart';
import '../../services/search_typeahead_service.dart';
import '../../services/search_history_service.dart';
import '../../widgets/marketplace/product_tile.dart';
import '../../services/page_service.dart';
import '../../services/bible_service.dart';
import '../../models/hymn_model.dart';
import '../../models/org_page_model.dart';
import '../library/bible_tab.dart' show BibleReaderScreen;
import '../library/hymnal_tab.dart' show HymnReaderScreen;
import '../../services/secure_storage_service.dart';
import '../../widgets/cached_image.dart';
import '../../utils/photo_url.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/inline_action.dart';
import '../../widgets/screen_shell.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../widgets/motion/content_reveal.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/shimmer_loaders.dart';

/// Facebook-style cross-content search.
///
/// Empty state: a compact search bar at the top with the user's Recent
/// searches below ("See all" expands the list). No big hero board.
///
/// Results state: filter chips (All / People / Posts / Churches /
/// Events / Marketplace / Jobs) above the result sections so the user
/// can narrow down. If nothing matches, a "Suggestions for you" list
/// fills in from the directory's suggested-members cache — the same
/// people the home tab surfaces — so the search never feels empty.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.autoLoad = true});

  /// Whether to fetch recents, suggestions and the viewer's relationships
  /// on mount. True in the app. False lets a widget test exercise the
  /// screen's layout — the field, the filter rail, the empty state —
  /// without a Supabase client behind it. Same seam as
  /// [SplashScreen.autoNavigate] and [BiometricLockScreen.autoPrompt].
  final bool autoLoad;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

enum _Filter {
  all,
  people,
  pages,
  posts,
  churches,
  events,
  marketplace,
  jobs,
  videos,
}

class _SearchScreenState extends State<SearchScreen>
    with TickerProviderStateMixin {
  static const _recentKey = 'recent_searches_v1';
  static const _maxRecent = 20;

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;

  /// Drives the staggered rise of whatever list is on screen. Restarted
  /// every time the content underneath changes identity (a new query
  /// lands, a filter chip flips), so results arrive as a considered
  /// sequence rather than a block of rows appearing at once.
  late final AnimationController _listEnter;

  /// True while the field has focus — the field lifts and its ring
  /// lights up, so the screen responds to being used instead of sitting
  /// inert.
  bool _focused = false;

  bool _searching = false;
  String _lastQuery = '';
  _Filter _filter = _Filter.all;

  List<Church> _churches = const [];
  List<Event> _events = const [];
  List<Product> _products = const [];
  List<Job> _jobs = const [];
  List<MemberDirectoryEntry> _people = const [];
  List<Post> _posts = const [];
  List<YoutubeVideo> _videos = const [];
  List<OrgPage> _pages = const [];

  /// What's in the field right now, and the as-you-type suggestions for it
  /// (search redesign, 28 Oct 2026). The full search runs only once the
  /// member submits or taps "See all results" — [_showResults].
  String _typed = '';
  List<SearchHit> _hits = const [];
  bool _suggesting = false;
  bool _showResults = false;

  /// Real "N mutual friends" for the top people results, by user id.
  final Map<String, int> _mutual = {};

  /// Pages: follower counts and whether I follow, for the results shown.
  final Map<String, ({int followers, bool following})> _pageStats = {};

  /// People tab filter: everyone, my friends, people from my church.
  String _peopleScope = 'all';

  // Fallback list — surfaced when the query has no matches. Loaded
  // lazily the first time we hit an empty-result state.
  List<MemberDirectoryEntry> _fallbackPeople = const [];
  bool _fallbackLoading = false;

  /// Close matches for a query that found nothing — "did you mean…".
  ///
  /// Shown ABOVE [_fallbackPeople], because the two are answering different
  /// questions: these are attempts at what the member actually typed, that
  /// one is a change of subject. A misspelling should be corrected before
  /// it is consoled.
  List<SearchSuggestion> _didYouMean = const [];

  List<String> _recent = const [];
  bool _seeAllRecent = false;

  // ── Inline action state ────────────────────────────────────────────
  // Search results act in place: Add a person, Follow a church, RSVP to
  // an event, without leaving the results. That needs the viewer's
  // current relationship to each row, loaded once on open and mutated
  // optimistically. Previously every result was a navigation link — you
  // searched, tapped through, added, came back, and lost your results.
  Set<String> _friendIds = <String>{};
  Set<String> _pendingFriendIds = <String>{};
  Set<String> _followedChurchIds = <String>{};
  Set<String> _rsvpedEventIds = <String>{};

  /// The viewer's HOME church (`profiles.church_id`), or null.
  ///
  /// A member belongs to one church and follows only that one — the rule
  /// church_details has enforced since it shipped. This screen offered a
  /// Follow button on every church in the results and called
  /// `ChurchService.follow` straight through, so a member with a home
  /// church could quietly collect a second, a third, a tenth. The insert
  /// succeeded every time; nothing on the server says no. (Founder
  /// report, 25 Aug 2026: "it's just the UI but the backend does allow".)
  ///
  /// Read from user metadata rather than a query, exactly as
  /// church_details reads it, so the results list costs no extra round
  /// trip to know the answer.
  String? _homeChurchId;

  bool _isHomeChurch(String churchId) =>
      _homeChurchId != null &&
      _homeChurchId!.isNotEmpty &&
      _homeChurchId == churchId;

  /// Rows with an action in flight, keyed by result id, so a row can
  /// show a spinner and reject double taps without blocking the list.
  final Set<String> _actionBusy = <String>{};

  // Mixed discovery for the no-query landing state — people, products,
  // churches, events and jobs, so search always surfaces something to
  // explore (not just people, and not an empty recents list).
  List<MemberDirectoryEntry> _suggestions = const [];
  List<Church> _suggChurches = const [];
  List<Event> _suggEvents = const [];
  List<Product> _suggProducts = const [];
  List<Job> _suggJobs = const [];
  List<YoutubeVideo> _suggVideos = const [];
  bool _seeAllSuggestions = false;

  @override
  void initState() {
    super.initState();
    _listEnter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _focusNode.addListener(() {
      if (!mounted || _focusNode.hasFocus == _focused) return;
      setState(() => _focused = _focusNode.hasFocus);
    });
    SearchHistoryService.load();
    if (widget.autoLoad) {
      _loadRecent();
      _loadSuggestions();
      _loadRelationships();
    }
    // Keeps Add / Pending / Friends honest while this screen is open.
    FeedService.friendshipsChanged.addListener(_onFriendshipsChanged);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Honour "remove animations": land the list on its finished frame
    // instead of playing the stagger.
    if (AppMotion.enabled(context)) {
      if (_listEnter.value == 0) _listEnter.forward();
    } else {
      _listEnter.value = 1;
    }
  }

  /// Replay the stagger. Called whenever the list underneath changes
  /// identity — a query lands, a chip flips scope — so the new content
  /// arrives rather than swapping in place.
  void _replayListEnter() {
    if (!mounted) return;
    if (!AppMotion.enabled(context)) {
      _listEnter.value = 1;
      return;
    }
    _listEnter.forward(from: 0);
  }

  void _onFriendshipsChanged() {
    if (mounted) _loadRelationships();
  }

  /// One pass for every inline action's "current state". All three are
  /// best-effort: if a set fails to load the row just renders its
  /// default affordance (Add / Follow / RSVP) and the write still
  /// works — the server is the source of truth either way.
  Future<void> _loadRelationships() async {
    Future<T> safe<T>(Future<T> Function() fn, T fallback) async {
      try {
        return await fn();
      } catch (_) {
        return fallback;
      }
    }

    final me = AuthService.currentUser?.id;
    _homeChurchId = AuthService.currentUser?.userMetadata?['church_id']
        ?.toString();
    final results = await Future.wait([
      safe(() => FeedService.fetchMyFriendships(), <Friendship>[]),
      safe(() => ChurchService.fetchUserFollowedChurchIds(), <String>{}),
      safe(() => EventService.fetchUserRsvpedEventIds(), <String>{}),
    ]);
    if (!mounted) return;
    final friendships = results[0] as List<Friendship>;
    final friends = <String>{};
    final pending = <String>{};
    for (final f in friendships) {
      // The row needs "the other person's id" — which end of the pair
      // that is depends on who sent the request.
      final other = f.requesterId == me ? f.addresseeId : f.requesterId;
      if (f.isAccepted) {
        friends.add(other);
      } else {
        pending.add(other);
      }
    }
    setState(() {
      _friendIds = friends;
      _pendingFriendIds = pending;
      _followedChurchIds = results[1] as Set<String>;
      _rsvpedEventIds = results[2] as Set<String>;
    });
  }

  Future<void> _addFriend(String userId) async {
    if (_actionBusy.contains(userId)) return;
    setState(() => _actionBusy.add(userId));
    try {
      await FeedService.sendRequest(userId);
      if (!mounted) return;
      setState(() => _pendingFriendIds = {..._pendingFriendIds, userId});
    } catch (_) {
      if (!mounted) return;
      _toast('Could not send the request.');
    } finally {
      if (mounted) setState(() => _actionBusy.remove(userId));
    }
  }

  /// Follow / unfollow, under the same rule church_details enforces.
  ///
  /// The row only renders an action where one is legal (see
  /// [_ChurchResultRow]), so both branches below are belt-and-braces —
  /// but they are the branch that actually protects the data, and the
  /// button they back up has already been wrong once.
  Future<void> _toggleFollowChurch(String churchId) async {
    if (_actionBusy.contains(churchId)) return;
    final following = _followedChurchIds.contains(churchId);

    // You can only be part of your home church — no following others.
    if (!following && !_isHomeChurch(churchId)) {
      _notice(
        'You can only follow your home church. Set this as your home '
        'church from your profile (Edit profile → Home church).',
      );
      return;
    }
    // And you can't drop your home church from a search result — you
    // change it from your profile, on its 2-week cooldown.
    if (following && _isHomeChurch(churchId)) {
      _notice(
        'This is your home church. Change it from your profile — '
        'you can switch once every 2 weeks.',
      );
      return;
    }

    setState(() => _actionBusy.add(churchId));
    try {
      if (following) {
        await ChurchService.unfollow(churchId);
      } else {
        await ChurchService.follow(churchId);
      }
      if (!mounted) return;
      setState(() {
        _followedChurchIds = following
            ? (_followedChurchIds.where((id) => id != churchId).toSet())
            : {..._followedChurchIds, churchId};
      });
    } catch (_) {
      if (!mounted) return;
      _toast('Could not update. Try again.');
    } finally {
      if (mounted) setState(() => _actionBusy.remove(churchId));
    }
  }

  Future<void> _toggleRsvp(String eventId) async {
    if (_actionBusy.contains(eventId)) return;
    final going = _rsvpedEventIds.contains(eventId);
    setState(() => _actionBusy.add(eventId));
    try {
      if (going) {
        await EventService.cancelRsvp(eventId);
      } else {
        await EventService.rsvpToEvent(eventId);
      }
      if (!mounted) return;
      setState(() {
        _rsvpedEventIds = going
            ? (_rsvpedEventIds.where((id) => id != eventId).toSet())
            : {..._rsvpedEventIds, eventId};
      });
    } catch (_) {
      if (!mounted) return;
      _toast('Could not update your RSVP.');
    } finally {
      if (mounted) setState(() => _actionBusy.remove(eventId));
    }
  }

  /// Guidance, not a failure. [_toast] paints red, which the colour
  /// scheme reserves for errors and urgent content — telling somebody
  /// where their home church lives is neither.
  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        ),
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.red,
        content: Text(
          message,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        ),
      ),
    );
  }

  Future<void> _loadSuggestions() async {
    Future<List<T>> safe<T>(Future<List<T>> Function() fn) async {
      try {
        return await fn();
      } catch (_) {
        return const [];
      }
    }

    final results = await Future.wait([
      safe(() => DirectoryService.fetchSuggestedMembers(limit: 20)),
      safe(() => ChurchService.fetchChurches()),
      safe(() => EventService.fetchEvents(upcomingOnly: true)),
      safe(() => MarketplaceService.fetchProducts()),
      safe(() => JobService.fetchJobs()),
      safe(() => YoutubeService.fetchFeed(limit: 6)),
    ]);
    if (!mounted) return;
    setState(() {
      _suggestions = results[0] as List<MemberDirectoryEntry>;
      _suggChurches = (results[1] as List<Church>).take(6).toList();
      _suggEvents = (results[2] as List<Event>).take(6).toList();
      _suggProducts = (results[3] as List<Product>).take(6).toList();
      _suggJobs = (results[4] as List<Job>).take(6).toList();
      _suggVideos = (results[5] as List<YoutubeVideo>).take(6).toList();
    });
  }

  @override
  void dispose() {
    FeedService.friendshipsChanged.removeListener(_onFriendshipsChanged);
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _listEnter.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    try {
      final raw = await SecureStorageService.read(_recentKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      if (!mounted) return;
      setState(() {
        _recent = decoded
            .whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .toList(growable: false);
      });
    } catch (_) {
      // Recent searches are best-effort — ignore parse / IO failures.
    }
  }

  Future<void> _saveRecent(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final lower = trimmed.toLowerCase();
    final next = <String>[trimmed];
    for (final r in _recent) {
      if (r.toLowerCase() == lower) continue;
      next.add(r);
      if (next.length >= _maxRecent) break;
    }
    if (mounted) setState(() => _recent = next);
    try {
      await SecureStorageService.write(_recentKey, jsonEncode(next));
    } catch (_) {}
  }

  Future<void> _removeRecent(String query) async {
    final lower = query.toLowerCase();
    final next = _recent.where((r) => r.toLowerCase() != lower).toList();
    setState(() => _recent = next);
    try {
      if (next.isEmpty) {
        await SecureStorageService.delete(_recentKey);
      } else {
        await SecureStorageService.write(_recentKey, jsonEncode(next));
      }
    } catch (_) {}
  }

  Future<void> _clearRecent() async {
    setState(() {
      _recent = const [];
      _seeAllRecent = false;
    });
    try {
      await SecureStorageService.delete(_recentKey);
    } catch (_) {}
  }

  /// Typing shows suggestions; it no longer runs the full seven-way search
  /// on every pause (that downloaded up to 5,000 churches each time).
  void _onChanged(String value) {
    final q = value.trim();
    _debounce?.cancel();
    setState(() {
      _typed = q;
      _showResults = false;
      if (q.isEmpty) {
        _hits = const [];
        _suggesting = false;
      }
    });
    if (q.isEmpty) {
      _runSearch('');
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 180), () => _suggest(q));
  }

  Future<void> _suggest(String q) async {
    if (!mounted) return;
    setState(() => _suggesting = true);
    final hits = await SearchTypeaheadService.suggest(q);
    // A newer keystroke owns the screen now.
    if (!mounted || q != _typed) return;
    setState(() {
      _hits = hits;
      _suggesting = false;
    });
  }

  void _submit(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _typed = q;
      _showResults = true;
    });
    unawaited(_saveRecent(q));
    _runSearch(q);
  }

  void _useRecent(String query) {
    _controller.text = query;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: query.length),
    );
    _submit(query);
  }

  /// Opens what a suggestion points at, remembering the search.
  Future<void> _openHit(SearchHit h) async {
    unawaited(_saveRecent(_typed));
    unawaited(SearchHistoryService.add(h));
    switch (h.kind) {
      case SearchHitKind.person:
        context.pushNamed('user_profile', pathParameters: {'userId': h.id});
      case SearchHitKind.page:
        context.pushNamed('page_details', pathParameters: {'id': h.id});
      case SearchHitKind.church:
        context.pushNamed('church_details', pathParameters: {'id': h.id});
      case SearchHitKind.product:
        context.pushNamed('product_details', pathParameters: {'id': h.id});
      case SearchHitKind.job:
        context.pushNamed('job_details', pathParameters: {'id': h.id});
      case SearchHitKind.verse:
        final ref = h.payload! as BibleReference;
        // The reader counts chapters and verses from 0; a reference from 1.
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BibleReaderScreen(
              book: ref.book,
              chapter: ref.chapter - 1,
              scrollToVerse: ref.verse == null ? null : ref.verse! - 1,
            ),
          ),
        );
      case SearchHitKind.hymn:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                HymnReaderScreen(hymns: [h.payload! as Hymn], initialIndex: 0),
          ),
        );
    }
  }

  Future<void> _runSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searching = false;
        _lastQuery = '';
        _filter = _Filter.all;
        _churches = const [];
        _events = const [];
        _products = const [];
        _jobs = const [];
        _people = const [];
        _posts = const [];
        _videos = const [];
        _pages = const [];
      });
      return;
    }
    setState(() {
      _searching = true;
      _lastQuery = query;
    });
    // Wrap each search source so one throwing service (a missing
    // column in events / a schema mismatch in jobs / etc.) doesn't
    // blank the entire results screen. Previously a single failing
    // Future caused the whole Future.wait to reject and the catch
    // block showed "No results" even when `_searchPeople` had returned
    // a dozen matches — which is what the user saw.
    Future<List<T>> safe<T>(Future<List<T>> Function() fn) async {
      try {
        return await fn();
      } catch (_) {
        return const [];
      }
    }

    final results = await Future.wait([
      safe(() => _searchPeople(query)),
      // 20, not the default 5,000: twelve are shown.
      safe(() => ChurchService.fetchChurches(search: query, limit: 20)),
      safe(() => EventService.fetchEvents(search: query)),
      safe(() => MarketplaceService.fetchProducts(search: query)),
      safe(() => JobService.fetchJobs(search: query)),
      safe(() => FeedService.searchPosts(query)),
      safe(() => YoutubeService.search(query, limit: 12)),
      safe(() => PageService.directory(query: query, limit: 12)),
    ]);
    if (!mounted) return;
    // Drop a stale answer. Searches overlap — "joh" is still in flight when
    // the debounce fires "john" — and whichever lands LAST used to win, so
    // a slow earlier query could replace the results for what is actually
    // in the box (or repaint results after the field was cleared).
    if (query != _lastQuery) return;
    final people = (results[0] as List<MemberDirectoryEntry>).take(12).toList();
    final churches = (results[1] as List<Church>).take(12).toList();
    final events = (results[2] as List<Event>).take(12).toList();
    final products = (results[3] as List<Product>).take(12).toList();
    final jobs = (results[4] as List<Job>).take(12).toList();
    final posts = (results[5] as List<Post>).take(12).toList();
    final videos = (results[6] as List<YoutubeVideo>).take(12).toList();
    final pages = (results[7] as List<OrgPage>).take(12).toList();
    setState(() {
      _pages = pages;
      _people = people;
      _churches = churches;
      _events = events;
      _products = products;
      _jobs = jobs;
      _posts = posts;
      _videos = videos;
      _searching = false;
    });
    // A new answer just landed — let it arrive in sequence rather than
    // replacing the previous result set in a single frame.
    _replayListEnter();
    unawaited(_enrich(query, people, pages));
    final hasAny =
        people.isNotEmpty ||
        churches.isNotEmpty ||
        events.isNotEmpty ||
        products.isNotEmpty ||
        jobs.isNotEmpty ||
        posts.isNotEmpty ||
        videos.isNotEmpty ||
        pages.isNotEmpty;
    if (!hasAny) {
      // Ask what they MEANT before offering something else entirely.
      // Fires alongside the generic fallback rather than before it, so the
      // empty state fills in as each answer lands instead of waiting on
      // both.
      unawaited(_loadDidYouMean(query));
      _loadFallback();
    } else if (_didYouMean.isNotEmpty) {
      // A later query matched — drop suggestions belonging to the previous
      // one, or they would sit under a result list they have nothing to do
      // with.
      setState(() => _didYouMean = const []);
    }
  }

  /// Mutual friends for the top people, follower counts for Pages — real
  /// numbers, fetched after the results are already on screen.
  Future<void> _enrich(
    String query,
    List<MemberDirectoryEntry> people,
    List<OrgPage> pages,
  ) async {
    final mutual = await Future.wait([
      for (final p in people.take(6))
        DirectoryService.fetchMutualFriends(
          p.userId,
          limit: 1,
        ).then((r) => MapEntry(p.userId, r.total)),
    ]);
    final stats = await Future.wait([
      for (final pg in pages.take(12))
        PageService.stats(pg.id)
            .then<MapEntry<String, ({int followers, bool following})>?>(
              (st) => MapEntry(pg.id, (
                followers: st.followers,
                following: st.iFollow,
              )),
            )
            .catchError((_) => null),
    ]);
    if (!mounted || query != _lastQuery) return;
    setState(() {
      for (final e in mutual) {
        if (e.value > 0) _mutual[e.key] = e.value;
      }
      for (final e in stats) {
        if (e != null) _pageStats[e.key] = e.value;
      }
    });
  }

  Future<void> _togglePageFollow(OrgPage pg) async {
    final cur = _pageStats[pg.id] ?? (followers: 0, following: false);
    final next = !cur.following;
    setState(() {
      _pageStats[pg.id] = (
        followers: (cur.followers + (next ? 1 : -1)).clamp(0, 1 << 30),
        following: next,
      );
    });
    try {
      if (next) {
        await PageService.follow(pg.id);
      } else {
        await PageService.unfollow(pg.id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _pageStats[pg.id] = cur);
    }
  }

  void _openProduct(Product p) => _openResult(_lastQuery, () {
    _remember(
      SearchHit(
        kind: SearchHitKind.product,
        id: p.id,
        title: p.title,
        subtitle: p.formatPrice(),
        imageUrl: p.imageUrls.isEmpty ? null : p.imageUrls.first,
      ),
    );
    context.pushNamed(
      'product_details',
      pathParameters: {'id': p.id},
      extra: p,
    );
  });

  /// Remember what was opened from the results (the Recent row).
  void _remember(SearchHit h) => unawaited(SearchHistoryService.add(h));

  /// Close matches for a query that found nothing. Best-effort and
  /// self-cancelling: if the member has typed on since, the answer is for a
  /// query that is no longer on screen, so it is dropped.
  Future<void> _loadDidYouMean(String query) async {
    final results = await SearchSuggestService.didYouMean(query);
    if (!mounted || results.isEmpty) return;
    if (query != _lastQuery) return;
    setState(() => _didYouMean = results);
  }

  /// The suggested-members list, fetched at most once per visit to this
  /// screen and shared by every search.
  ///
  /// Held as a Future rather than a List so that two searches racing at
  /// startup await the same in-flight request instead of firing two.
  Future<List<MemberDirectoryEntry>>? _suggestedFuture;

  Future<List<MemberDirectoryEntry>> _suggestedForMatching() {
    // 80 covers both callers: the local substring match in _searchPeople
    // and the empty-state fallback, which only shows 30. One fetch, not two
    // at different limits.
    return _suggestedFuture ??= DirectoryService.fetchSuggestedMembers(
      limit: 80,
    );
  }

  Future<void> _loadFallback() async {
    if (_fallbackLoading) return;
    if (_fallbackPeople.isNotEmpty) return;
    _fallbackLoading = true;
    try {
      // Reuses whatever _searchPeople already fetched — the empty state is
      // reached straight after a search, so this was a second request for a
      // list we had just downloaded.
      final list = await _suggestedForMatching();
      if (!mounted) return;
      setState(() => _fallbackPeople = list);
    } catch (_) {
      // ignore
    } finally {
      _fallbackLoading = false;
    }
  }

  /// People search: hits three sources in parallel so any account that
  /// could appear on the home tab is also findable by name —
  ///   1. Directory entries matched by profession / skills / city / bio
  ///   2. Discoverable profiles matched by full_name directly
  ///   3. The cached "suggested members" list, name-filtered locally as
  ///      a final fallback when the user typed a name that doesn't index
  ///      cleanly.
  Future<List<MemberDirectoryEntry>> _searchPeople(String query) async {
    final lower = query.toLowerCase();
    // Each sub-source can fail independently (missing column, RLS
    // rejection, network blip). Wrap each in catch-returning-empty so
    // one failure doesn't blank the entire people section.
    Future<List<MemberDirectoryEntry>> safe(
      Future<List<MemberDirectoryEntry>> Function() fn,
    ) async {
      try {
        return await fn();
      } catch (_) {
        return const [];
      }
    }

    final results = await Future.wait([
      safe(() => DirectoryService.fetchEntries(search: query)),
      safe(() => DirectoryService.searchProfilesByName(query)),
      // Fetched ONCE per visit, not once per search.
      //
      // This list does not depend on `query` — it is the generic suggested
      // -members list, pulled only so the local substring match below can
      // catch names Supabase's index misses. It was being re-fetched on
      // every keystroke batch, dragging 80 profile rows over the network
      // each time to answer a question the previous copy could already
      // answer.
      //
      // On this project that round trip goes to eu-central-1, so it was one
      // of nine requests per search and by far the heaviest payload. Same
      // data, same fallback behaviour, one fetch.
      safe(() => _suggestedForMatching()),
    ]);
    final byProfession = results[0];
    final byName = results[1];
    final recent = results[2];

    final seen = <String>{};
    final merged = <MemberDirectoryEntry>[];
    for (final e in byProfession) {
      if (seen.add(e.id)) merged.add(e);
    }
    for (final e in byName) {
      if (seen.add(e.id)) merged.add(e);
    }
    // Loose substring match on the cached suggestion list so accounts
    // visible on the home tab also surface here — Supabase's text
    // search index can miss partial names that the cache contains.
    for (final e in recent) {
      if (seen.contains(e.id)) continue;
      final name = (e.fullName ?? '').toLowerCase();
      if (name.contains(lower)) {
        seen.add(e.id);
        merged.add(e);
      }
    }
    return merged;
  }

  void _openResult(String query, VoidCallback navigate) {
    _saveRecent(query);
    navigate();
  }

  bool get _hasResults =>
      _people.isNotEmpty ||
      _pages.isNotEmpty ||
      _churches.isNotEmpty ||
      _events.isNotEmpty ||
      _products.isNotEmpty ||
      _jobs.isNotEmpty ||
      _posts.isNotEmpty ||
      _videos.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildSearchBar(),
            if (_showResults && _lastQuery.isNotEmpty && _hasResults)
              _buildFilterChips(),
            Expanded(
              // Landing → suggestions while typing → full results on
              // submit. Row-shaped shimmer while the full search runs.
              child: _typed.isEmpty
                  ? _buildRecent()
                  : !_showResults
                  ? _buildTypeahead()
                  : ContentReveal(
                      loading: _searching,
                      skeleton: ShimmerLoaders.peopleList(),
                      child: _hasResults ? _buildResults() : _buildEmpty(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    // Flat header on the scaffold colour — no navy bar, no white slab.
    // The screen reads as one continuous surface from the status bar
    // down, and FlatStatusBar keeps the status-bar icons dark on it.
    return FlatStatusBar(
      child: Container(
        // Transparent so the ambient field reaches the status bar. Nothing
        // scrolls under this bar — it sits above the results list in the
        // normal flow — so the opaque fill was only ever hiding particles.
        color: Colors.transparent,
        // Sits straight under the status bar. The field is the subject of
        // this screen, so it starts as high as the inset allows — 2dp of
        // breathing room, not a band of empty canvas above it.
        padding: const EdgeInsets.fromLTRB(8, 2, 12, 6),
        child: Row(
          children: [
            IconButton(
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.goNamed('home');
                }
              },
              icon: Icon(Icons.arrow_back, color: context.palette.text),
              splashRadius: 22,
            ),
            Expanded(
              // One control, shared with the rest of the app.
              //
              // This used to be its own thing: a 22dp rounded rectangle
              // that lit a primary-blue ring, lifted on a shadow and
              // tweened its glyph to the accent on focus. It looked good in
              // isolation and wrong in context — new chat and find friends
              // use a flat pill, so the same act of typing to find
              // something looked like two different features depending on
              // which screen you were standing in. Founder's call, 4 Aug
              // 2026: the chat pill is the house style, and chat itself is
              // not to be touched.
              //
              // The hint stays short. "Search for friends, churches,
              // events, products…" is ~45 characters and this field is
              // roughly 230dp on a 360dp phone, so it always truncated
              // mid-word. The filter chips underneath already name every
              // scope.
              child: AppSearchField(
                controller: _controller,
                focusNode: _focusNode,
                hint: 'Search Adventist Super App',
                onChanged: _onChanged,
                onSubmitted: _submit,
                onClear: () {
                  _controller.clear();
                  _onChanged('');
                },
              ),
            ),
            // Find a friend by their QR code — already in the app, now one
            // tap from where people look for friends.
            IconButton(
              tooltip: "Scan a friend's QR code",
              onPressed: () => context.pushNamed('scan_friend'),
              icon: Icon(
                Icons.qr_code_scanner_rounded,
                color: context.palette.text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Result scopes as underlined tabs with real counts — only the ones
  /// that found something (plus All), so no tab leads to an empty list.
  Widget _buildFilterChips() {
    final palette = context.palette;
    final tabs = <(_Filter, String, int)>[
      (_Filter.all, 'Top', -1),
      (_Filter.people, 'People', _people.length),
      (_Filter.pages, 'Pages', _pages.length),
      (_Filter.posts, 'Posts', _posts.length),
      (_Filter.marketplace, 'Shop', _products.length),
      (_Filter.jobs, 'Jobs', _jobs.length),
      (_Filter.churches, 'Churches', _churches.length),
      (_Filter.events, 'Events', _events.length),
      (_Filter.videos, 'Videos', _videos.length),
    ].where((t) => t.$3 != 0).toList();
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.divider)),
      ),
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          for (final t in tabs)
            _ScopeTab(
              label: t.$2,
              count: t.$3 < 0 ? null : t.$3,
              active: _filter == t.$1,
              onTap: () {
                if (_filter == t.$1) return;
                setState(() => _filter = t.$1);
                _replayListEnter();
              },
            ),
        ],
      ),
    );
  }

  /// As-you-type suggestions: a "Search for …" row, then direct matches
  /// (a Bible reference or hymn first, then people, Pages, churches, shop
  /// items, jobs). Tapping one opens it; the first row runs the full
  /// search.
  Widget _buildTypeahead() {
    final palette = context.palette;
    // Grouped like Facebook's: a heading per kind of thing.
    const order = <(SearchHitKind, String)>[
      (SearchHitKind.verse, 'Bible'),
      (SearchHitKind.hymn, 'Hymns'),
      (SearchHitKind.person, 'People'),
      (SearchHitKind.page, 'Pages'),
      (SearchHitKind.product, 'Shop'),
      (SearchHitKind.job, 'Jobs'),
      (SearchHitKind.church, 'Churches'),
    ];
    final groups = [
      for (final (kind, label) in order)
        (
          label,
          [
            for (final h in _hits)
              if (h.kind == kind) h,
          ],
        ),
    ].where((g) => g.$2.isNotEmpty).toList();
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _Group(
          children: [
            _SuggestRow(
              leading: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.search_rounded,
                  color: AppColors.primaryBlue,
                  size: 24,
                ),
              ),
              title: 'Search for "$_typed"',
              subtitle: 'See all results',
              query: '',
              bold: true,
              onTap: () => _submit(_typed),
            ),
          ],
        ),
        for (final (label, hits) in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
            child: Text(
              label,
              style: AppTextStyles.titleSmall.copyWith(
                color: palette.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _Group(
            children: [
              for (final h in hits)
                _SuggestRow(
                  leading: _HitLeading(hit: h),
                  title: h.title,
                  subtitle: _hitSubtitle(h),
                  preview: h.preview,
                  query: _typed,
                  verified: h.verified,
                  onTap: () => _openHit(h),
                ),
            ],
          ),
        ],
        if (_suggesting && _hits.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: palette.textMuted,
                ),
              ),
            ),
          )
        else if (!_suggesting && _hits.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
            child: Text(
              'No quick matches. Search to look through posts, events and '
              'videos too.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
            ),
          ),
      ],
    );
  }

  /// "Friend · Harare", "3 mutual friends · @rudo", or the hit's own line.
  String? _hitSubtitle(SearchHit h) {
    if (h.kind != SearchHitKind.person) return h.subtitle;
    final lead = _friendIds.contains(h.id)
        ? 'Friend'
        : (h.mutualFriends ?? 0) > 0
        ? '${h.mutualFriends} mutual friend${h.mutualFriends == 1 ? '' : 's'}'
        : null;
    return [?lead, if ((h.subtitle ?? '').isNotEmpty) h.subtitle!].join(' · ');
  }

  Widget _buildRecent() {
    final shown = _seeAllRecent
        ? _recent
        : _recent.take(5).toList(growable: false);
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      // Was 8 here + 16 on the first section = 24dp of stacked dead space
      // under the field before anything readable started.
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 24),
      children: [
        ValueListenableBuilder<List<SearchHit>>(
          valueListenable: SearchHistoryService.items,
          builder: (context, items, _) => items.isEmpty
              ? const SizedBox.shrink()
              : _RecentItemsRail(
                  items: items,
                  onOpen: _openHit,
                  onClear: SearchHistoryService.clear,
                ),
        ),
        _JumpGrid(
          onPeople: () {
            setState(() => _filter = _Filter.people);
            _focusNode.requestFocus();
          },
        ),
        if (_recent.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TRY SEARCHING FOR',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: context.palette.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in const [
                      'Tendai',
                      'Harare central',
                      'Camp meeting',
                      'Plumber',
                      'Bibles',
                      'Solusi',
                      'Teaching',
                    ])
                      _SuggestionTap(label: s, onTap: () => _useRecent(s)),
                  ],
                ),
              ],
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
            child: Row(
              children: [
                Text(
                  'Recent',
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (_recent.length > 5)
                  TextButton(
                    onPressed: () =>
                        setState(() => _seeAllRecent = !_seeAllRecent),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primaryBlue,
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Text(
                      _seeAllRecent ? 'Show less' : 'See all',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: _clearRecent,
                  style: TextButton.styleFrom(
                    foregroundColor: context.palette.textMuted,
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text(
                    'Clear',
                    style: AppTextStyles.labelLarge.copyWith(
                      color: context.palette.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final q in shown)
            _RecentRow(
              query: q,
              onTap: () => _useRecent(q),
              onRemove: () => _removeRecent(q),
            ),
        ],
        ..._buildLandingSuggestions(),
      ],
    );
  }

  /// Mixed discovery rails for the no-query landing state: people,
  /// products, churches, events and jobs. Each section is hidden when
  /// empty; "People you may know" keeps its inline See-all toggle, the
  /// rest link to their tab.
  List<Widget> _buildLandingSuggestions() {
    final sections = <Widget>[];

    if (_suggestions.isNotEmpty) {
      sections.add(
        _landingHeader(
          'People you may know',
          actionLabel: _suggestions.length > 3
              ? (_seeAllSuggestions ? 'Show less' : 'See all')
              : null,
          onAction: _suggestions.length > 3
              ? () => setState(() => _seeAllSuggestions = !_seeAllSuggestions)
              : null,
        ),
      );
      sections.add(
        _seeAllSuggestions
            ? _landingList([
                for (final p in _suggestions)
                  _PersonResultRow(
                    person: p,
                    query: '',
                    state: _friendStateOf(p.userId),
                    busy: _actionBusy.contains(p.userId),
                    onAdd: () => _addFriend(p.userId),
                    onTap: () => context.pushNamed(
                      'user_profile',
                      pathParameters: {'userId': p.userId},
                    ),
                  ),
              ])
            // A rail of faces reads as "people", where a stack of rows
            // with an Add button each read as a form to fill in.
            : SizedBox(
                height: 196,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  itemCount: _suggestions.length.clamp(0, 12),
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final p = _suggestions[i];
                    return _PersonCard(
                      person: p,
                      state: _friendStateOf(p.userId),
                      busy: _actionBusy.contains(p.userId),
                      onAdd: () => _addFriend(p.userId),
                      onTap: () => context.pushNamed(
                        'user_profile',
                        pathParameters: {'userId': p.userId},
                      ),
                    );
                  },
                ),
              ),
      );
    }

    if (_suggVideos.isNotEmpty) {
      sections.add(
        _landingHeader(
          'Videos to watch',
          actionLabel: 'See all',
          onAction: () => context.pushNamed('watch'),
        ),
      );
      for (final v in _suggVideos) {
        sections.add(
          YoutubeVideoCard(
            video: v,
            onTap: () => context.pushNamed(
              'watch_video',
              pathParameters: {'id': v.videoId},
              extra: v,
            ),
          ),
        );
      }
    }

    if (_suggProducts.isNotEmpty) {
      sections.add(
        _landingHeader(
          'In the marketplace',
          actionLabel: 'See all',
          onAction: () => context.goNamed('marketplace'),
        ),
      );
      sections.add(
        _landingList([
          for (final p in _suggProducts)
            _ProductRow(
              product: p,
              onTap: () => context.pushNamed(
                'product_details',
                pathParameters: {'id': p.id},
                extra: p,
              ),
            ),
        ]),
      );
    }

    if (_suggChurches.isNotEmpty) {
      sections.add(
        _landingHeader(
          // Not location-based — these are suggestions, so don't claim "near you".
          // Real distance ranking lives on the Churches screen's "Near me".
          'Discover churches',
          actionLabel: 'See all',
          onAction: () => context.pushNamed('churches'),
        ),
      );
      sections.add(
        _landingList([
          for (final c in _suggChurches)
            _ChurchRow(
              church: c,
              onTap: () => context.pushNamed(
                'church_details',
                pathParameters: {'id': c.id},
                extra: c,
              ),
            ),
        ]),
      );
    }

    if (_suggEvents.isNotEmpty) {
      sections.add(
        _landingHeader(
          'Upcoming events',
          actionLabel: 'See all',
          onAction: () => context.pushNamed('events'),
        ),
      );
      sections.add(
        _landingList([
          for (final e in _suggEvents)
            _EventRow(
              event: e,
              onTap: () => context.pushNamed(
                'event_details',
                pathParameters: {'id': e.id},
                extra: e,
              ),
            ),
        ]),
      );
    }

    if (_suggJobs.isNotEmpty) {
      sections.add(
        _landingHeader(
          'Jobs & opportunities',
          actionLabel: 'See all',
          onAction: () => context.pushNamed('jobs'),
        ),
      );
      sections.add(
        _landingList([
          for (final j in _suggJobs)
            _JobRow(
              job: j,
              onTap: () => context.pushNamed(
                'job_details',
                pathParameters: {'id': j.id},
                extra: j,
              ),
            ),
        ]),
      );
    }

    return sections;
  }

  Widget _landingHeader(
    String title, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Text(
            title,
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryBlue,
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(
                actionLabel,
                style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  _FriendState _friendStateOf(String userId) => _friendIds.contains(userId)
      ? _FriendState.friends
      : _pendingFriendIds.contains(userId)
      ? _FriendState.pending
      : _FriendState.none;

  /// One grouped card with hairlines between rows — the way a settings
  /// list or a polished search app groups related results, instead of a
  /// separate floating card per row.
  Widget _landingList(List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: _Group(children: rows),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        EmptyStateCard(
          icon: Icons.search_off,
          title: 'No matches for "$_lastQuery"',
          // The copy changes with what we can actually offer. Telling
          // someone to "try a different spelling" while showing them the
          // correct spelling directly underneath is not advice, it is
          // noise.
          message: _didYouMean.isNotEmpty
              ? 'Here are some close matches.'
              : 'Try a shorter keyword or different spelling. '
                    'Here are people you might know instead.',
        ),
        const SizedBox(height: 16),
        // "Did you mean…" — attempts at what was typed. Above the generic
        // suggestions on purpose: correcting a misspelling beats changing
        // the subject.
        if (_didYouMean.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              _didYouMean.length == 1
                  ? 'Did you mean ${_didYouMean.first.label}?'
                  : 'Did you mean…',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (final s in _didYouMean)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DidYouMeanRow(
                suggestion: s,
                onTap: () => _openResult(
                  _lastQuery,
                  () => s.isPerson
                      ? context.pushNamed(
                          'user_profile',
                          pathParameters: {'userId': s.refId},
                        )
                      : context.pushNamed(
                          'church_details',
                          pathParameters: {'id': s.refId},
                        ),
                ),
              ),
            ),
          const SizedBox(height: 20),
        ],
        if (_fallbackPeople.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Suggestions for you',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (final p in _fallbackPeople.take(15))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PersonResultRow(
                person: p,
                // No highlight here — these are suggestions, not matches,
                // so marking the query inside them would be a lie.
                query: '',
                state: _friendIds.contains(p.userId)
                    ? _FriendState.friends
                    : _pendingFriendIds.contains(p.userId)
                    ? _FriendState.pending
                    : _FriendState.none,
                busy: _actionBusy.contains(p.userId),
                onAdd: () => _addFriend(p.userId),
                onTap: () => _openResult(
                  _lastQuery,
                  () => context.pushNamed(
                    'user_profile',
                    pathParameters: {'userId': p.userId},
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildResults() {
    final showPeople =
        (_filter == _Filter.all || _filter == _Filter.people) &&
        _people.isNotEmpty;
    final showPosts =
        (_filter == _Filter.all || _filter == _Filter.posts) &&
        _posts.isNotEmpty;
    final showChurches =
        (_filter == _Filter.all || _filter == _Filter.churches) &&
        _churches.isNotEmpty;
    final showEvents =
        (_filter == _Filter.all || _filter == _Filter.events) &&
        _events.isNotEmpty;
    final showProducts =
        (_filter == _Filter.all || _filter == _Filter.marketplace) &&
        _products.isNotEmpty;
    final showJobs =
        (_filter == _Filter.all || _filter == _Filter.jobs) && _jobs.isNotEmpty;
    final showVideos =
        (_filter == _Filter.all || _filter == _Filter.videos) &&
        _videos.isNotEmpty;
    final showPages =
        (_filter == _Filter.all || _filter == _Filter.pages) &&
        _pages.isNotEmpty;

    final anyForFilter =
        showPeople ||
        showPosts ||
        showChurches ||
        showEvents ||
        showProducts ||
        showJobs ||
        showVideos ||
        showPages;

    if (!anyForFilter) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: EmptyStateCard(
          icon: Icons.filter_alt_off,
          title: 'No ${_filterName(_filter)} for "$_lastQuery"',
          message: 'Try the All tab or a different keyword.',
        ),
      );
    }

    // On "All" every section is capped so no single type can push the
    // others off the screen — a name that matches 12 people and 1 church
    // should still show the church. "See all N" switches to that scope
    // rather than expanding in place, which is what the chips are for.
    const allCap = 3;
    final grouped = _filter == _Filter.all;
    // People tab: everyone, my friends, or my church.
    final people = _filter != _Filter.people || _peopleScope == 'all'
        ? _people
        : [
            for (final p in _people)
              if (_peopleScope == 'friends'
                  ? _friendIds.contains(p.userId)
                  : (p.churchId != null && _isHomeChurch(p.churchId!)))
                p,
          ];
    List<T> cap<T>(List<T> items) =>
        grouped ? items.take(allCap).toList() : items;

    final sections = <Widget>[
      if (showPeople)
        _Section(
          label: 'People',
          count: _people.length,
          onSeeAll: grouped && _people.length > allCap
              ? () => setState(() => _filter = _Filter.people)
              : null,
          header: _filter == _Filter.people
              ? _ScopeChips(
                  value: _peopleScope,
                  options: [
                    ('all', 'Everyone'),
                    ('friends', 'Friends'),
                    if ((_homeChurchId ?? '').isNotEmpty)
                      ('church', 'My church'),
                  ],
                  onChanged: (v) => setState(() => _peopleScope = v),
                )
              : null,
          children: [
            if (people.isEmpty)
              Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  _peopleScope == 'friends'
                      ? 'None of your friends match "$_lastQuery".'
                      : 'Nobody from your church matches "$_lastQuery".',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: context.palette.textMuted,
                  ),
                ),
              ),
            for (final p in cap(people))
              _PersonResultRow(
                person: p,
                query: _lastQuery,
                mutualFriends: _mutual[p.userId],
                state: _friendStateOf(p.userId),
                busy: _actionBusy.contains(p.userId),
                onAdd: () => _addFriend(p.userId),
                onTap: () => _openResult(_lastQuery, () {
                  _remember(
                    SearchHit(
                      kind: SearchHitKind.person,
                      id: p.userId,
                      title: (p.fullName ?? '').trim().isEmpty
                          ? 'Member'
                          : p.fullName!.trim(),
                      subtitle: p.city,
                      imageUrl: p.profilePhotoUrl,
                      verified: p.isVerified,
                    ),
                  );
                  context.pushNamed(
                    'user_profile',
                    pathParameters: {'userId': p.userId},
                  );
                }),
              ),
          ],
        ),
      if (showPages)
        _Section(
          label: 'Pages',
          count: _pages.length,
          onSeeAll: grouped && _pages.length > allCap
              ? () => setState(() => _filter = _Filter.pages)
              : null,
          children: [
            for (final pg in cap(_pages))
              _PageResultRow(
                page: pg,
                query: _lastQuery,
                followers: _pageStats[pg.id]?.followers,
                following: _pageStats[pg.id]?.following ?? false,
                onFollow: () => _togglePageFollow(pg),
                onTap: () => _openResult(_lastQuery, () {
                  _remember(
                    SearchHit(
                      kind: SearchHitKind.page,
                      id: pg.id,
                      title: pg.name,
                      subtitle: pg.category.label,
                      imageUrl: pg.logoUrl,
                      verified: pg.isVerified,
                    ),
                  );
                  context.pushNamed(
                    'page_details',
                    pathParameters: {'id': pg.id},
                    extra: pg,
                  );
                }),
              ),
          ],
        ),
      if (showChurches)
        _Section(
          label: 'Churches',
          count: _churches.length,
          onSeeAll: grouped && _churches.length > allCap
              ? () => setState(() => _filter = _Filter.churches)
              : null,
          children: [
            for (final c in cap(_churches))
              _ChurchResultRow(
                church: c,
                query: _lastQuery,
                following: _followedChurchIds.contains(c.id),
                isHomeChurch: _isHomeChurch(c.id),
                busy: _actionBusy.contains(c.id),
                onToggleFollow: () => _toggleFollowChurch(c.id),
                onTap: () => _openResult(
                  _lastQuery,
                  () => context.pushNamed(
                    'church_details',
                    pathParameters: {'id': c.id},
                    extra: c,
                  ),
                ),
              ),
          ],
        ),
      if (showEvents)
        _Section(
          label: 'Events',
          count: _events.length,
          onSeeAll: grouped && _events.length > allCap
              ? () => setState(() => _filter = _Filter.events)
              : null,
          children: [
            for (final e in cap(_events))
              _EventResultRow(
                event: e,
                query: _lastQuery,
                going: _rsvpedEventIds.contains(e.id),
                busy: _actionBusy.contains(e.id),
                onToggleRsvp: () => _toggleRsvp(e.id),
                onTap: () => _openResult(
                  _lastQuery,
                  () => context.pushNamed(
                    'event_details',
                    pathParameters: {'id': e.id},
                    extra: e,
                  ),
                ),
              ),
          ],
        ),
      if (showPosts)
        _Section(
          label: 'Posts',
          count: _posts.length,
          onSeeAll: grouped && _posts.length > allCap
              ? () => setState(() => _filter = _Filter.posts)
              : null,
          children: [
            for (final post in cap(_posts))
              _PostResultRow(
                post: post,
                query: _lastQuery,
                onTap: () =>
                    _openResult(_lastQuery, () => Navigator.pop(context)),
              ),
          ],
        ),
      if (showVideos)
        _Section(
          grouped: false,
          label: 'Videos',
          count: _videos.length,
          onSeeAll: grouped && _videos.length > allCap
              ? () => setState(() => _filter = _Filter.videos)
              : null,
          children: [
            for (final v in cap(_videos))
              YoutubeVideoCard(
                video: v,
                onTap: () => _openResult(
                  _lastQuery,
                  () => context.pushNamed(
                    'watch_video',
                    pathParameters: {'id': v.videoId},
                    extra: v,
                  ),
                ),
              ),
          ],
        ),
      if (showProducts)
        _Section(
          label: 'Shop',
          count: _products.length,
          grouped: false,
          onSeeAll: grouped && _products.length > allCap
              ? () => setState(() => _filter = _Filter.marketplace)
              : null,
          children: [
            // Photos, like a shop — not text rows.
            if (grouped)
              SizedBox(
                height: 236,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  itemCount: _products.length.clamp(0, 8),
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, i) => SizedBox(
                    width: 156,
                    child: ProductTile(
                      product: _products[i],
                      onTap: () => _openProduct(_products[i]),
                    ),
                  ),
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _products.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.72,
                ),
                itemBuilder: (context, i) => ProductTile(
                  product: _products[i],
                  onTap: () => _openProduct(_products[i]),
                ),
              ),
          ],
        ),
      if (showJobs)
        _Section(
          label: 'Jobs',
          count: _jobs.length,
          onSeeAll: grouped && _jobs.length > allCap
              ? () => setState(() => _filter = _Filter.jobs)
              : null,
          children: [
            for (final j in cap(_jobs))
              _JobResultRow(
                job: j,
                query: _lastQuery,
                onTap: () => _openResult(
                  _lastQuery,
                  () => context.pushNamed(
                    'job_details',
                    pathParameters: {'id': j.id},
                    extra: j,
                  ),
                ),
              ),
          ],
        ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        for (var i = 0; i < sections.length; i++)
          _StaggerIn(listenable: _listEnter, index: i, child: sections[i]),
      ],
    );
  }

  String _filterName(_Filter f) {
    switch (f) {
      case _Filter.all:
        return 'results';
      case _Filter.people:
        return 'people';
      case _Filter.pages:
        return 'Pages';
      case _Filter.posts:
        return 'posts';
      case _Filter.churches:
        return 'churches';
      case _Filter.events:
        return 'events';
      case _Filter.marketplace:
        return 'products';
      case _Filter.jobs:
        return 'jobs';
      case _Filter.videos:
        return 'videos';
    }
  }
}

/// Fade-and-rise for item [index] of a list, sliced out of one shared
/// controller. Results used to appear as a finished block the instant the
/// query returned; arriving in sequence reads as the app answering you.
///
/// Deliberately cheap — an Opacity and a translate, no layout work — so a
/// long result list still scrolls at 60fps on a mid-range Android.
class _StaggerIn extends StatelessWidget {
  const _StaggerIn({
    required this.listenable,
    required this.index,
    required this.child,
  });

  final Animation<double> listenable;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: listenable,
      builder: (context, inner) {
        // Each item opens a beat after the one above it. Capped so a
        // twenty-row list doesn't take twenty beats to finish — past the
        // first handful everything lands together.
        const span = 0.5;
        final start = (index * 0.06).clamp(0.0, 1 - span);
        final v = Curves.easeOutCubic.transform(
          ((listenable.value - start) / span).clamp(0.0, 1.0),
        );
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - v)),
            child: inner,
          ),
        );
      },
      child: child,
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({
    required this.query,
    required this.onTap,
    required this.onRemove,
  });

  final String query;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return PressEffect(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: context.palette.chipBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.history,
                    color: context.palette.text,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    query,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onRemove,
                  icon: Icon(
                    Icons.close,
                    color: context.palette.textMuted,
                    size: 18,
                  ),
                  splashRadius: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestionTap extends StatelessWidget {
  const _SuggestionTap({required this.label, required this.onTap});
  final String label;
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: context.palette.chipBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.palette.divider),
            ),
            child: Text(
              label,
              style: AppTextStyles.labelMedium.copyWith(
                color: context.palette.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.count,
    required this.children,
    this.onSeeAll,
    this.grouped = true,
    this.header,
  });
  final String label;
  final int count;
  final List<Widget> children;

  /// Optional row under the title (the People tab's filter chips).
  final Widget? header;

  /// Non-null only when the section is truncated on the Top tab. Switches
  /// to this type's tab rather than expanding in place.
  final VoidCallback? onSeeAll;

  /// Rows share one card; false for things that are cards themselves
  /// (videos).
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  label,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.textMuted,
                  ),
                ),
                const Spacer(),
                if (onSeeAll != null)
                  GestureDetector(
                    onTap: onSeeAll,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(
                        'See all',
                        style: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.primaryBlue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ?header,
          if (grouped)
            _Group(children: children)
          else
            for (final c in children) ...[c, const SizedBox(height: 10)],
        ],
      ),
    );
  }
}

/// A Page result: logo, name, category, real follower count, Follow.
class _PageResultRow extends StatelessWidget {
  const _PageResultRow({
    required this.page,
    required this.query,
    required this.following,
    required this.onFollow,
    required this.onTap,
    this.followers,
  });
  final OrgPage page;
  final String query;
  final int? followers;
  final bool following;
  final VoidCallback onFollow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final n = followers;
    final sub = [
      page.category.label,
      if (n != null && n > 0) '$n follower${n == 1 ? '' : 's'}',
      if ((page.city ?? '').isNotEmpty) page.city!,
    ].join('  ·  ');
    return _ResultShell(
      onTap: onTap,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 60,
          height: 60,
          color: AppColors.primaryBlue.withValues(alpha: 0.10),
          child: (page.logoUrl ?? '').isNotEmpty
              ? CachedImage(page.logoUrl!, fit: BoxFit.cover)
              : const Icon(
                  Icons.flag_outlined,
                  color: AppColors.primaryBlue,
                  size: 26,
                ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: _HighlightedText(
                  text: page.name,
                  query: query,
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (page.isVerified) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.verified,
                  color: AppColors.goldAccent,
                  size: 15,
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
          ),
        ],
      ),
      trailing: InlineAction(
        label: following ? 'Following' : 'Follow',
        icon: following ? Icons.check : Icons.add,
        filled: !following,
        onTap: onFollow,
      ),
    );
  }
}

/// Small filter chips under a results heading.
class _ScopeChips extends StatelessWidget {
  const _ScopeChips({
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 8,
        children: [
          for (final (id, label) in options)
            ChoiceChip(
              label: Text(label),
              selected: value == id,
              showCheckmark: false,
              onSelected: (_) => onChanged(id),
              selectedColor: AppColors.primaryBlue.withValues(alpha: 0.12),
              backgroundColor: palette.card,
              labelStyle: AppTextStyles.labelMedium.copyWith(
                color: value == id ? AppColors.primaryBlue : palette.text,
                fontWeight: FontWeight.w600,
              ),
              side: BorderSide(
                color: value == id ? AppColors.primaryBlue : palette.divider,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Recent": faces and logos of what was opened from Search, newest first.
class _RecentItemsRail extends StatelessWidget {
  const _RecentItemsRail({
    required this.items,
    required this.onOpen,
    required this.onClear,
  });
  final List<SearchHit> items;
  final void Function(SearchHit) onOpen;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
          child: Row(
            children: [
              Text(
                'Recent',
                style: AppTextStyles.titleMedium.copyWith(
                  color: palette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: onClear,
                style: TextButton.styleFrom(minimumSize: const Size(0, 36)),
                child: Text(
                  'Clear',
                  style: AppTextStyles.labelLarge.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) {
              final h = items[i];
              final round = h.kind == SearchHitKind.person;
              return Semantics(
                button: true,
                label: h.title,
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: () => onOpen(h),
                  child: SizedBox(
                    width: 72,
                    child: Column(
                      children: [
                        round
                            ? _PersonAvatar(
                                photoUrl: h.imageUrl,
                                fullName: h.title,
                                size: 68,
                              )
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: SizedBox(
                                  width: 68,
                                  height: 68,
                                  child: _HitLeadingFill(hit: h),
                                ),
                              ),
                        const SizedBox(height: 6),
                        Text(
                          h.title,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.labelSmall.copyWith(
                            color: palette.text,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
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

/// A logo / photo / icon that fills its box — for the Recent rail.
class _HitLeadingFill extends StatelessWidget {
  const _HitLeadingFill({required this.hit});
  final SearchHit hit;

  @override
  Widget build(BuildContext context) {
    final url = hit.imageUrl;
    if ((url ?? '').isNotEmpty) return CachedImage(url!, fit: BoxFit.cover);
    final icon = switch (hit.kind) {
      SearchHitKind.page => Icons.flag_outlined,
      SearchHitKind.church => Icons.church_outlined,
      SearchHitKind.product => Icons.shopping_bag_outlined,
      SearchHitKind.job => Icons.work_outline_rounded,
      _ => Icons.search_rounded,
    };
    return ColoredBox(
      color: AppColors.primaryBlue.withValues(alpha: 0.10),
      child: Icon(icon, color: AppColors.primaryBlue, size: 28),
    );
  }
}

/// Rows in one card, hairline-separated.
class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: 76,
                color: palette.divider,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A results-scope tab: label, count, and an underline when active.
class _ScopeTab extends StatelessWidget {
  const _ScopeTab({
    required this.label,
    required this.active,
    required this.onTap,
    this.count,
  });
  final String label;
  final int? count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      button: true,
      selected: active,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: label),
                    if (count != null)
                      TextSpan(
                        text: ' $count',
                        style: TextStyle(
                          color: active
                              ? AppColors.primaryBlue.withValues(alpha: 0.7)
                              : palette.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
                style: AppTextStyles.labelLarge.copyWith(
                  color: active ? AppColors.primaryBlue : palette.text,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 3,
                width: active ? 28 : 0,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One as-you-type suggestion.
class _SuggestRow extends StatelessWidget {
  const _SuggestRow({
    required this.leading,
    required this.title,
    required this.query,
    required this.onTap,
    this.subtitle,
    this.preview,
    this.verified = false,
    this.bold = false,
  });
  final Widget leading;
  final String title;
  final String? subtitle;

  /// A verse's text, in italics under the reference.
  final String? preview;
  final String query;
  final bool verified;
  final bool bold;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: _HighlightedText(
                          text: title,
                          query: query,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: palette.text,
                            fontWeight: bold
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (verified) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.verified,
                          color: AppColors.goldAccent,
                          size: 14,
                        ),
                      ],
                    ],
                  ),
                  if ((subtitle ?? '').isNotEmpty)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  if ((preview ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '"${preview!}"',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: palette.text,
                          fontStyle: FontStyle.italic,
                          height: 1.4,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.north_west_rounded, size: 16, color: palette.textMuted),
          ],
        ),
      ),
    );
  }
}

/// The picture for a suggestion: a face, a logo, a product photo, or the
/// kind's icon.
class _HitLeading extends StatelessWidget {
  const _HitLeading({required this.hit});
  final SearchHit hit;

  @override
  Widget build(BuildContext context) {
    if (hit.kind == SearchHitKind.person) {
      return _PersonAvatar(
        photoUrl: hit.imageUrl,
        fullName: hit.title,
        size: 52,
      );
    }
    final icon = switch (hit.kind) {
      SearchHitKind.page => Icons.flag_outlined,
      SearchHitKind.church => Icons.church_outlined,
      SearchHitKind.product => Icons.shopping_bag_outlined,
      SearchHitKind.job => Icons.work_outline_rounded,
      SearchHitKind.verse => Icons.menu_book_rounded,
      SearchHitKind.hymn => Icons.music_note_rounded,
      SearchHitKind.person => Icons.person_outline,
    };
    final url = hit.imageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 52,
        height: 52,
        color: AppColors.primaryBlue.withValues(alpha: 0.10),
        child: (url ?? '').isNotEmpty
            ? CachedImage(url!, fit: BoxFit.cover, width: 52, height: 52)
            : Icon(icon, color: AppColors.primaryBlue, size: 24),
      ),
    );
  }
}

/// Shortcuts at the top of Search to the places people look things up.
class _JumpGrid extends StatelessWidget {
  const _JumpGrid({required this.onPeople});
  final VoidCallback onPeople;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final items = <(IconData, String, VoidCallback)>[
      (Icons.people_alt_outlined, 'People', onPeople),
      (Icons.flag_outlined, 'Pages', () => context.pushNamed('pages')),
      (Icons.church_outlined, 'Churches', () => context.pushNamed('churches')),
      (Icons.storefront_outlined, 'Shop', () => context.goNamed('marketplace')),
      (Icons.work_outline_rounded, 'Jobs', () => context.pushNamed('jobs')),
      (Icons.event_outlined, 'Events', () => context.pushNamed('events')),
      (Icons.play_circle_outline, 'Videos', () => context.pushNamed('watch')),
      (Icons.menu_book_outlined, 'Library', () => context.pushNamed('library')),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        // Height grows with the member's text size — a fixed aspect
        // ratio overflowed at large accessibility sizes.
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          mainAxisExtent:
              62 + MediaQuery.textScalerOf(context).scale(11.5) * 1.6,
        ),
        children: [
          for (final (icon, label, onTap) in items)
            Semantics(
              button: true,
              label: label,
              excludeSemantics: true,
              child: Pressable(
                onTap: onTap,
                child: Container(
                  decoration: BoxDecoration(
                    color: palette.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: palette.divider),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          icon,
                          color: AppColors.primaryBlue,
                          size: 20,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.labelSmall.copyWith(
                            color: palette.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A person in the landing rail: face, name, place, and Add.
class _PersonCard extends StatelessWidget {
  const _PersonCard({
    required this.person,
    required this.state,
    required this.busy,
    required this.onAdd,
    required this.onTap,
  });
  final MemberDirectoryEntry person;
  final _FriendState state;
  final bool busy;
  final VoidCallback onAdd;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final name = (person.fullName ?? '').trim().isEmpty
        ? 'Member'
        : person.fullName!.trim();
    final place = (person.city ?? person.province ?? '').trim();
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 140,
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.divider),
        ),
        child: Column(
          children: [
            _PersonAvatar(
              photoUrl: person.profilePhotoUrl,
              fullName: name,
              size: 64,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelLarge.copyWith(
                      color: palette.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (person.isVerified) ...[
                  const SizedBox(width: 3),
                  const Icon(
                    Icons.verified,
                    color: AppColors.goldAccent,
                    size: 13,
                  ),
                ],
              ],
            ),
            Text(
              place.isEmpty ? ' ' : place,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall.copyWith(
                color: palette.textMuted,
                fontSize: 11.5,
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: switch (state) {
                _FriendState.friends => InlineAction(
                  label: 'Friends',
                  icon: Icons.check,
                  filled: false,
                  onTap: null,
                ),
                _FriendState.pending => InlineAction(
                  label: 'Pending',
                  icon: Icons.hourglass_top_rounded,
                  filled: false,
                  onTap: null,
                ),
                _FriendState.none => InlineAction(
                  label: 'Add',
                  icon: Icons.person_add_alt_1,
                  busy: busy,
                  onTap: onAdd,
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The viewer's relationship to a person result — drives which inline
/// affordance the row shows.
enum _FriendState { none, pending, friends }

/// Renders [text] with every occurrence of [query] tinted, so a result
/// says WHY it matched. Without this a results list makes people re-read
/// every row to work out what the app thought they meant.
///
/// Case-insensitive, and matches on the whole query string rather than
/// per-word so "camp meeting" highlights as one phrase.
class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.text,
    required this.query,
    required this.style,
    this.maxLines = 1,
  });

  final String text;
  final String query;
  final TextStyle style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final needle = query.trim().toLowerCase();
    final haystack = text.toLowerCase();
    if (needle.isEmpty || !haystack.contains(needle)) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final spans = <TextSpan>[];
    var cursor = 0;
    while (cursor < text.length) {
      final hit = haystack.indexOf(needle, cursor);
      if (hit == -1) {
        spans.add(TextSpan(text: text.substring(cursor)));
        break;
      }
      if (hit > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, hit)));
      }
      spans.add(
        TextSpan(
          text: text.substring(hit, hit + needle.length),
          style: TextStyle(
            color: AppColors.primaryBlue,
            fontWeight: FontWeight.w800,
            backgroundColor: AppColors.primaryBlue.withValues(alpha: 0.14),
          ),
        ),
      );
      cursor = hit + needle.length;
    }
    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

// The inline Add / Follow / RSVP pill now lives in
// `lib/widgets/inline_action.dart` as InlineAction, shared with the home
// "People you may meet" cards so Add can't mean two things in two places.

/// Shared chrome for every result row: the card, the tap target and the
/// leading/body/trailing rhythm. The rows differ in what they put in
/// those slots, which is the whole point — a church, a job and a person
/// should not arrive looking like siblings.
class _ResultShell extends StatelessWidget {
  const _ResultShell({
    required this.leading,
    required this.body,
    required this.onTap,
    this.trailing,
  });

  final Widget leading;
  final Widget body;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    // Flat: the row sits in a grouped card (_Group) with its neighbours.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(child: body),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// A person: round avatar, name with verified tick, church/place
/// subtitle, and an inline Add.
class _PersonResultRow extends StatelessWidget {
  const _PersonResultRow({
    required this.person,
    required this.query,
    required this.state,
    required this.busy,
    required this.onAdd,
    required this.onTap,
    this.mutualFriends,
  });

  /// Real count of friends in common, when known.
  final int? mutualFriends;

  final MemberDirectoryEntry person;
  final String query;
  final _FriendState state;
  final bool busy;
  final VoidCallback onAdd;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = (person.fullName ?? '').trim().isEmpty
        ? 'Member'
        : person.fullName!.trim();
    final parts = <String>[
      if (state == _FriendState.friends)
        'Friend'
      else if ((mutualFriends ?? 0) > 0)
        '$mutualFriends mutual friend${mutualFriends == 1 ? '' : 's'}',
      if ((person.churchName ?? '').trim().isNotEmpty)
        person.churchName!.trim(),
      if ((person.profession ?? '').trim().isNotEmpty)
        person.profession!.trim(),
      if ((person.city ?? '').trim().isNotEmpty) person.city!.trim(),
    ];
    return _ResultShell(
      onTap: onTap,
      leading: _PersonAvatar(
        photoUrl: person.profilePhotoUrl,
        fullName: name,
        size: 60,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: _HighlightedText(
                  text: name,
                  query: query,
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (person.isVerified) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.verified,
                  color: AppColors.goldAccent,
                  size: 15,
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          _HighlightedText(
            text: parts.isEmpty
                ? 'On Adventist Super App'
                : parts.join('  ·  '),
            query: query,
            style: AppTextStyles.bodySmall.copyWith(
              color: context.palette.textMuted,
            ),
          ),
        ],
      ),
      trailing: switch (state) {
        _FriendState.friends => InlineAction(
          label: 'Friends',
          icon: Icons.check,
          filled: false,
          onTap: null,
        ),
        _FriendState.pending => InlineAction(
          label: 'Pending',
          icon: Icons.hourglass_top_rounded,
          filled: false,
          onTap: null,
        ),
        _FriendState.none => InlineAction(
          label: 'Add',
          icon: Icons.person_add_alt_1,
          busy: busy,
          onTap: onAdd,
        ),
      },
    );
  }
}

/// A church: square logo (churches have logos, not faces), city and
/// member count, and an inline Follow.
class _ChurchResultRow extends StatelessWidget {
  const _ChurchResultRow({
    required this.church,
    required this.query,
    required this.following,
    required this.isHomeChurch,
    required this.busy,
    required this.onToggleFollow,
    required this.onTap,
  });

  final Church church;
  final String query;
  final bool following;

  /// This row IS the viewer's home church (`profiles.church_id`).
  final bool isHomeChurch;

  final bool busy;
  final VoidCallback onToggleFollow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final logo = (church.profilePhotoUrl ?? '').trim();
    final members = church.membersCount;
    final subtitle = [
      if (church.city.trim().isNotEmpty) church.city.trim(),
      if (members > 0) '$members member${members == 1 ? '' : 's'}',
    ].join('  ·  ');
    return _ResultShell(
      onTap: onTap,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: logo.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: logo,
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                placeholder: (_, _) => const _ChurchGlyph(),
                errorWidget: (_, _, _) => const _ChurchGlyph(),
              )
            : const _ChurchGlyph(),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: _HighlightedText(
                  text: church.name,
                  query: query,
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (church.isVerified) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.verified,
                  color: AppColors.goldAccent,
                  size: 15,
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          _HighlightedText(
            text: subtitle.isEmpty ? 'SDA church' : subtitle,
            query: query,
            style: AppTextStyles.bodySmall.copyWith(
              color: context.palette.textMuted,
            ),
          ),
        ],
      ),
      // Only the home church gets an action.
      //
      //  * home church, followed      → a quiet "Home church" marker.
      //  * home church, not yet       → "Follow", the one legal follow.
      //  * anything else, followed    → "Following", so historic rows
      //                                 collected before this rule can
      //                                 still be undone from here.
      //  * anything else, not         → nothing. Tapping the row still
      //                                 opens the church, which is where
      //                                 "make this my home church" is
      //                                 explained properly.
      trailing: switch ((isHomeChurch, following)) {
        (true, true) => InlineAction(
          label: 'Home church',
          icon: Icons.home_rounded,
          filled: false,
          busy: busy,
          onTap: onToggleFollow,
        ),
        (true, false) => InlineAction(
          label: 'Follow',
          icon: Icons.add,
          filled: true,
          busy: busy,
          onTap: onToggleFollow,
        ),
        (false, true) => InlineAction(
          label: 'Following',
          icon: Icons.check,
          filled: false,
          busy: busy,
          onTap: onToggleFollow,
        ),
        (false, false) => null,
      },
    );
  }
}

class _ChurchGlyph extends StatelessWidget {
  const _ChurchGlyph();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(11),
      ),
      child: const Icon(Icons.church, color: AppColors.white, size: 21),
    );
  }
}

/// An event: a date block instead of an avatar, because the first thing
/// you need from an event is when it is. Plus an inline RSVP.
class _EventResultRow extends StatelessWidget {
  const _EventResultRow({
    required this.event,
    required this.query,
    required this.going,
    required this.busy,
    required this.onToggleRsvp,
    required this.onTap,
  });

  final Event event;
  final String query;
  final bool going;
  final bool busy;
  final VoidCallback onToggleRsvp;
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
    final date = event.eventDate;
    final subtitle = [
      event.eventTime,
      if ((event.location ?? '').trim().isNotEmpty) event.location!.trim(),
      if (event.rsvpCount > 0) '${event.rsvpCount} going',
    ].join('  ·  ');
    return _ResultShell(
      onTap: onTap,
      leading: Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.primaryBlue.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${date.day}',
              style: AppTextStyles.titleSmall.copyWith(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w800,
                fontSize: 15,
                height: 1.05,
              ),
            ),
            Text(
              _months[(date.month - 1).clamp(0, 11)],
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w800,
                fontSize: 8.5,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HighlightedText(
            text: event.title,
            query: query,
            style: AppTextStyles.titleSmall.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          _HighlightedText(
            text: subtitle,
            query: query,
            style: AppTextStyles.bodySmall.copyWith(
              color: context.palette.textMuted,
            ),
          ),
        ],
      ),
      trailing: InlineAction(
        label: going ? 'Going' : 'RSVP',
        icon: going ? Icons.check : Icons.event_available,
        filled: !going,
        busy: busy,
        onTap: onToggleRsvp,
      ),
    );
  }
}

/// A post: the author, and the sentence that actually matched — not the
/// first 140 characters of the body regardless of where the hit was.
class _PostResultRow extends StatelessWidget {
  const _PostResultRow({
    required this.post,
    required this.query,
    required this.onTap,
  });

  final Post post;
  final String query;
  final VoidCallback onTap;

  /// Window the body around the first hit so the highlighted term is
  /// visible in a two-line preview. A match 400 characters in is
  /// invisible if you always start from the beginning.
  String _snippet() {
    final body = (post.body ?? '').trim();
    if (body.isEmpty) return '(photo post)';
    final hit = body.toLowerCase().indexOf(query.trim().toLowerCase());
    if (hit <= 60 || query.trim().isEmpty) {
      return body.length > 160 ? '${body.substring(0, 160)}…' : body;
    }
    final start = hit - 40;
    final end = (hit + 120).clamp(0, body.length);
    return '…${body.substring(start, end)}${end < body.length ? '…' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    return _ResultShell(
      onTap: onTap,
      leading: _PersonAvatar(
        photoUrl: post.authorPhotoUrl,
        fullName: post.authorName,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HighlightedText(
            text: post.authorName,
            query: query,
            style: AppTextStyles.titleSmall.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          _HighlightedText(
            text: _snippet(),
            query: query,
            maxLines: 2,
            style: AppTextStyles.bodySmall.copyWith(
              color: context.palette.textMuted,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// A product: square photo (it is the product), price and seller.
/// A job: role, then company and place — the two things you screen on.
class _JobResultRow extends StatelessWidget {
  const _JobResultRow({
    required this.job,
    required this.query,
    required this.onTap,
  });

  final Job job;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final loc = (job.location ?? '').trim();
    return _ResultShell(
      onTap: onTap,
      leading: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.goldAccent.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(11),
        ),
        child: const Icon(
          Icons.work_outline,
          color: Color(0xFF8A6D1F),
          size: 20,
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HighlightedText(
            text: job.title,
            query: query,
            style: AppTextStyles.titleSmall.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          _HighlightedText(
            text: loc.isEmpty ? job.company : '${job.company}  ·  $loc',
            query: query,
            style: AppTextStyles.bodySmall.copyWith(
              color: context.palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonAvatar extends StatelessWidget {
  const _PersonAvatar({
    required this.photoUrl,
    required this.fullName,
    this.size = 44,
  });
  final String? photoUrl;
  final String fullName;
  final double size;

  String get _initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = (photoUrl ?? '').trim().isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primaryBlue.withValues(alpha: 0.10),
        image: hasPhoto
            ? DecorationImage(
                // Asked for at 3x the drawn size. The stored Google URL is
                // `=s96-c`, a 96px thumbnail — upscaled and soft otherwise.
                image: CachedNetworkImageProvider(
                  photoUrlAtSize(photoUrl, (size * 3).round()),
                  cacheManager: adventImageCacheManager,
                ),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: hasPhoto
          ? null
          : Text(
              _initials,
              style: AppTextStyles.labelMedium.copyWith(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.3,
              ),
            ),
    );
  }
}

class _ChurchRow extends StatelessWidget {
  const _ChurchRow({required this.church, required this.onTap});
  final Church church;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressEffect(
      child: _Row(
        icon: Icons.church,
        title: church.name,
        subtitle: church.city,
        onTap: onTap,
        trailing: church.isVerified
            ? const Icon(Icons.verified, color: AppColors.goldAccent, size: 16)
            : null,
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.onTap});
  final Event event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Row(
      icon: Icons.event,
      imageUrl: event.coverPhotoUrl,
      title: event.title,
      subtitle:
          '${event.eventDate.day}/${event.eventDate.month}  ·  ${event.eventTime}${event.location != null ? "  ·  ${event.location}" : ""}',
      onTap: onTap,
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.onTap});
  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Row(
      icon: Icons.shopping_bag_outlined,
      imageUrl: product.firstImage,
      title: product.title,
      subtitle: '${product.formatPrice()}  ·  ${product.sellerName}',
      onTap: onTap,
    );
  }
}

class _JobRow extends StatelessWidget {
  const _JobRow({required this.job, required this.onTap});
  final Job job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final loc = (job.location ?? '').trim();
    final companyLine = loc.isEmpty ? job.company : '${job.company}  ·  $loc';
    return _Row(
      icon: Icons.work_outline,
      title: job.title,
      subtitle: companyLine,
      onTap: onTap,
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.imageUrl,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  // When set, the leading shows this image (product photo / event flyer)
  // instead of the generic icon.
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              if ((imageUrl ?? '').isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl!,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(
                      width: 52,
                      height: 52,
                      color: AppColors.primaryBlue.withValues(alpha: 0.10),
                    ),
                    errorWidget: (_, _, _) => Container(
                      width: 52,
                      height: 52,
                      color: AppColors.primaryBlue.withValues(alpha: 0.10),
                      child: Icon(icon, color: AppColors.primaryBlue, size: 20),
                    ),
                  ),
                )
              else
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: AppColors.primaryBlue, size: 20),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.titleSmall.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (trailing != null) ...[
                          const SizedBox(width: 6),
                          trailing!,
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: context.palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: context.palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// One "did you mean…" row.
///
/// Deliberately plainer than [_PersonResultRow] and the church row: these
/// are guesses, not matches. Giving them the full result treatment — the
/// Add-friend button, the follower counts, the query highlighting — would
/// dress a suggestion up as something the search actually found, and the
/// highlighting in particular would be a lie, because the whole reason
/// this row exists is that the text does NOT contain what was typed.
class _DidYouMeanRow extends StatelessWidget {
  const _DidYouMeanRow({required this.suggestion, required this.onTap});

  final SearchSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final photo = (suggestion.photoUrl ?? '').trim();
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.cardMuted,
              ),
              child: photo.isNotEmpty
                  ? CachedImage(photo, fit: BoxFit.cover, width: 40, height: 40)
                  : Icon(
                      suggestion.isPerson
                          ? Icons.person_outline
                          : Icons.church_outlined,
                      size: 20,
                      color: palette.textMuted,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    suggestion.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.titleSmall.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    suggestion.sublabel?.trim().isNotEmpty == true
                        ? suggestion.sublabel!
                        : (suggestion.isPerson ? 'Member' : 'SDA church'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: palette.textMuted),
          ],
        ),
      ),
    );
  }
}
