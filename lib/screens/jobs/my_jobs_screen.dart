import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/countries.dart';
import '../../models/job_application_model.dart';
import '../../models/job_model.dart';
import '../../services/auth_service.dart';
import '../../services/job_application_service.dart';
import '../../services/job_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/job_card.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/screen_shell.dart';
import '../../widgets/shimmer_loaders.dart';

/// My jobs — one place for both sides (jobs redesign v2):
///   * Applied — every Quick application and where it stands (Sent, Seen
///     by employer, Shortlisted, Not selected); withdraw.
///   * Saved — bookmarked jobs.
///   * My posts — each listing with its real moderation status and its
///     Applicants.
///   * Alerts — "tell me when…" subscriptions.
/// Nothing is estimated: every status is the row's own.
class MyJobsScreen extends StatefulWidget {
  const MyJobsScreen({super.key, this.initialTab});

  /// 'applied' | 'saved' | 'posts' | 'alerts'.
  final String? initialTab;

  @override
  State<MyJobsScreen> createState() => _MyJobsScreenState();
}

/// What a listing's status means to its owner.
enum JobPostState { live, review, filled, ended, rejected }

JobPostState jobPostState(Job j) {
  if (j.status == 'pending') return JobPostState.review;
  if (j.status == 'rejected') return JobPostState.rejected;
  if (j.status == 'filled') return JobPostState.filled;
  if (j.status == 'open' && !j.isExpired) return JobPostState.live;
  return JobPostState.ended;
}

extension JobPostStateX on JobPostState {
  String get label => switch (this) {
    JobPostState.live => 'Live',
    JobPostState.review => 'Waiting for review',
    JobPostState.filled => 'Filled',
    JobPostState.ended => 'Ended',
    JobPostState.rejected => 'Not approved',
  };

  Color get color => switch (this) {
    JobPostState.live => AppColors.successGreen,
    JobPostState.review => AppColors.primaryBlue,
    JobPostState.rejected => AppColors.red,
    _ => AppColors.textMuted,
  };
}

const _tabs = ['applied', 'saved', 'posts', 'alerts'];

