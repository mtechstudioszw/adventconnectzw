import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/church_model.dart';
import '../../models/event_model.dart';
import '../../models/job_model.dart';
import '../../models/member_directory_model.dart';
import '../../models/post_model.dart';
import '../../models/product_model.dart';
import '../../services/church_service.dart';
import '../../services/directory_service.dart';
import '../../services/event_service.dart';
import '../../services/feed_service.dart';
import '../../services/job_service.dart';
import '../../services/marketplace_service.dart';
import '../../services/secure_storage_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/screen_shell.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

enum _Filter { all, people, posts, churches, events, marketplace, jobs }

class _SearchScreenState extends State<SearchScreen> {
  static const _recentKey = 'recent_searches_v1';
  static const _maxRecent = 20;

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;

  bool _searching = false;
  String _lastQuery = '';
  _Filter _filter = _Filter.all;

  List<Church> _churches = const [];
  List<Event> _events = const [];
  List<Product> _products = const [];
  List<Job> _jobs = const [];
  List<MemberDirectoryEntry> _people = const [];
  List<Post> _posts = const [];

  // Fallback list — surfaced when the query has no matches. Loaded
  // lazily the first time we hit an empty-result state.
  List<MemberDirectoryEntry> _fallbackPeople = const [];
  bool _fallbackLoading = false;

  List<String> _recent = const [];
  bool _seeAllRecent = false;

