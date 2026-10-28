import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/countries.dart';
import '../../models/job_model.dart';
import '../../services/auth_service.dart';
import '../../services/cache_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/job_application_service.dart';
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

/// Jobs (redesign v2, 28 Oct 2026 — owner: "it should accommodate
/// everyone… garden boys, house girls… medical… professional").
///
/// Two modes, because there are two people here:
///   * **Find work** — vacancies. Three kinds of work up top (Everyday,
///     Skilled & medical, Professional) narrow to fields; quick chips for
///     what people actually choose by (start now, day work, Sabbath,
///     Adventist employers, no experience); a "Start now" rail; Saved;
///     the latest jobs; job alerts for the field you're looking at.
///   * **Hire someone** — members available for work, plus one-tap
///     templates to post a vacancy (Housekeeper, Gardener, Nurse…).
///
/// Nothing is invented: counts are the jobs actually loaded, "Start now"
/// is the poster's own flag, and there's no "Recommended" or "Featured".
class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key});

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> with NavVisibilityMixin {
  final _searchController = TextEditingController();
  Timer? _debounce;

  /// false = Find work (vacancies), true = Hire someone (people available).
  bool _hire = false;
  JobKind? _kind;
  String? _category;
  JobFilters _filters = JobFilters.none;

  List<Job> _jobs = [];
  List<Job> _saved = const [];
  Map<JobKind, int> _kindCounts = const {};

  /// Jobs are scoped to the member's own country unless they ask for
  /// worldwide: almost every posting is a local role with a phone number.
  bool _worldwide = false;
  final String _country = AuthService.currentCountry();
  bool _loading = true;
  String? _error;
  bool _redesign = JobService.redesignAvailable;

  static const _cacheKey = 'jobs_list';

  bool get _browsing =>
      _searchController.text.trim().isEmpty &&
      _kind == null &&
      _category == null &&
      _filters.isEmpty;

  bool get _signedIn => AuthService.currentUser != null;

  @override
  void initState() {
    super.initState();
    _hydrateFromCache();
    _loadJobs();
    JobService.savedIds.addListener(_loadSavedJobs);
    JobService.loadSaved();
    JobApplicationService.loadApplied();
    JobAlertService.load();
    JobService.probeRedesign().then((ok) {
      if (mounted && ok != _redesign) setState(() => _redesign = ok);
    });
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
        _kindCounts = _countKinds(list);
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

  static Map<JobKind, int> _countKinds(List<Job> jobs) {
    final out = <JobKind, int>{};
    for (final j in jobs) {
      final k = JobCategory.byId(j.category)?.kind;
      if (k != null) out.update(k, (n) => n + 1, ifAbsent: () => 1);
    }
    return out;
  }

  Future<void> _loadJobs() async {
    setState(() {
      if (_jobs.isEmpty) _loading = true;
      _error = null;
    });
    final hire = _hire;
    try {
      final list = await JobService.fetchJobs(
        search: _searchController.text,
        category: _category,
        categories: _category == null && _kind != null
            ? [for (final c in JobCategory.ofKind(_kind!)) c.id]
            : null,
        filters: _filters.copyWith(postType: hire ? 'seeking' : 'hiring'),
        country: _worldwide ? null : _country,
      );
      if (!mounted || hire != _hire) return;
      setState(() {
        _jobs = list;
        _loading = false;
        if (_browsing) _kindCounts = _countKinds(list);
      });
      // Only the default view is cached — a filtered or worldwide list
      // would greet the member with the wrong jobs on the next cold start.
      if (_browsing && !_worldwide && !hire) unawaited(_writeCache(list));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load jobs. Pull to retry.';
        _loading = false;
      });
    }
  }

  void _reload(VoidCallback change) {
    setState(change);
    _loadJobs();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _loadJobs);
    setState(() {});
  }

  void _setMode(bool hire) {
    if (hire == _hire) return;
    _reload(() {
      _hire = hire;
      _jobs = [];
      _filters = JobFilters.none;
      _loading = true;
    });
  }

  Future<void> _openFilters() async {
    final picked = await showJobFilterSheet(
      context,
      current: _filters,
      hire: _hire,
    );
    if (picked == null || !mounted) return;
    _reload(() => _filters = picked);
  }

  Future<void> _toggleSaved(Job job) async {
    final saved = JobService.savedIds.value.contains(job.id);
    try {
      await JobService.setSaved(job.id, !saved);
    } catch (_) {
      if (!mounted) return;
      _snack(
        !JobService.savedAvailable
            ? 'Saving jobs needs a database update (patch_278).'
            : 'Sign in to save jobs.',
      );
    }
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  void _open(Job j) =>
      context.pushNamed('job_details', pathParameters: {'id': j.id}, extra: j);

  Future<void> _post({
    bool seeking = false,
    String? category,
    String? role,
  }) async {
    final made = await context.pushNamed<bool>(
      'post_job',
      queryParameters: {
        if (seeking) 'type': 'seeking',
        'category': ?category,
        'role': ?role,
      },
    );
    if (made == true && mounted) _loadJobs();
  }

  // Alerts ---------------------------------------------------------------------

  JobAlert? _matchingAlert(List<JobAlert> alerts) {
    final country = _worldwide ? null : _country;
    for (final a in alerts) {
      if (a.matches(category: _category, jobType: null, country: country)) {
        return a;
      }
    }
    return null;
  }

  Future<void> _toggleAlert(JobAlert? existing) async {
    try {
      if (existing != null) {
        await JobAlertService.delete(existing.id);
        _snack('Alert turned off.');
      } else {
        await JobAlertService.create(
          category: _category,
          country: _worldwide ? null : _country,
        );
        _snack("Alert on — we'll notify you when a matching job is posted.");
      }
    } catch (e) {
      if (!mounted) return;
      final s = e.toString();
      _snack(
        !JobAlertService.available || s.contains('PGRST205')
            ? 'Job alerts need a database update (patch_278).'
            : s.contains('10 job alerts')
            ? 'You can have up to 10 job alerts. Remove one in My jobs.'
            : "Couldn't change the alert. Try again.",
      );
    }
  }

  // Build ----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      bottomNavigationBar: const SafeArea(top: false, child: AdBanner()),
      // The empty states carry their own post buttons; a FAB on top of
      // them would cover one.
      floatingActionButton: !_loading && _jobs.isEmpty
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
            await Future.wait([
              _loadJobs(),
              JobService.loadSaved(),
              JobApplicationService.loadApplied(),
            ]);
          },
          child: AnimatedBuilder(
            animation: Listenable.merge([
              JobService.savedIds,
              JobApplicationService.appliedJobIds,
              JobAlertService.alerts,
            ]),
            builder: (context, _) => CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: ScreenHero(
                    title: 'Jobs',
                    tagline: 'MARKETPLACE',
                    subtitle: _hire
                        ? 'Find people ready to work'
                        : 'Work for every skill, in the community',
                    fallbackRoute: 'marketplace',
                    trailing: !_signedIn
                        ? null
                        : HeaderIconButton(
                            icon: Icons.work_history_outlined,
                            tooltip: 'My jobs',
                            onTap: () async {
                              await context.pushNamed('my_jobs');
                              if (mounted) _loadJobs();
                            },
                          ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: _ShopJobsSegment(active: _Section.jobs),
                ),
                SliverToBoxAdapter(
                  child: _ModeSwitch(hire: _hire, onChanged: _setMode),
                ),
                SliverToBoxAdapter(child: _buildSearchRow()),
                SliverToBoxAdapter(child: _buildScope()),
                SliverToBoxAdapter(child: _buildKinds()),
                if (_kind != null)
                  SliverToBoxAdapter(child: _buildFieldChips()),
                SliverToBoxAdapter(child: _buildQuickChips()),
                if (_hire && _browsing)
                  SliverToBoxAdapter(child: _buildHireCard()),
                if (!_hire && _signedIn && (_category != null || _kind != null))
                  SliverToBoxAdapter(child: _buildAlertCard()),
                if (!_hire && _browsing) ..._buildRails(),
                SliverToBoxAdapter(child: _buildListHeader()),
                ..._buildListSlivers(),
                if (!_hire && _jobs.isNotEmpty)
                  SliverToBoxAdapter(child: _buildSeekerCta()),
                const SliverToBoxAdapter(child: SizedBox(height: 96)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchRow() {
    final palette = context.palette;
    final n = _filters.activeCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              style: AppTextStyles.bodyMedium.copyWith(color: palette.text),
              decoration: InputDecoration(
                hintText: _hire
                    ? 'Skill or trade, e.g. electrician'
                    : 'Job, employer, skill or town',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => _reload(_searchController.clear),
                      ),
                filled: true,
                fillColor: palette.card,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: palette.divider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: palette.divider),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: 'Filters',
            child: Pressable(
              onTap: _openFilters,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: n > 0 ? AppColors.primaryBlue : palette.card,
                  borderRadius: BorderRadius.circular(16),
                  border: n > 0 ? null : Border.all(color: palette.divider),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      color: n > 0 ? AppColors.white : palette.text,
                    ),
                    if (n > 0)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 16,
                          height: 16,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: AppColors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$n',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                            ),
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

  Widget _buildScope() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: CountryScopeToggle(
          countryCode: _country,
          worldwide: _worldwide,
          onChanged: (v) => _reload(() => _worldwide = v),
        ),
      ),
    );
  }

  Widget _buildKinds() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          for (final k in JobKind.values) ...[
            if (k != JobKind.everyday) const SizedBox(width: 10),
            Expanded(
              child: _KindTile(
                kind: k,
                count: _hire ? null : _kindCounts[k],
                selected: _kind == k,
                onTap: () => _reload(() {
                  _kind = _kind == k ? null : k;
                  _category = null;
                }),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFieldChips() {
    final fields = [
      for (final c in JobCategory.ofKind(_kind!))
        if (_redesign || !c.needsPatch) c,
    ];
    return SizedBox(
      height: 54,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        children: [
          _Chip(
            label: 'All ${_kind!.label.toLowerCase()}',
            selected: _category == null,
            onTap: () => _reload(() => _category = null),
          ),
          for (final c in fields)
            _Chip(
              label: c.label,
              icon: c.icon,
              selected: _category == c.id,
              onTap: () =>
                  _reload(() => _category = _category == c.id ? null : c.id),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickChips() {
    final f = _filters;
    final chips = <_Chip>[
      if (_redesign)
        _Chip(
          label: _hire ? 'Available now' : 'Start now',
          icon: Icons.bolt_rounded,
          selected: f.urgent,
          onTap: () => _reload(() => _filters = f.copyWith(urgent: !f.urgent)),
        ),
      if (_redesign)
        _Chip(
          label: 'Day & casual work',
          selected: f.jobType == 'casual',
          onTap: () => _reload(
            () => _filters = f.copyWith(
              jobType: f.jobType == 'casual' ? null : 'casual',
            ),
          ),
        ),
      if (!_hire)
        _Chip(
          label: 'Part-time',
          selected: f.jobType == 'part_time',
          onTap: () => _reload(
            () => _filters = f.copyWith(
              jobType: f.jobType == 'part_time' ? null : 'part_time',
            ),
          ),
        ),
      _Chip(
        label: _hire ? 'Keeps Sabbath' : 'Sabbath-friendly',
        icon: Icons.brightness_2_outlined,
        selected: f.sabbathFriendly,
        onTap: () => _reload(
          () => _filters = f.copyWith(sabbathFriendly: !f.sabbathFriendly),
        ),
      ),
      if (!_hire)
        _Chip(
          label: 'Adventist employers',
          icon: Icons.church_outlined,
          selected: f.sdaInstitution,
          onTap: () => _reload(
            () => _filters = f.copyWith(sdaInstitution: !f.sdaInstitution),
          ),
        ),
      _Chip(
        label: _hire ? 'Experienced' : 'No experience needed',
        selected: f.level == (_hire ? 'senior' : 'entry'),
        onTap: () {
          final want = _hire ? 'senior' : 'entry';
          _reload(
            () => _filters = f.copyWith(level: f.level == want ? null : want),
          );
        },
      ),
      if (!_hire && _redesign)
        _Chip(
          label: 'Remote',
          selected: f.workArrangement == 'remote',
          onTap: () => _reload(
            () => _filters = f.copyWith(
              workArrangement: f.workArrangement == 'remote' ? null : 'remote',
            ),
          ),
        ),
    ];
    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        children: chips,
      ),
    );
  }

  Widget _sectionTitle(String title, {String? trailing}) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: AppTextStyles.titleLarge.copyWith(
              color: context.palette.text,
              fontWeight: FontWeight.w700,
              fontSize: 19,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing,
            style: AppTextStyles.bodySmall.copyWith(
              color: context.palette.textMuted,
            ),
          ),
      ],
    ),
  );

  List<Widget> _buildRails() {
    final urgent = [
      for (final j in _jobs)
        if (j.isUrgent) j,
    ];
    final applied = JobApplicationService.appliedJobIds.value;
    Widget rail(List<Job> jobs) => SizedBox(
      height: 156,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        itemCount: jobs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final j = jobs[i];
          return SizedBox(
            width: 292,
            child: JobCard(
              job: j,
              compact: true,
              onTap: () => _open(j),
              applied: applied.contains(j.id),
              saved: _signedIn
                  ? JobService.savedIds.value.contains(j.id)
                  : null,
              onToggleSave: () => _toggleSaved(j),
            ),
          );
        },
      ),
    );
    return [
      if (urgent.isNotEmpty) ...[
        SliverToBoxAdapter(child: _sectionTitle('Start now')),
        SliverToBoxAdapter(child: rail(urgent)),
      ],
      if (_saved.isNotEmpty) ...[
        SliverToBoxAdapter(child: _sectionTitle('Saved')),
        SliverToBoxAdapter(child: rail(_saved)),
      ],
    ];
  }

  Widget _buildListHeader() {
    final title = _hire
        ? 'Available for work'
        : _browsing
        ? 'Latest jobs'
        : _category != null
        ? JobCategory.labelFor(_category)
        : _kind?.label ?? 'Results';
    final n = _jobs.length;
    return _sectionTitle(
      title,
      trailing: _loading || n == 0
          ? null
          : _hire
          ? '$n ${n == 1 ? 'person' : 'people'}'
          : '$n ${n == 1 ? 'job' : 'jobs'}',
    );
  }

  List<Widget> _buildListSlivers() {
    if (_loading && _jobs.isEmpty) {
      return [
        SliverToBoxAdapter(
          // cardList is a ListView; a sliver gives it no height.
          child: SizedBox(
            height: 560,
            child: ShimmerLoaders.cardList(count: 4),
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
    final saved = JobService.savedIds.value;
    final applied = JobApplicationService.appliedJobIds.value;
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.separated(
          itemCount: _jobs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final j = _jobs[i];
            final Widget card = j.isSeeking
                ? SeekerCard(
                    job: j,
                    onTap: () => _open(j),
                    saved: _signedIn ? saved.contains(j.id) : null,
                    onToggleSave: () => _toggleSaved(j),
                  )
                : JobCard(
                    job: j,
                    onTap: () => _open(j),
                    applied: applied.contains(j.id),
                    saved: _signedIn ? saved.contains(j.id) : null,
                    onToggleSave: () => _toggleSaved(j),
                  );
            if (i >= 8) return card;
            return StaggeredReveal(index: i, rise: 18, child: card);
          },
        ),
      ),
    ];
  }

  /// Hire mode's first card: post a vacancy from a common role in one tap.
  Widget _buildHireCard() {
    final palette = context.palette;
    const picks = [
      ('domestic_caregiving', 'Housekeeper'),
      ('domestic_caregiving', 'Gardener'),
      ('domestic_caregiving', 'Nanny'),
      ('construction_trades', 'Builder'),
      ('driving_transport', 'Driver'),
      ('healthcare', 'Registered nurse'),
      ('teaching_education', 'Tutor'),
      ('business_admin', 'Accountant'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: jobCardDecoration(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.campaign_outlined,
                    color: AppColors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hiring? Post in two minutes',
                        style: AppTextStyles.titleMedium.copyWith(
                          color: palette.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Pick a role to start — we fill in the rest.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (cat, role) in picks)
                  ActionChip(
                    avatar: Icon(
                      JobCategory.byId(cat)?.icon,
                      size: 16,
                      color: AppColors.primaryBlue,
                    ),
                    label: Text(role),
                    onPressed: () => _post(category: cat, role: role),
                    labelStyle: AppTextStyles.labelMedium.copyWith(
                      color: palette.text,
                      fontWeight: FontWeight.w600,
                    ),
                    backgroundColor: palette.cardMuted,
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ActionChip(
                  label: const Text('Something else'),
                  onPressed: () => _post(),
                  labelStyle: AppTextStyles.labelMedium.copyWith(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w700,
                  ),
                  backgroundColor: AppColors.primaryBlue.withValues(
                    alpha: 0.08,
                  ),
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertCard() {
    final palette = context.palette;
    final alert = _matchingAlert(JobAlertService.alerts.value);
    final what = _category != null
        ? JobCategory.labelFor(_category).toLowerCase()
        : 'new';
    final where = _worldwide ? '' : ' in ${Countries.nameOf(_country)}';
    // Alerts are per field, so a whole kind asks to pick one first.
    final canSet = _category != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: AppColors.primaryBlue.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              alert != null
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              color: AppColors.primaryBlue,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                !canSet
                    ? 'Pick a field to get alerts when new jobs are posted.'
                    : alert != null
                    ? "You'll be notified about new $what jobs$where."
                    : 'Get notified about new $what jobs$where.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: palette.text,
                  height: 1.35,
                ),
              ),
            ),
            if (canSet)
              TextButton(
                onPressed: () => _toggleAlert(alert),
                child: Text(alert != null ? 'Turn off' : 'Turn on'),
              ),
          ],
        ),
      ),
    );
  }

  /// Under the vacancies: the other side of the market.
  Widget _buildSeekerCta() {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Pressable(
        onTap: () => _post(seeking: true),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: jobCardDecoration(context),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.person_search_outlined,
                  color: AppColors.primaryBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Can't find the right job?",
                      style: AppTextStyles.titleMedium.copyWith(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Tell employers what you do and let them find you.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  /// Nothing posted yet is the real state today — say so warmly, and give
  /// both sides of the market a first step.
  Widget _buildEmpty() {
    final palette = context.palette;
    final filtered = !_browsing;
    final place = _worldwide ? '' : ' in ${Countries.nameOf(_country)}';
    final title = _hire
        ? (filtered ? 'No one matches yet' : 'No one listed$place yet')
        : (filtered ? 'No jobs match' : 'No jobs posted$place yet');
    final body = _hire
        ? 'Post your vacancy — people looking for work will see it and '
              'can apply in the app.'
        : filtered
        ? 'Try fewer filters, or turn on an alert and we will tell you when '
              'one is posted.'
        : 'Be the first: post a vacancy, or tell employers what you do.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
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
              _hire
                  ? Icons.person_search_outlined
                  : filtered
                  ? Icons.search_off_rounded
                  : Icons.work_outline,
              color: AppColors.primaryBlue,
              size: 40,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyles.headlineSmall.copyWith(
              color: palette.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: palette.textMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: () => _post(),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('Post a vacancy'),
            ),
          ),
          if (!_hire) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () => _post(seeking: true),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.person_search_outlined),
                label: const Text("I'm looking for work"),
              ),
            ),
          ],
          if (!_worldwide)
            TextButton.icon(
              onPressed: () => _reload(() => _worldwide = true),
              icon: const Icon(Icons.public, size: 18),
              label: const Text('Browse worldwide'),
            ),
        ],
      ),
    );
  }
}