class _MyJobsScreenState extends State<MyJobsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(
    length: _tabs.length,
    vsync: this,
    initialIndex: _tabs.contains(widget.initialTab)
        ? _tabs.indexOf(widget.initialTab!)
        : 0,
  );

  List<JobApplication>? _applied;
  List<Job>? _saved;
  List<Job>? _posts;
  final Map<String, int?> _counts = {};
  String? _error;
  JobPostState? _postFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    await Future.wait([
      JobApplicationService.mine()
          .then((v) => _applied = v)
          .catchError((_) => _applied = const <JobApplication>[]),
      JobService.loadSaved()
          .then((_) => JobService.fetchSavedJobs())
          .then((v) => _saved = v)
          .catchError((_) => _saved = const <Job>[]),
      JobService.fetchMyJobs().then((v) => _posts = v).catchError((_) {
        _error = "Couldn't load your job posts.";
        return _posts = const <Job>[];
      }),
      JobAlertService.load(),
    ]);
    if (!mounted) return;
    setState(() {});
    for (final j in _posts ?? const <Job>[]) {
      if (!j.isHiring) continue;
      JobApplicationService.count(j.id).then((n) {
        if (mounted) setState(() => _counts[j.id] = n);
      });
    }
  }

  Future<void> _open(Job j) async {
    await context.pushNamed(
      'job_details',
      pathParameters: {'id': j.id},
      extra: j,
    );
    if (mounted) _load();
  }

  Future<void> _post() async {
    final made = await context.pushNamed<bool>('post_job');
    if (made == true && mounted) _load();
  }

  Future<void> _withdraw(JobApplication a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Withdraw application?'),
        content: const Text(
          'The employer will no longer see it. You can apply again while '
          'the job is open.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await JobApplicationService.withdraw(a.id, a.jobId);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't withdraw. Try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(
              child: ScreenHero(
                title: 'My jobs',
                tagline: 'JOBS',
                subtitle: 'Applications, saved jobs, your posts and alerts',
                fallbackRoute: 'jobs',
                trailing: HeaderIconButton(
                  icon: Icons.add_rounded,
                  tooltip: 'Post a job',
                  onTap: _post,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: palette.cardMuted,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TabBar(
                    controller: _tab,
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      color: palette.card,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    labelColor: palette.text,
                    unselectedLabelColor: palette.textMuted,
                    labelStyle: AppTextStyles.labelMedium.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    unselectedLabelStyle: AppTextStyles.labelMedium,
                    labelPadding: EdgeInsets.zero,
                    tabs: const [
                      Tab(text: 'Applied'),
                      Tab(text: 'Saved'),
                      Tab(text: 'My posts'),
                      Tab(text: 'Alerts'),
                    ],
                  ),
                ),
              ),
            ),
          ],
          body: TabBarView(
            controller: _tab,
            children: [
              _refreshable(_buildApplied()),
              _refreshable(_buildSaved()),
              _refreshable(_buildPosts()),
              _refreshable(_buildAlerts()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _refreshable(List<Widget> children) => BrandedRefreshIndicator(
    color: AppColors.primaryBlue,
    onRefresh: _load,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: children,
    ),
  );

  Widget _loader() =>
      SizedBox(height: 480, child: ShimmerLoaders.cardList(count: 3));

  Widget _empty(
    IconData icon,
    String title,
    String message, {
    String? action,
    VoidCallback? onAction,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: EmptyStateCard(
      icon: icon,
      title: title,
      message: message,
      action: action == null
          ? null
          : FilledButton(onPressed: onAction, child: Text(action)),
    ),
  );

  Widget _statusLine(String label, Color color) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 6),
    child: Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.labelMedium.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  List<Widget> _buildApplied() {
    final apps = _applied;
    if (apps == null) return [_loader()];
    if (!JobApplicationService.available) {
      return [
        _empty(
          Icons.send_outlined,
          'Quick apply is coming',
          'Applying inside the app needs a database update (patch_278). '
              'Until then, apply with the contact details on each job.',
        ),
      ];
    }
    if (apps.isEmpty) {
      return [
        _empty(
          Icons.send_outlined,
          'No applications yet',
          'Use Quick apply on a job and you can follow it here — seen, '
              'shortlisted or not selected.',
          action: 'Browse jobs',
          onAction: () =>
              context.canPop() ? context.pop() : context.goNamed('jobs'),
        ),
      ];
    }
    final palette = context.palette;
    return [
      for (final a in apps) ...[
        _statusLine(a.applicantStatusLabel, switch (a.status) {
          'shortlisted' => AppColors.successGreen,
          'declined' => palette.textMuted,
          _ => AppColors.primaryBlue,
        }),
        if (a.job != null)
          JobCard(job: a.job!, onTap: () => _open(a.job!))
        else
          Text(
            'This job was removed.',
            style: AppTextStyles.bodyMedium.copyWith(color: palette.textMuted),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => _withdraw(a),
            child: Text('Withdraw', style: TextStyle(color: palette.textMuted)),
          ),
        ),
        const SizedBox(height: 4),
      ],
    ];
  }

  List<Widget> _buildSaved() {
    final saved = _saved;
    if (saved == null) return [_loader()];
    if (saved.isEmpty) {
      return [
        _empty(
          Icons.bookmark_border_rounded,
          'Nothing saved',
          'Tap the bookmark on any job to keep it here for later.',
        ),
      ];
    }
    return [
      for (final j in saved) ...[
        if (!j.isOpen || j.isExpired)
          _statusLine('No longer open', context.palette.textMuted),
        j.isSeeking
            ? SeekerCard(job: j, onTap: () => _open(j))
            : JobCard(job: j, onTap: () => _open(j)),
        const SizedBox(height: 12),
      ],
    ];
  }

  List<Widget> _buildPosts() {
    final jobs = _posts;
    if (jobs == null) return [_loader()];
    if (_error != null && jobs.isEmpty) {
      return [_empty(Icons.cloud_off_outlined, _error!, 'Pull down to retry.')];
    }
    if (jobs.isEmpty) {
      return [
        _empty(
          Icons.work_outline,
          'No job posts yet',
          'Post a vacancy, or tell employers you are looking for work. '
              'Listings are reviewed before they go live.',
          action: 'Post a job',
          onAction: _post,
        ),
      ];
    }
    final counts = <JobPostState, int>{};
    for (final j in jobs) {
      counts.update(jobPostState(j), (n) => n + 1, ifAbsent: () => 1);
    }
    final shown = _postFilter == null
        ? jobs
        : jobs.where((j) => jobPostState(j) == _postFilter).toList();
    return [
      SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _StateChip(
              label: 'All · ${jobs.length}',
              selected: _postFilter == null,
              onTap: () => setState(() => _postFilter = null),
            ),
            for (final st in JobPostState.values)
              if ((counts[st] ?? 0) > 0)
                _StateChip(
                  label: '${st.label} · ${counts[st]}',
                  selected: _postFilter == st,
                  onTap: () => setState(() => _postFilter = st),
                ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      for (final j in shown) ...[
        _statusLine(jobPostState(j).label, jobPostState(j).color),
        j.isSeeking
            ? SeekerCard(job: j, onTap: () => _open(j))
            : JobCard(job: j, onTap: () => _open(j)),
        if (j.isHiring && JobApplicationService.available)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                await context.pushNamed(
                  'job_applicants',
                  pathParameters: {'id': j.id},
                  extra: j,
                );
                if (mounted) _load();
              },
              icon: const Icon(Icons.people_alt_outlined, size: 18),
              label: Text(
                (_counts[j.id] ?? 0) == 0
                    ? 'Applicants'
                    : 'Applicants · ${_counts[j.id]}',
              ),
            ),
          ),
        const SizedBox(height: 10),
      ],
    ];
  }

  List<Widget> _buildAlerts() {
    final palette = context.palette;
    final alerts = JobAlertService.alerts.value;
    if (!JobAlertService.available) {
      return [
        _empty(
          Icons.notifications_none_rounded,
          'Job alerts are coming',
          'Alerts need a database update (patch_278).',
        ),
      ];
    }
    return [
      Text(
        "We'll notify you when a matching job is approved. Up to 10 alerts.",
        style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
      ),
      const SizedBox(height: 12),
      for (final a in alerts)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          decoration: jobCardDecoration(context),
          child: Row(
            children: [
              JobMark(category: a.category, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        a.category == null
                            ? 'Any field'
                            : JobCategory.labelFor(a.category),
                        if (a.keyword != null) '"${a.keyword}"',
                      ].join(' · '),
                      style: AppTextStyles.titleSmall.copyWith(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      [
                        a.country == null
                            ? 'Worldwide'
                            : Countries.nameOf(a.country),
                        if (a.jobType != null) jobTypes[a.jobType] ?? '',
                      ].join(' · '),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove alert',
                icon: Icon(Icons.close_rounded, color: palette.textMuted),
                onPressed: () async {
                  try {
                    await JobAlertService.delete(a.id);
                    if (mounted) setState(() {});
                  } catch (_) {}
                },
              ),
            ],
          ),
        ),
      if (alerts.length < 10)
        OutlinedButton.icon(
          onPressed: _addAlert,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(Icons.add_alert_outlined),
          label: const Text('New alert'),
        ),
    ];
  }

  Future<void> _addAlert() async {
    final picked = await showModalBottomSheet<(String?, bool, String)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _NewAlertSheet(),
    );
    if (picked == null || !mounted) return;
    final (category, worldwide, keyword) = picked;
    try {
      await JobAlertService.create(
        category: category,
        country: worldwide ? null : AuthService.currentCountry(),
        keyword: keyword,
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().contains('10 job alerts')
                ? 'You can have up to 10 job alerts.'
                : "Couldn't add the alert. Try again.",
          ),
        ),
      );
    }
  }
}

