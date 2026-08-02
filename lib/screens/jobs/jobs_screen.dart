import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import '../../widgets/screen_shell.dart';
import 'package:go_router/go_router.dart';
import '../../models/job_model.dart';
import '../../services/cache_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/job_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/ads/ad_banner.dart';
import '../../widgets/job_card.dart';
import '../../widgets/last_updated_strip.dart';
import '../../widgets/offline_inline_notice.dart';
import '../widgets/post_form_widgets.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/content_reveal.dart';
import '../../widgets/motion/hide_on_scroll.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/motion/staggered_reveal.dart';
import '../../widgets/shimmer_loaders.dart';

class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key});

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> with NavVisibilityMixin {
  final _searchController = TextEditingController();
  Timer? _debounce;

  List<Job> _jobs = [];
  String _selectedCategory = 'all';

  /// patch_039: 'all' | 'entry' | 'mid' | 'senior'. Second-row filter
  /// strip under categories so applicants can self-select tier.
  String _selectedLevel = 'all';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _hydrateFromCache();
    _loadJobs();
  }

  static const _cacheKey = 'jobs_list';

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
    } catch (_) {
      // ignore
    }
  }

  Future<void> _writeCache(List<Job> list) async {
    try {
      final payload = jsonEncode(list.map((e) => e.toJson()).toList());
      await CacheService.writeString(_cacheKey, payload);
    } catch (_) {}
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadJobs() async {
    setState(() {
      if (_jobs.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final list = await JobService.fetchJobs(
        search: _searchController.text,
        category: _selectedCategory,
        level: _selectedLevel == 'all' ? null : _selectedLevel,
      );
      if (!mounted) return;
      setState(() {
        _jobs = list;
        _loading = false;
      });
      // Cache the unfiltered list (no search, no category filter) so
      // the cache represents the full feed users land on first.
      if (_searchController.text.isEmpty &&
          _selectedCategory == 'all' &&
          _selectedLevel == 'all') {
        unawaited(_writeCache(list));
      }
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

  void _selectCategory(String id) {
    setState(() => _selectedCategory = id);
    _loadJobs();
  }

  void _selectLevel(String id) {
    setState(() => _selectedLevel = id);
    _loadJobs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      // No island: Jobs is pushed from Home, not a tab. It used to light
      // the Marketplace pill — the same lie Prayer told with the Profile
      // pill. Its ScreenHero already carries the back button.
      bottomNavigationBar: const SafeArea(top: false, child: AdBanner()),
      floatingActionButton: const PostFab(
        routeName: 'post_job',
        tooltip: 'Post a job',
      ),
      body: NotificationListener<UserScrollNotification>(
        onNotification: handleNavScroll,
        child: SizedBox(
          height: MediaQuery.of(context).size.height,
          child: Column(
            children: [
              _buildHero(),
              _buildSearchBar(),
              const _ShopJobsSegment(active: _Section.jobs),
              _buildCategoryStrip(),
              const SizedBox(height: 6),
              _buildLevelStrip(),
              Expanded(
                child: BrandedRefreshIndicator(
                  color: AppColors.primaryBlue,
                  onRefresh: _loadJobs,
                  // Entrance now happens per-card (StaggeredReveal below).
                  child: _buildList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero() {
    return const ScreenHero(
      title: 'Opportunities for the community',
      tagline: 'Jobs',
      fallbackRoute: 'home',
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _loadJobs(),
        style: AppTextStyles.bodyLarge,
        decoration: InputDecoration(
          hintText: 'Search jobs',
          prefixIcon: const Icon(Icons.search, color: AppColors.primaryBlue),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close, color: AppColors.textMuted),
                  onPressed: () {
                    _searchController.clear();
                    _loadJobs();
                  },
                ),
          filled: true,
          fillColor: context.palette.inputFill,
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
        ),
      ),
    );
  }

  Widget _buildCategoryStrip() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: JobCategory.all.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final cat = JobCategory.all[i];
          final selected = _selectedCategory == cat.id;
          return _CategoryChip(
            label: cat.label,
            selected: selected,
            onTap: () => _selectCategory(cat.id),
          );
        },
      ),
    );
  }

  /// Tier filter strip — entry / mid / senior, with "All levels" as
  /// the opt-out. Sits under the category row so the two filter
  /// dimensions stack cleanly. patch_039.
  Widget _buildLevelStrip() {
    const items = <(String, String)>[
      ('all', 'All levels'),
      ('entry', 'Entry'),
      ('mid', 'Mid'),
      ('senior', 'Senior'),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (id, label) = items[i];
          final selected = _selectedLevel == id;
          return _CategoryChip(
            label: label,
            selected: selected,
            onTap: () => _selectLevel(id),
          );
        },
      ),
    );
  }

  Widget _buildList() {
    return ContentReveal(
      loading: _loading && _jobs.isEmpty,
      skeleton: ShimmerLoaders.cardList(count: 6),
      child: _buildJobsListContent(),
    );
  }

  Widget _buildJobsListContent() {
    if (_error != null && _jobs.isEmpty) {
      final isOffline = !ConnectivityService.isOnline;
      if (isOffline) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            OfflineInlineNotice(onRetry: _loadJobs),
            const SizedBox(height: 60),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'No jobs cached yet.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ),
          ],
        );
      }
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 100),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  Icon(
                    Icons.cloud_off_outlined,
                    size: 56,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    if (_jobs.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.work_outline,
                      color: AppColors.primaryBlue,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'No jobs posted yet',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.headlineMedium.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Be the first to post an opportunity for the community.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textMuted,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    final cachedAt = CacheService.cachedAt(_cacheKey);
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: _jobs.length + (cachedAt != null ? 1 : 0),
      separatorBuilder: (_, i) {
        if (cachedAt != null && i == 0) return const SizedBox(height: 6);
        return const SizedBox(height: 12);
      },
      itemBuilder: (context, rawIndex) {
        if (cachedAt != null && rawIndex == 0) {
          return LastUpdatedStrip(
            timestamp: cachedAt,
            isOnline: ConnectivityService.isOnline,
            onRefresh: _loadJobs,
          );
        }
        final i = cachedAt != null ? rawIndex - 1 : rawIndex;
        final j = _jobs[i];
        final card = JobCard(
          job: j,
          onTap: () => context.pushNamed(
            'job_details',
            pathParameters: {'id': j.id},
            extra: j,
          ),
        );
        if (i >= 8) return card;
        return StaggeredReveal(index: i, rise: 18, child: card);
      },
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

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressEffect(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: selected ? AppColors.primaryGradient : null,
              color: selected ? null : context.palette.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? AppColors.primaryBlue : AppColors.divider,
              ),
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
            child: Text(
              label,
              style: AppTextStyles.labelMedium.copyWith(
                color: selected ? AppColors.white : AppColors.text,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