/// Find work | Hire someone.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.hire, required this.onChanged});
  final bool hire;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget side(String label, IconData icon, bool active, bool value) =>
        Expanded(
          child: Semantics(
            button: true,
            selected: active,
            child: GestureDetector(
              onTap: () => onChanged(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                height: 44,
                decoration: BoxDecoration(
                  color: active ? palette.card : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 18,
                      color: active ? AppColors.primaryBlue : palette.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: AppTextStyles.labelLarge.copyWith(
                        color: active ? palette.text : palette.textMuted,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: palette.cardMuted,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            side('Find work', Icons.search_rounded, !hire, false),
            side('Hire someone', Icons.person_add_alt_rounded, hire, true),
          ],
        ),
      ),
    );
  }
}

/// One of the three kinds of work, with the fields' icons and the real
/// number of open jobs loaded for it.
class _KindTile extends StatelessWidget {
  const _KindTile({
    required this.kind,
    required this.selected,
    required this.onTap,
    this.count,
  });
  final JobKind kind;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final icons = [for (final c in JobCategory.ofKind(kind).take(3)) c.icon];
    return Semantics(
      button: true,
      selected: selected,
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 124,
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryBlue : palette.card,
            borderRadius: BorderRadius.circular(18),
            border: selected ? null : Border.all(color: palette.divider),
            boxShadow: [
              BoxShadow(
                color: (selected ? AppColors.primaryBlue : Colors.black)
                    .withValues(alpha: selected ? 0.25 : 0.04),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (final i in icons)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        i,
                        size: 17,
                        color: selected
                            ? AppColors.white
                            : AppColors.primaryBlue,
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                kind.label,
                maxLines: 2,
                style: AppTextStyles.labelLarge.copyWith(
                  color: selected ? AppColors.white : palette.text,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                (count ?? 0) > 0 ? '$count open' : kind.blurb,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall.copyWith(
                  color: selected
                      ? AppColors.white.withValues(alpha: 0.85)
                      : (count ?? 0) > 0
                      ? AppColors.primaryBlue
                      : palette.textMuted,
                  fontSize: 11,
                  fontWeight: (count ?? 0) > 0
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
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
    final fg = selected ? AppColors.primaryBlue : palette.text;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected
            ? AppColors.primaryBlue.withValues(alpha: 0.12)
            : palette.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppColors.primaryBlue : palette.divider,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: fg),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: fg,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