class _NewAlertSheet extends StatefulWidget {
  const _NewAlertSheet();

  @override
  State<_NewAlertSheet> createState() => _NewAlertSheetState();
}

class _NewAlertSheetState extends State<_NewAlertSheet> {
  String? _category;
  bool _worldwide = false;
  final _keyword = TextEditingController();

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'New job alert',
                style: AppTextStyles.titleLarge.copyWith(
                  color: palette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Field',
                style: AppTextStyles.labelLarge.copyWith(color: palette.text),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Any field'),
                    selected: _category == null,
                    onSelected: (_) => setState(() => _category = null),
                  ),
                  for (final c in JobCategory.all)
                    if (!c.needsPatch || JobService.redesignAvailable)
                      ChoiceChip(
                        avatar: Icon(c.icon, size: 16),
                        label: Text(c.label),
                        selected: _category == c.id,
                        onSelected: (_) => setState(() => _category = c.id),
                      ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _keyword,
                maxLength: 60,
                decoration: const InputDecoration(
                  labelText: 'Keyword (optional)',
                  hintText: 'e.g. nurse, driver, Harare',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _worldwide,
                onChanged: (v) => setState(() => _worldwide = v),
                title: const Text('Worldwide'),
                subtitle: Text(
                  _worldwide
                      ? 'Jobs in any country'
                      : 'Only ${Countries.nameOf(AuthService.currentCountry())}',
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, (
                    _category,
                    _worldwide,
                    _keyword.text.trim(),
                  )),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Create alert'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.primaryBlue,
        labelStyle: AppTextStyles.labelMedium.copyWith(
          color: selected ? AppColors.white : palette.text,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: selected ? AppColors.primaryBlue : palette.divider,
          ),
        ),
      ),
    );
  }
}
