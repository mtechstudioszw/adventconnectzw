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
import '../../services/secure_storage_service.dart';
import '../../widgets/cached_image.dart';
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

enum _Filter { all, people, posts, churches, events, marketplace, jobs, videos }

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

  Future<void> _toggleFollowChurch(String churchId) async {
    if (_actionBusy.contains(churchId)) return;
    final following = _followedChurchIds.contains(churchId);
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

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _runSearch(value.trim());
    });
  }

  void _submit(String value) {
    _debounce?.cancel();
    _runSearch(value.trim());
  }

  void _useRecent(String query) {
    _controller.text = query;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: query.length),
    );
    _focusNode.requestFocus();
    _runSearch(query);
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
      safe(() => ChurchService.fetchChurches(search: query)),
      safe(() => EventService.fetchEvents(search: query)),
      safe(() => MarketplaceService.fetchProducts(search: query)),
      safe(() => JobService.fetchJobs(search: query)),
      safe(() => FeedService.searchPosts(query)),
      safe(() => YoutubeService.search(query, limit: 12)),
    ]);
    if (!mounted) return;
    final people = (results[0] as List<MemberDirectoryEntry>).take(12).toList();
    final churches = (results[1] as List<Church>).take(12).toList();
    final events = (results[2] as List<Event>).take(12).toList();
    final products = (results[3] as List<Product>).take(12).toList();
    final jobs = (results[4] as List<Job>).take(12).toList();
    final posts = (results[5] as List<Post>).take(12).toList();
    final videos = (results[6] as List<YoutubeVideo>).take(12).toList();
    setState(() {
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
    final hasAny =
        people.isNotEmpty ||
        churches.isNotEmpty ||
        events.isNotEmpty ||
        products.isNotEmpty ||
        jobs.isNotEmpty ||
        posts.isNotEmpty ||
        videos.isNotEmpty;
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
    return _suggestedFuture ??=
        DirectoryService.fetchSuggestedMembers(limit: 80);
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
      _churches.isNotEmpty ||
      _events.isNotEmpty ||
      _products.isNotEmpty ||
      _jobs.isNotEmpty ||
      _posts.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildSearchBar(),
            if (_lastQuery.isNotEmpty && _hasResults) _buildFilterChips(),
            Expanded(
              // Row-shaped shimmer while searching, crossfading into
              // whichever state lands (results / recent / empty).
              child: ContentReveal(
                loading: _searching,
                skeleton: ShimmerLoaders.peopleList(),
                child: _lastQuery.isEmpty
                    ? _buildRecent()
                    : _hasResults
                    ? _buildResults()
                    : _buildEmpty(),
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
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    // Each scope carries its own glyph. With eight text-only pills the
    // rail was a wall of similar words you had to read one by one; an
    // icon makes the one you want findable at a glance, and makes the
    // active chip obvious from the corner of the eye.
    final chips = <_FilterDef>[
      const _FilterDef(_Filter.all, 'All', Icons.auto_awesome_rounded),
      const _FilterDef(_Filter.videos, 'Videos', Icons.play_circle_outline),
      const _FilterDef(_Filter.people, 'People', Icons.people_alt_outlined),
      const _FilterDef(_Filter.posts, 'Posts', Icons.article_outlined),
      const _FilterDef(_Filter.churches, 'Churches', Icons.church_outlined),
      const _FilterDef(_Filter.events, 'Events', Icons.event_outlined),
      const _FilterDef(
        _Filter.marketplace,
        'Marketplace',
        Icons.storefront_outlined,
      ),
      const _FilterDef(_Filter.jobs, 'Jobs', Icons.work_outline_rounded),
    ];
    return Container(
      // Transparent, like the search bar above it — together they form the
      // top region of this screen, and painting either one opaque leaves a
      // band where the ambient field stops dead.
      color: Colors.transparent,
      padding: const EdgeInsets.only(bottom: 10),
      // No fixed height. The rail used to be pinned at 38dp with text
      // inside it that scales with the system font — at large
      // accessibility sizes the labels simply clipped (silently: there is
      // no Flex here, so nothing throws). Let the content size the row.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            for (var i = 0; i < chips.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _FilterChip(
                label: chips[i].label,
                icon: chips[i].icon,
                active: chips[i].filter == _filter,
                onTap: () {
                  if (chips[i].filter == _filter) return;
                  setState(() => _filter = chips[i].filter);
                  // The list underneath is now a different set of rows,
                  // so it arrives rather than swapping in place.
                  _replayListEnter();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecent() {
    final shown = _seeAllRecent
        ? _recent
        : _recent.take(5).toList(growable: false);
    return ListView(
      // Was 8 here + 16 on the first section = 24dp of stacked dead space
      // under the field before anything readable started.
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 24),
      children: [
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
          actionLabel: _suggestions.length > 6
              ? (_seeAllSuggestions ? 'Show less' : 'See all')
              : null,
          onAction: _suggestions.length > 6
              ? () => setState(() => _seeAllSuggestions = !_seeAllSuggestions)
              : null,
        ),
      );
      sections.add(
        _landingList([
          // Same rich row as the results list — so the landing state is
          // somewhere you can actually add people, not just a list of
          // links back into the profile screen.
          for (final p
              in (_seeAllSuggestions ? _suggestions : _suggestions.take(6)))
            _PersonResultRow(
              person: p,
              query: '',
              state: _friendIds.contains(p.userId)
                  ? _FriendState.friends
                  : _pendingFriendIds.contains(p.userId)
                  ? _FriendState.pending
                  : _FriendState.none,
              busy: _actionBusy.contains(p.userId),
              onAdd: () => _addFriend(p.userId),
              onTap: () => context.pushNamed(
                'user_profile',
                pathParameters: {'userId': p.userId},
              ),
            ),
        ]),
      );
    }

    if (_suggVideos.isNotEmpty) {
      sections.add(
        _landingHeader(
          'Videos to watch',
          actionLabel: 'See all',
          onAction: () => context.goNamed('watch'),
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
          onAction: () => context.goNamed('jobs'),
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

  Widget _landingList(List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (final r in rows)
            Padding(padding: const EdgeInsets.only(bottom: 10), child: r),
        ],
      ),
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

    final anyForFilter =
        showPeople ||
        showPosts ||
        showChurches ||
        showEvents ||
        showProducts ||
        showJobs ||
        showVideos;

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
    List<T> cap<T>(List<T> items) =>
        grouped ? items.take(allCap).toList() : items;

    final sections = <Widget>[
      if (showPeople)
        _Section(
          label: 'PEOPLE',
          count: _people.length,
          onSeeAll: grouped && _people.length > allCap
              ? () => setState(() => _filter = _Filter.people)
              : null,
          children: [
            for (final p in cap(_people))
              _PersonResultRow(
                person: p,
                query: _lastQuery,
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
          ],
        ),
      if (showChurches)
        _Section(
          label: 'CHURCHES',
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
          label: 'EVENTS',
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
          label: 'POSTS',
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
          label: 'VIDEOS',
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
          label: 'MARKETPLACE',
          count: _products.length,
          onSeeAll: grouped && _products.length > allCap
              ? () => setState(() => _filter = _Filter.marketplace)
              : null,
          children: [
            for (final p in cap(_products))
              _ProductResultRow(
                product: p,
                query: _lastQuery,
                onTap: () => _openResult(
                  _lastQuery,
                  () => context.pushNamed(
                    'product_details',
                    pathParameters: {'id': p.id},
                    extra: p,
                  ),
                ),
              ),
          ],
        ),
      if (showJobs)
        _Section(
          label: 'JOBS',
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

class _FilterDef {
  const _FilterDef(this.filter, this.label, this.icon);
  final _Filter filter;
  final String label;
  final IconData icon;
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return PressEffect(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          // Animated rather than a hard colour swap: the selected chip
          // fills, its border lights and a soft blue shadow settles under
          // it, so the eye can follow the selection moving along the rail
          // instead of two chips blinking at once.
          child: AnimatedContainer(
            duration: AppMotion.maybe(context, AppMotion.quick),
            curve: AppMotion.ease,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              gradient: active ? AppColors.primaryGradient : null,
              color: active ? null : palette.chipBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: active ? Colors.transparent : palette.divider,
              ),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: AppColors.primaryBlue.withValues(alpha: 0.28),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: active ? AppColors.white : palette.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: active ? AppColors.white : palette.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
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
  });
  final String label;
  final int count;
  final List<Widget> children;

  /// Non-null only when the section is truncated on the "All" scope.
  /// Switches the chip filter to this type rather than expanding in
  /// place — the chips already exist, this just makes them discoverable
  /// from the results instead of requiring you to plan ahead.
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Text(
                label,
                style: AppTextStyles.labelSmall.copyWith(
                  color: context.palette.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$count',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.primaryBlue,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              if (onSeeAll != null)
                GestureDetector(
                  onTap: onSeeAll,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    child: Text(
                      'See all $count',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: AppColors.primaryBlue,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (final c in children) ...[c, const SizedBox(height: 10)],
        const SizedBox(height: 6),
      ],
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
    return PressEffect(
      child: ScreenCard(
        padding: const EdgeInsets.all(12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
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
  });

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
      if ((person.churchName ?? '').trim().isNotEmpty)
        person.churchName!.trim(),
      if ((person.profession ?? '').trim().isNotEmpty)
        person.profession!.trim(),
      if ((person.city ?? '').trim().isNotEmpty) person.city!.trim(),
    ];
    return _ResultShell(
      onTap: onTap,
      leading: _PersonAvatar(photoUrl: person.profilePhotoUrl, fullName: name),
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
            text: parts.isEmpty ? 'On Adventist Super App' : parts.join('  ·  '),
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
    required this.busy,
    required this.onToggleFollow,
    required this.onTap,
  });

  final Church church;
  final String query;
  final bool following;
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
                width: 44,
                height: 44,
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
      trailing: InlineAction(
        label: following ? 'Following' : 'Follow',
        icon: following ? Icons.check : Icons.add,
        filled: !following,
        busy: busy,
        onTap: onToggleFollow,
      ),
    );
  }
}

class _ChurchGlyph extends StatelessWidget {
  const _ChurchGlyph();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
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
        width: 44,
        height: 44,
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
class _ProductResultRow extends StatelessWidget {
  const _ProductResultRow({
    required this.product,
    required this.query,
    required this.onTap,
  });

  final Product product;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final image = product.firstImage.trim();
    return _ResultShell(
      onTap: onTap,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: image.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: image,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                placeholder: (_, _) => const _ProductGlyph(),
                errorWidget: (_, _, _) => const _ProductGlyph(),
              )
            : const _ProductGlyph(),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HighlightedText(
            text: product.title,
            query: query,
            style: AppTextStyles.titleSmall.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                product.formatPrice(),
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _HighlightedText(
                  text: product.sellerName,
                  query: query,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: context.palette.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProductGlyph extends StatelessWidget {
  const _ProductGlyph();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(11),
      ),
      child: const Icon(
        Icons.shopping_bag_outlined,
        color: AppColors.primaryBlue,
        size: 20,
      ),
    );
  }
}

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
        width: 44,
        height: 44,
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
  const _PersonAvatar({required this.photoUrl, required this.fullName});
  final String? photoUrl;
  final String fullName;

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
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primaryBlue.withValues(alpha: 0.10),
        image: hasPhoto
            ? DecorationImage(
                image: CachedNetworkImageProvider(photoUrl!),
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
                fontSize: 13,
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
    return ScreenCard(
      padding: const EdgeInsets.all(14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Row(
            children: [
              if ((imageUrl ?? '').isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl!,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(
                      width: 44,
                      height: 44,
                      color: AppColors.primaryBlue.withValues(alpha: 0.10),
                    ),
                    errorWidget: (_, _, _) => Container(
                      width: 44,
                      height: 44,
                      color: AppColors.primaryBlue.withValues(alpha: 0.10),
                      child: Icon(icon, color: AppColors.primaryBlue, size: 20),
                    ),
                  ),
                )
              else
                Container(
                  width: 44,
                  height: 44,
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