  @override
  void initState() {
    super.initState();
    _loadRecent();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
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
    ]);
    if (!mounted) return;
    final people = (results[0] as List<MemberDirectoryEntry>).take(12).toList();
    final churches = (results[1] as List<Church>).take(12).toList();
    final events = (results[2] as List<Event>).take(12).toList();
    final products = (results[3] as List<Product>).take(12).toList();
    final jobs = (results[4] as List<Job>).take(12).toList();
    final posts = (results[5] as List<Post>).take(12).toList();
    setState(() {
      _people = people;
      _churches = churches;
      _events = events;
      _products = products;
      _jobs = jobs;
      _posts = posts;
      _searching = false;
    });
    final hasAny = people.isNotEmpty ||
        churches.isNotEmpty ||
        events.isNotEmpty ||
        products.isNotEmpty ||
        jobs.isNotEmpty ||
        posts.isNotEmpty;
    if (!hasAny) {
      _loadFallback();
    }
  }

  Future<void> _loadFallback() async {
    if (_fallbackLoading) return;
    if (_fallbackPeople.isNotEmpty) return;
    _fallbackLoading = true;
    try {
      final list = await DirectoryService.fetchSuggestedMembers(limit: 30);
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
      safe(() => DirectoryService.fetchSuggestedMembers(limit: 80)),
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
      backgroundColor: AppColors.lightGrey,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildSearchBar(),
            if (_lastQuery.isNotEmpty && _hasResults) _buildFilterChips(),
            Expanded(
              child: _searching
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryBlue,
                      ),
                    )
                  : _lastQuery.isEmpty
                      ? _buildRecent()
                      : _hasResults
                          ? _buildResults()
                          : _buildEmpty(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 10),
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
            icon: const Icon(
              Icons.arrow_back,
              color: AppColors.textDark,
            ),
            splashRadius: 22,
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.lightGrey,
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                onChanged: _onChanged,
                onSubmitted: _submit,
                textInputAction: TextInputAction.search,
                style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                decoration: InputDecoration(
                  hintText:
                      'Search for friends, churches, events, products...',
                  hintStyle: AppTextStyles.bodyMedium.copyWith(
                    color: const Color.fromRGBO(26, 26, 46, 0.5),
                    fontSize: 14,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: Color.fromRGBO(26, 26, 46, 0.55),
                    size: 20,
                  ),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Color.fromRGBO(26, 26, 46, 0.55),
                            size: 18,
                          ),
                          onPressed: () {
                            _controller.clear();
                            _onChanged('');
                            setState(() {});
                          },
                        ),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    final chips = <_FilterDef>[
      const _FilterDef(_Filter.all, 'All'),
      const _FilterDef(_Filter.people, 'People'),
      const _FilterDef(_Filter.posts, 'Posts'),
      const _FilterDef(_Filter.churches, 'Churches'),
      const _FilterDef(_Filter.events, 'Events'),
      const _FilterDef(_Filter.marketplace, 'Marketplace'),
      const _FilterDef(_Filter.jobs, 'Jobs'),
    ];
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: chips.length,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (ctx, i) {
            final c = chips[i];
            final active = c.filter == _filter;
            return _FilterChip(
              label: c.label,
              active: active,
              onTap: () => setState(() => _filter = c.filter),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRecent() {
    if (_recent.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        children: [
          Text(
            'TRY SEARCHING FOR',
            style: AppTextStyles.labelSmall.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.55),
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
                _SuggestionTap(
                  label: s,
                  onTap: () => _useRecent(s),
                ),
            ],
          ),
        ],
      );
    }
    final shown =
        _seeAllRecent ? _recent : _recent.take(5).toList(growable: false);
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
      children: [
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
              if (_recent.isNotEmpty)
                TextButton(
                  onPressed: _clearRecent,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color.fromRGBO(26, 26, 46, 0.6),
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text(
                    'Clear',
                    style: AppTextStyles.labelLarge.copyWith(
                      color: const Color.fromRGBO(26, 26, 46, 0.6),
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
    );
  }

  Widget _buildEmpty() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        EmptyStateCard(
          icon: Icons.search_off,
          title: 'No matches for "$_lastQuery"',
          message:
              'Try a shorter keyword or different spelling. '
              'Here are people you might know instead.',
        ),
        const SizedBox(height: 16),
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
              child: _PersonRow(
                person: p,
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
        (_filter == _Filter.all || _filter == _Filter.jobs) &&
            _jobs.isNotEmpty;

    final anyForFilter = showPeople ||
        showPosts ||
        showChurches ||
        showEvents ||
        showProducts ||
        showJobs;

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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (showPeople)
          _Section(
            label: 'PEOPLE',
            count: _people.length,
            children: [
              for (final p in _people)
                _PersonRow(
                  person: p,
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
        if (showPosts)
          _Section(
            label: 'POSTS',
            count: _posts.length,
            children: [
              for (final post in _posts)
                _PostRow(
                  post: post,
                  onTap: () => _openResult(
                    _lastQuery,
                    () => Navigator.pop(context),
                  ),
                ),
            ],
          ),
        if (showChurches)
          _Section(
            label: 'CHURCHES',
            count: _churches.length,
            children: [
              for (final c in _churches)
                _ChurchRow(
                  church: c,
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
            children: [
              for (final e in _events)
                _EventRow(
                  event: e,
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
        if (showProducts)
          _Section(
            label: 'MARKETPLACE',
            count: _products.length,
            children: [
              for (final p in _products)
                _ProductRow(
                  product: p,
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
            children: [
              for (final j in _jobs)
                _JobRow(
                  job: j,
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
    }
  }
}

class _FilterDef {
  const _FilterDef(this.filter, this.label);
  final _Filter filter;
  final String label;
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? AppColors.primaryBlue
                : const Color.fromRGBO(26, 26, 46, 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active
                  ? AppColors.primaryBlue
                  : const Color.fromRGBO(26, 26, 46, 0.08),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppTextStyles.labelMedium.copyWith(
              color: active ? AppColors.white : AppColors.textDark,
              fontWeight: FontWeight.w700,
              fontSize: 13,
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
    return Material(
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
                  color: const Color.fromRGBO(26, 26, 46, 0.05),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.history,
                  color: AppColors.textDark,
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
                icon: const Icon(
                  Icons.close,
                  color: Color.fromRGBO(26, 26, 46, 0.5),
                  size: 18,
                ),
                splashRadius: 18,
              ),
            ],
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color.fromRGBO(26, 26, 46, 0.08),
            ),
          ),
          child: Text(
            label,
            style: AppTextStyles.labelMedium.copyWith(
              color: AppColors.textDark,
              fontWeight: FontWeight.w700,
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
  });
  final String label;
  final int count;
  final List<Widget> children;

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
                  color: const Color.fromRGBO(26, 26, 46, 0.55),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
            ],
          ),
        ),
        for (final c in children) ...[c, const SizedBox(height: 10)],
        const SizedBox(height: 6),
      ],
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person, required this.onTap});
  final MemberDirectoryEntry person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = (person.fullName ?? '').trim().isEmpty
        ? 'Member'
        : person.fullName!.trim();
    final parts = <String>[
      if ((person.profession ?? '').trim().isNotEmpty) person.profession!.trim(),
      if ((person.city ?? '').trim().isNotEmpty) person.city!.trim(),
      if ((person.churchName ?? '').trim().isNotEmpty) person.churchName!.trim(),
    ];
    final subtitle = parts.isEmpty ? 'On Advent Connect' : parts.join('  ·  ');
    return ScreenCard(
      padding: const EdgeInsets.all(14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Row(
            children: [
              _PersonAvatar(
                photoUrl: person.profilePhotoUrl,
                fullName: name,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: const Color.fromRGBO(26, 26, 46, 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.primaryBlue,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PostRow extends StatelessWidget {
  const _PostRow({required this.post, required this.onTap});

  final Post post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final body = (post.body ?? '').trim();
    final preview = body.isEmpty
        ? '(photo post)'
        : body.length > 140
            ? '${body.substring(0, 140)}…'
            : body;
    return ScreenCard(
      padding: const EdgeInsets.all(14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.article_outlined,
                  color: AppColors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preview,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: const Color.fromRGBO(26, 26, 46, 0.7),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
    return _Row(
      icon: Icons.church,
      title: church.name,
      subtitle: church.city,
      onTap: onTap,
      trailing: church.isVerified
          ? const Icon(Icons.verified, color: AppColors.goldAccent, size: 16)
          : null,
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
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

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
                        color: const Color.fromRGBO(26, 26, 46, 0.6),
                      ),
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
        ),
      ),
    );
  }
}
