import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/countries.dart';
import '../../models/job_application_model.dart';
import '../../models/job_model.dart';
import '../../services/job_application_service.dart';
import '../../services/messaging_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/job_card.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/screen_shell.dart';
import '../../widgets/shimmer_loaders.dart';

/// The people who Quick-applied to one of the poster's jobs (patch_278).
///
/// Each applicant: who they are (name, photo, town — tap for their
/// profile), their message and number, and one-tap Call / WhatsApp /
/// Message. Shortlist notifies them; Decline doesn't (no push for a "no").
/// Opening the list marks new applications as seen, so applicants can tell
/// their message was read.
class JobApplicantsScreen extends StatefulWidget {
  const JobApplicantsScreen({super.key, required this.jobId, this.job});
  final String jobId;
  final Job? job;

  @override
  State<JobApplicantsScreen> createState() => _JobApplicantsScreenState();
}

class _JobApplicantsScreenState extends State<JobApplicantsScreen> {
  List<JobApplication>? _apps;
  String? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final apps = await JobApplicationService.forJob(widget.jobId);
      if (!mounted) return;
      setState(() => _apps = apps);
      // Seen — quietly, one by one; a failure just leaves it 'sent'.
      for (final a in apps.where((a) => a.isNew)) {
        JobApplicationService.setStatus(a.id, 'viewed').catchError((_) {});
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = !JobApplicationService.available
              ? 'Applications need a database update (patch_278).'
              : "Couldn't load applicants.",
        );
      }
    }
  }

  Future<void> _setStatus(JobApplication a, String status) async {
    try {
      await JobApplicationService.setStatus(a.id, status);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'shortlisted'
                ? '${a.applicantName ?? 'They'} will be told they are shortlisted.'
                : 'Marked as not selected.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't update. Try again.")),
      );
    }
  }

  Future<void> _call(String phone) =>
      launchUrl(Uri(scheme: 'tel', path: phone));

  Future<void> _whatsApp(JobApplication a) async {
    final digits =
        Countries.toWhatsAppDigits(
          a.phone!,
          countryCode: widget.job?.country,
        ) ??
        a.phone!.replaceAll(RegExp(r'\D'), '');
    final text = Uri.encodeComponent(
      'Hello ${a.applicantName ?? ''}, thank you for applying for '
      '"${widget.job?.title ?? 'the job'}".',
    );
    await launchUrl(
      Uri.parse('https://wa.me/$digits?text=$text'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _message(JobApplication a) async {
    try {
      final convo = await MessagingService.createConversation(
        otherUserId: a.applicantId,
        otherUserName: a.applicantName ?? 'Applicant',
        source: 'job',
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      context.pushNamed('chat', pathParameters: {'id': convo.id}, extra: convo);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open chat. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final apps = _apps;
    final shown = apps == null
        ? const <JobApplication>[]
        : switch (_filter) {
            'shortlisted' => apps.where((a) => a.isShortlisted).toList(),
            'new' =>
              apps.where((a) => !a.isShortlisted && !a.isDeclined).toList(),
            _ => apps,
          };
    final shortlisted = apps?.where((a) => a.isShortlisted).length ?? 0;
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
                  title: 'Applicants',
                  tagline: 'JOBS',
                  subtitle: widget.job?.title,
                  fallbackRoute: 'jobs',
                ),
              ),
              if (apps != null && apps.isNotEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        for (final (id, label) in [
                          ('all', 'All · ${apps.length}'),
                          ('new', 'To review'),
                          ('shortlisted', 'Shortlisted · $shortlisted'),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(label),
                              selected: _filter == id,
                              showCheckmark: false,
                              onSelected: (_) => setState(() => _filter = id),
                              selectedColor: AppColors.primaryBlue,
                              backgroundColor: context.palette.card,
                              labelStyle: AppTextStyles.labelMedium.copyWith(
                                color: _filter == id
                                    ? AppColors.white
                                    : context.palette.text,
                                fontWeight: FontWeight.w600,
                              ),
                              side: BorderSide(
                                color: _filter == id
                                    ? AppColors.primaryBlue
                                    : context.palette.divider,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (apps == null && _error == null)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 480,
                    child: ShimmerLoaders.cardList(count: 3),
                  ),
                )
              else if (_error != null)
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
              else if (apps!.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: EmptyStateCard(
                      icon: Icons.people_outline_rounded,
                      title: 'No applicants yet',
                      message:
                          "When someone uses Quick apply you'll get a "
                          'notification and they will appear here.',
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  sliver: SliverList.separated(
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, i) => _ApplicantCard(
                      app: shown[i],
                      onProfile: () => context.pushNamed(
                        'user_profile',
                        pathParameters: {'userId': shown[i].applicantId},
                      ),
                      onCall: shown[i].phone == null || shown[i].phone!.isEmpty
                          ? null
                          : () => _call(shown[i].phone!),
                      onWhatsApp:
                          shown[i].phone == null || shown[i].phone!.isEmpty
                          ? null
                          : () => _whatsApp(shown[i]),
                      onMessage: () => _message(shown[i]),
                      onShortlist: shown[i].isShortlisted
                          ? null
                          : () => _setStatus(shown[i], 'shortlisted'),
                      onDecline: shown[i].isDeclined
                          ? null
                          : () => _setStatus(shown[i], 'declined'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApplicantCard extends StatelessWidget {
  const _ApplicantCard({
    required this.app,
    required this.onProfile,
    required this.onMessage,
    this.onCall,
    this.onWhatsApp,
    this.onShortlist,
    this.onDecline,
  });

  final JobApplication app;
  final VoidCallback onProfile;
  final VoidCallback onMessage;
  final VoidCallback? onCall;
  final VoidCallback? onWhatsApp;
  final VoidCallback? onShortlist;
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final name = (app.applicantName ?? '').trim().isEmpty
        ? 'Member'
        : app.applicantName!.trim();
    final initials = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    Widget contact(IconData icon, String label, VoidCallback? onTap) =>
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 16),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, maxLines: 1),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              foregroundColor: palette.text,
              side: BorderSide(color: palette.divider),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        );
    return Opacity(
      opacity: app.isDeclined ? 0.6 : 1,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: jobCardDecoration(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onProfile,
              borderRadius: BorderRadius.circular(12),
              child: Row(
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: (app.applicantPhotoUrl ?? '').isNotEmpty
                          ? CachedImage(
                              app.applicantPhotoUrl!,
                              fit: BoxFit.cover,
                            )
                          : DecoratedBox(
                              decoration: const BoxDecoration(
                                gradient: AppColors.primaryGradient,
                              ),
                              child: Center(
                                child: Text(
                                  initials,
                                  style: AppTextStyles.titleMedium.copyWith(
                                    color: AppColors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: AppTextStyles.titleMedium.copyWith(
                            color: palette.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          [
                            if ((app.applicantCity ?? '').isNotEmpty)
                              app.applicantCity!,
                            'Applied ${jobAge(app.createdAt)}',
                          ].join('  ·  '),
                          style: AppTextStyles.bodySmall.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (app.isShortlisted)
                    const StatusBadge('Shortlisted')
                  else if (app.isDeclined)
                    StatusBadge('Not selected', color: palette.textMuted)
                  else if (app.isNew)
                    const StatusBadge('New', color: AppColors.primaryBlue),
                ],
              ),
            ),
            if ((app.message ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                app.message!,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: palette.text,
                  height: 1.5,
                ),
              ),
            ],
            if ((app.phone ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.phone_outlined,
                    size: 15,
                    color: palette.textMuted,
                  ),
                  const SizedBox(width: 6),
                  SelectableText(
                    app.phone!,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                contact(Icons.call_outlined, 'Call', onCall),
                const SizedBox(width: 8),
                contact(Icons.chat_rounded, 'WhatsApp', onWhatsApp),
                const SizedBox(width: 8),
                contact(Icons.forum_outlined, 'Message', onMessage),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: onShortlist,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      minimumSize: const Size(0, 42),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      app.isShortlisted ? 'Shortlisted' : 'Shortlist',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onDecline,
                  child: Text(
                    'Not selected',
                    style: TextStyle(color: palette.textMuted),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
