import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/job_model.dart';
import '../../services/job_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/job_card.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/screen_shell.dart';
import '../../widgets/shimmer_loaders.dart';

/// The poster's own listings with their real moderation status (brief
/// §15, employer tools). Nothing here is estimated: the status is the
/// row's, and views/applicants aren't shown because jobs don't record them.
class MyJobsScreen extends StatefulWidget {
  const MyJobsScreen({super.key});

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

class _MyJobsScreenState extends State<MyJobsScreen> {
  List<Job>? _jobs;
  String? _error;
  JobPostState? _filter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final jobs = await JobService.fetchMyJobs();
      if (mounted) setState(() => _jobs = jobs);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't load your job posts.");
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

  @override
  Widget build(BuildContext context) {
    final jobs = _jobs;
    final counts = <JobPostState, int>{};
    for (final j in jobs ?? const <Job>[]) {
      counts.update(jobPostState(j), (n) => n + 1, ifAbsent: () => 1);
    }
    final shown = jobs == null
        ? const <Job>[]
        : _filter == null
        ? jobs
        : jobs.where((j) => jobPostState(j) == _filter).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: BrandedRefreshIndicator(
          color: AppColors.primaryBlue,
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: ScreenHero(
                  title: 'My job posts',
                  tagline: 'JOBS',
                  subtitle: 'Every listing you posted, and where it stands',
                  fallbackRoute: 'jobs',
                  trailing: HeaderIconButton(
                    icon: Icons.add_rounded,
                    tooltip: 'Post a job',
                    onTap: _post,
                  ),
                ),
              ),
              if (jobs != null && jobs.isNotEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        _StateChip(
                          label: 'All · ${jobs.length}',
                          selected: _filter == null,
                          onTap: () => setState(() => _filter = null),
                        ),
                        for (final s in JobPostState.values)
                          if ((counts[s] ?? 0) > 0)
                            _StateChip(
                              label: '${s.label} · ${counts[s]}',
                              selected: _filter == s,
                              onTap: () => setState(() => _filter = s),
                            ),
                      ],
                    ),
                  ),
                ),
              if (jobs == null && _error == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  // cardList is a ListView; a sliver gives it no height.
                  child: SizedBox(
                    height: 560,
                    child: ShimmerLoaders.cardList(count: 4),
                  ),
                )
              else if (_error != null && jobs == null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: EmptyStateCard(
                      icon: Icons.cloud_off_outlined,
                      title: _error!,
                      message: 'Pull down to try again.',
                    ),
                  ),
                )
              else if (jobs!.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: EmptyStateCard(
                      icon: Icons.work_outline,
                      title: 'No job posts yet',
                      message:
                          'Post a vacancy, or tell employers you are looking '
                          'for work. Listings are reviewed before they go live.',
                      action: FilledButton(
                        onPressed: _post,
                        child: const Text('Post a job'),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  sliver: SliverList.separated(
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (context, i) {
                      final j = shown[i];
                      final s = jobPostState(j);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 6),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: s.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  s.label,
                                  style: AppTextStyles.labelMedium.copyWith(
                                    color: s.color,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          JobCard(job: j, onTap: () => _open(j)),
                        ],
                      );
                    },
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
