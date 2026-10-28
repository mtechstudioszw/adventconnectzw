import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/countries.dart';
import '../../models/job_model.dart';
import '../../services/auth_service.dart';
import '../../services/cache_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/job_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/ads/ad_banner.dart';
import '../../widgets/country_scope_toggle.dart';
import '../../widgets/job_card.dart';
import '../../widgets/jobs/job_filter_sheet.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/hide_on_scroll.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/motion/staggered_reveal.dart';
import '../../widgets/offline_inline_notice.dart';
import '../../widgets/screen_shell.dart';
import '../../widgets/shimmer_loaders.dart';
import '../widgets/post_form_widgets.dart';

/// Jobs landing (redesign, 28 Oct 2026, brief §15).
///
/// One scroll, top to bottom: title with "My job posts", search (role,
/// employer, skill or town), the Shop/Jobs switch, country scope, field
/// chips, a Filters row (type, experience, arrangement, vacancies vs
/// people looking, Sabbath-friendly, Adventist employers), the member's
/// saved jobs, then the latest listings. No "recommended for you" —
/// nothing here personalises, so nothing claims to.
class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key});

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> with NavVisibilityMixin {
  final _searchController = TextEditingController();
  Timer? _debounce;

  List<Job> _jobs = [];
  List<Job> _saved = const [];
  String? _category;
  JobFilters _filters = JobFilters.none;

  /// Jobs are scoped to the member's own country unless they ask for
  /// worldwide: almost every posting is a local role with a phone number.
  bool _worldwide = false;
  final String _country = AuthService.currentCountry();
  bool _loading = true;
  String? _error;

  static const _cacheKey = 'jobs_list';

  bool get _browsing =>
      _searchController.text.trim().isEmpty &&
      _category == null &&
      _filters.isEmpty;

  @override
  void initState() {
    super.initState();
    _hydrateFromCache();
    _loadJobs();
    JobService.savedIds.addListener(_loadSavedJobs);
    JobService.loadSaved();
  }

  @override
  void dispose() {
    JobService.savedIds.removeListener(_loadSavedJobs);
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _hydrateFromCache() {
    try {
      final raw = CacheService.readString(_cacheKey);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List)
          .map((e) => Job.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!mounted || list.isEmpty) return;
      setState(() {
        _jobs = list;
        _loading = false;
      });
    } catch (_) {}
  }

  Future<void> _writeCache(List<Job> list) async {
    try {
      await CacheService.writeString(
        _cacheKey,
        jsonEncode(list.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> _loadSavedJobs() async {
    try {
      final jobs = await JobService.fetchSavedJobs();
      if (!mounted) return;
      setState(() => _saved = jobs.where((j) => j.isOpen).toList());
    } catch (_) {}
  }

  Future<void> _loadJobs() async {
    setState(() {
      if (_jobs.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final list = await JobService.fetchJobs(
        search: _searchController.text,
        category: _category,
        filters: _filters,
        country: _worldwide ? null : _country,
      );
      if (!mounted) return;
      setState(() {
        _jobs = list;
        _loading = false;
      });
      // Only the default view is cached — a filtered or worldwide list
      // would greet the member with the wrong jobs on the next cold start.
      if (_browsing && !_worldwide) unawaited(_writeCache(list));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load jobs. Pull to retry.';
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _loadJobs);
  }

  Future<void> _openFilters() async {
    final picked = await showJobFilterSheet(context, current: _filters);
    if (picked == null || !mounted) return;
    setState(() => _filters = picked);
    _loadJobs();
  }

  Future<void> _toggleSaved(Job job) async {
    final saved = JobService.savedIds.value.contains(job.id);
    try {
      await JobService.setSaved(job.id, !saved);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !JobService.savedAvailable
                ? 'Saving jobs needs a database update (patch_278).'
                : 'Sign in to save jobs.',
          ),
        ),
      );
    }
  }

  void _open(Job j) =>
      context.pushNamed('job_details', pathParameters: {'id': j.id}, extra: j);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      bottomNavigationBar: const SafeArea(top: false, child: AdBanner()),
      // The empty state carries its own two post buttons; a FAB on top of
      // them would cover the second.
      floatingActionButton: !_loading && _jobs.isEmpty && _browsing
          ? null
          : PostFab(
              routeName: 'post_job',
              tooltip: 'Post a job',
              onCreated: _loadJobs,
            ),
      body: NotificationListener<UserScrollNotification>(
        onNotification: handleNavScroll,
        child: BrandedRefreshIndicator(
          color: AppColors.primaryBlue,
          onRefresh: () async {
            await Future.wait([_loadJobs(), JobService.loadSaved()]);
          },
          child: ValueListenableBuilder<Set<String>>(
            valueListenable: JobService.savedIds,
            builder: (context, savedIds, _) => CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: ScreenHero(
                    title: 'Jobs',
                    tagline: 'MARKETPLACE',
                    subtitle: 'Work and opportunities in the community',
                    fallbackRoute: 'marketplace',
                    trailing: AuthService.currentUser == null
                        ? null
                        : HeaderIconButton(
                            icon: Icons.work_history_outlined,
                            tooltip: 'My job posts',
                            onTap: () => context.pushNamed('my_jobs'),
                          ),
                  ),
                ),
                SliverToBoxAdapter(child: _buildSearchBar()),
                const SliverToBoxAdapter(
                  child: _ShopJobsSegment(active: _Section.jobs),
                ),
                SliverToBoxAdapter(child: _buildScope()),
                SliverToBoxAdapter(child: _buildCategoryStrip()),
                SliverToBoxAdapter(child: _buildFilterRow()),
                if (_browsing && _saved.isNotEmpty)
                  SliverToBoxAdapter(child: _buildSavedRail(savedIds)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                    child: Text(
                      _browsing ? 'Latest' : 'Results',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: context.palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                ..._buildListSlivers(savedIds),
                const SliverToBoxAdapter(child: SizedBox(height: 96)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        style: AppTextStyles.bodyMedium.copyWith(color: palette.text),
        decoration: InputDecoration(
          hintText: 'Role, employer, skill or town',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    _searchController.clear();
                    _loadJobs();
                  },
                ),
          filled: true,
          fillColor: palette.card,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: palette.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: palette.divider),
          ),
        ),
      ),
    );
  }

  Widget _buildScope() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: CountryScopeToggle(
          countryCode: _country,
          worldwide: _worldwide,
          onChanged: (v) {
            setState(() => _worldwide = v);
            _loadJobs();
          },
        ),
      ),
    );
  }

  Widget _buildCategoryStrip() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _Chip(
            label: 'All fields',
            selected: _category == null,
            onTap: () {
              setState(() => _category = null);
              _loadJobs();
            },
          ),
          for (final c in JobCategory.all)
            _Chip(
              label: c.label,
              icon: c.icon,
              selected: _category == c.id,
              onTap: () {
                setState(() => _category = c.id);
                _loadJobs();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildFilterRow() {
    final palette = context.palette;
    final n = _filters.activeCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          Material(
            color: n > 0 ? AppColors.primaryBlue : palette.card,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: _openFilters,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: n > 0 ? null : Border.all(color: palette.divider),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 18,
                      color: n > 0 ? AppColors.white : palette.text,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      n > 0 ? 'Filters · $n' : 'Filters',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: n > 0 ? AppColors.white : palette.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (n > 0)
            TextButton(
              onPressed: () {
                setState(() => _filters = JobFilters.none);
                _loadJobs();
              },
              child: const Text('Clear'),
            ),
          const Spacer(),
          if (!_loading)
            Text(
              '${_jobs.length} listing${_jobs.length == 1 ? '' : 's'}',
              style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
            ),
        ],
      ),
    );
  }

  Widget _buildSavedRail(Set<String> savedIds) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
          child: Text(
            'Saved',
            style: AppTextStyles.titleMedium.copyWith(
              color: context.palette.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(
          height: 156,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _saved.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => SizedBox(
              width: 290,
              child: JobCard(
                job: _saved[i],
                onTap: () => _open(_saved[i]),
                saved: true,
                onToggleSave: () => _toggleSaved(_saved[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildListSlivers(Set<String> savedIds) {
    if (_loading && _jobs.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          // cardList is a ListView; a sliver gives it no height.
          child: SizedBox(
            height: 560,
            child: ShimmerLoaders.cardList(count: 5),
          ),
        ),
      ];
    }
    if (_error != null && _jobs.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: !ConnectivityService.isOnline
              ? OfflineInlineNotice(onRetry: _loadJobs)
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: EmptyStateCard(
                    icon: Icons.cloud_off_outlined,
                    title: "Couldn't load jobs",
                    message: _error!,
                  ),
                ),
        ),
      ];
    }
    if (_jobs.isEmpty) {
      return [SliverToBoxAdapter(child: _buildEmpty())];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.separated(
          itemCount: _jobs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final j = _jobs[i];
            final card = JobCard(
              job: j,
              onTap: () => _open(j),
              saved: AuthService.currentUser == null
                  ? null
                  : savedIds.contains(j.id),
              onToggleSave: () => _toggleSaved(j),
            );
            if (i >= 8) return card;
            return StaggeredReveal(index: i, rise: 18, child: card);
          },
        ),
      ),
    ];
  }

  /// Nothing posted yet is the real state today — say so warmly, and give
  /// both sides of the market a first step.
  Widget _buildEmpty() {
    final palette = context.palette;
    final filtered = !_browsing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(
              filtered ? Icons.search_off_rounded : Icons.work_outline,
              color: AppColors.primaryBlue,
              size: 40,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            filtered
                ? 'No jobs match'
                : _worldwide
                ? 'No jobs posted yet'
                : 'No jobs in ${Countries.nameOf(_country)} yet',
            textAlign: TextAlign.center,
            style: AppTextStyles.headlineSmall.copyWith(
              color: palette.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            filtered
                ? 'Try fewer filters or a different search.'
                : 'Hiring? Post a vacancy for the community. Looking for '
                      'work? Tell employers what you do.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: palette.textMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          if (!filtered) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  final made = await context.pushNamed<bool>('post_job');
                  if (made == true) _loadJobs();
                },
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Post a vacancy'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final made = await context.pushNamed<bool>(
                    'post_job',
                    queryParameters: {'type': 'seeking'},
                  );
                  if (made == true) _loadJobs();
                },
                icon: const Icon(Icons.person_search_outlined),
                label: const Text("I'm looking for work"),
              ),
            ),
          ],
          if (!_worldwide)
            TextButton.icon(
              onPressed: () {
                setState(() => _worldwide = true);
                _loadJobs();
              },
              icon: const Icon(Icons.public, size: 18),
              label: const Text('Browse worldwide'),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fg = selected ? AppColors.white : palette.text;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? AppColors.primaryBlue : palette.card,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: selected ? null : Border.all(color: palette.divider),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: fg,
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

enum _Section { shop, jobs }

class _ShopJobsSegment extends StatelessWidget {
  const _ShopJobsSegment({required this.active});
  final _Section active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            _SegmentButton(
              label: 'Shop',
              icon: Icons.shopping_bag_outlined,
              selected: active == _Section.shop,
              onTap: active == _Section.shop
                  ? null
                  : () => context.goNamed('marketplace'),
            ),
            const SizedBox(width: 6),
            _SegmentButton(
              label: 'Jobs',
              icon: Icons.work_outline,
              selected: active == _Section.jobs,
              onTap: active == _Section.jobs
                  ? null
                  : () => context.goNamed('jobs'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

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
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: selected ? AppColors.primaryGradient : null,
                borderRadius: BorderRadius.circular(10),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: AppColors.primaryBlue.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : [],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: selected ? AppColors.white : AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: AppTextStyles.labelMedium.copyWith(
                      color: selected ? AppColors.white : AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
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
