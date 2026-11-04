import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/countries.dart';
import '../../config/share_config.dart';
import '../../models/job_model.dart';
import '../../services/job_application_service.dart';
import '../../services/job_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../services/messaging_service.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/ads/ad_banner.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/home/report_sheet.dart';
import '../../marketplace/market_ui.dart';
import '../../models/org_page_model.dart';
import '../../services/page_service.dart';
import '../../widgets/expandable_text.dart';
import '../../widgets/pages/page_tile.dart';
import '../../widgets/profile/profile_header.dart' show websiteLabel;
import '../../widgets/screen_shell.dart';
import '../../widgets/job_card.dart';
import '../../widgets/jobs/quick_apply_sheet.dart';
import '../../widgets/verified_tick.dart';
import '../../widgets/premium/boost_sheet.dart';
import '../../config/platform_flags.dart';
import '../../services/billing/boost_catalog.dart';

class JobDetailsScreen extends StatefulWidget {
  const JobDetailsScreen({super.key, required this.jobId, this.initialJob});

  final String jobId;
  final Job? initialJob;

  @override
  State<JobDetailsScreen> createState() => _JobDetailsScreenState();
}

class _JobDetailsScreenState extends State<JobDetailsScreen>
    with SingleTickerProviderStateMixin {
  Job? _job;
  bool _loading = true;
  String? _error;

  /// The server has no such job (deleted, or hidden from this viewer).
  /// A shared link to one crashed the screen on `_job!`; one opened from a
  /// stale list kept showing a job nobody could apply to.
  bool _gone = false;
  bool _markingFilled = false;
  bool _reopening = false;
  bool _renewing = false;
  bool _deleting = false;

  /// The real number of Quick applications (patch_278), null when unknown.
  int? _applicantCount;
  List<Job> _similar = const [];
  String? _extrasFor;

  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  @override
  void initState() {
    super.initState();
    _job = widget.initialJob;
    _loading = widget.initialJob == null;
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slide = Tween<double>(
      begin: 12,
      end: 0,
    ).animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOut));
    _bootstrap();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final fetched = await JobService.fetchJobById(widget.jobId);
      if (!mounted) return;
      setState(() {
        _job = fetched;
        _gone = fetched == null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load job.';
        _loading = false;
      });
    }
  }

  /// Applicant count and similar jobs, once per job.
  Future<void> _loadExtras(Job job) async {
    if (_extrasFor == job.id) return;
    _extrasFor = job.id;
    JobApplicationService.loadApplied();
    final count = await JobApplicationService.count(job.id);
    List<Job> similar = const [];
    try {
      final list = await JobService.fetchJobs(
        category: job.category,
        country: job.country,
        filters: JobFilters(postType: job.postType),
      );
      similar = [
        for (final j in list)
          if (j.id != job.id) j,
      ].take(8).toList();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _applicantCount = count;
      _similar = similar;
    });
  }

  bool get _quickApply =>
      _job != null &&
      _job!.isHiring &&
      JobApplicationService.available &&
      Supabase.instance.client.auth.currentUser != null;

  /// The poster's own routes, for "Or apply directly".
  List<ApplyRoute> _directRoutes(Job job) => [
    if ((job.applyUrl ?? '').trim().isNotEmpty)
      ApplyRoute(
        'url',
        Icons.open_in_new_rounded,
        'Apply online',
        websiteLabel(job.applyUrl!),
      ),
    if ((job.contactEmail ?? '').trim().isNotEmpty)
      ApplyRoute(
        'email',
        Icons.mail_outline,
        'Email',
        job.contactEmail!.trim(),
      ),
    if ((job.contactPhone ?? '').trim().isNotEmpty) ...[
      ApplyRoute(
        'whatsapp',
        Icons.chat_rounded,
        'WhatsApp',
        job.contactPhone!.trim(),
      ),
      ApplyRoute('call', Icons.call_outlined, 'Call', job.contactPhone!.trim()),
    ],
    const ApplyRoute(
      'chat',
      Icons.forum_rounded,
      'Message in the app',
      'Ask a question first',
    ),
  ];

  Future<void> _runRoute(Job job, String? choice) async {
    switch (choice) {
      case 'url':
        await _openUrl(job.applyUrl!.trim());
      case 'email':
        await _emailPoster(job);
      case 'whatsapp':
        await _apply();
      case 'call':
        await _callPoster();
      case 'chat':
        await _messagePoster();
    }
  }

  /// Quick apply when it's available, otherwise the poster's own routes.
  Future<void> _openApplySheet() async {
    final job = _job;
    if (job == null) return;
    if (!_quickApply) return _openContactSheet();
    final choice = await showQuickApplySheet(
      context,
      job: job,
      routes: _directRoutes(job),
    );
    if (!mounted) return;
    if (choice == 'sent') {
      setState(() => _applicantCount = (_applicantCount ?? 0) + 1);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Application sent. You'll be notified if you're shortlisted.",
          ),
        ),
      );
      return;
    }
    await _runRoute(job, choice);
  }

  bool get _isPoster {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    return uid != null && _job?.posterId == uid;
  }

  Future<void> _confirmMarkFilled() async {
    final job = _job;
    if (job == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.sheet,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Mark as filled?',
          style: AppTextStyles.titleLarge.copyWith(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This hides "${job.title}" from new applicants. You can\'t reopen it from the app.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: AppTextStyles.buttonText.copyWith(color: ctx.palette.text),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Mark as filled'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _markingFilled = true);
    try {
      await JobService.markAsFilled(job.id);
      if (!mounted) return;
      setState(() {
        _markingFilled = false;
        _job = job.copyWith(status: 'filled');
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Marked as filled.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _markingFilled = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not update the job. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  Future<void> _confirmReopen() async {
    final job = _job;
    if (job == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.sheet,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Reopen this listing?',
          style: AppTextStyles.titleLarge.copyWith(fontWeight: FontWeight.w700),
        ),
        content: Text(
          '"${job.title}" will show up again for applicants.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: AppTextStyles.buttonText.copyWith(color: ctx.palette.text),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reopen'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _reopening = true);
    try {
      await JobService.reopen(job.id);
      if (!mounted) return;
      setState(() {
        _reopening = false;
        _job = job.copyWith(status: 'open');
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Listing reopened.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _reopening = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not reopen the job. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  /// Owner-only Renew tile + 5-days-left warning. Hidden when the
  /// post is healthy (more than 5 days remaining) so we don't nag
  /// the poster about a job that's nowhere near expiry.
  Widget _buildExpiryBanner(Job job) {
    final days = job.daysUntilExpiry;
    final expired = job.isExpired;
    final urgent = expired || (days != null && days <= 5);
    if (!urgent) return const SizedBox.shrink();
    final title = expired
        ? 'This post has expired'
        : days == 0
        ? 'Expires today'
        : days == 1
        ? 'Expires tomorrow'
        : 'Expires in $days days';
    final body = expired
        ? 'It\'s hidden from applicants until you renew. One tap gives you another 30 days.'
        : 'Renew to give it another 30 days and re-arm the 5-days-out reminder.';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.goldAccent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.goldAccent.withValues(alpha: 0.40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule, size: 16, color: AppColors.goldAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: AppTextStyles.bodySmall.copyWith(
              color: context.palette.textMuted,
              height: 1.4,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _renewing ? null : _renew,
            icon: const Icon(
              Icons.refresh,
              size: 16,
              color: AppColors.primaryBlue,
            ),
            label: Text(
              _renewing ? 'Renewing…' : 'Renew for 30 days',
              style: AppTextStyles.buttonText.copyWith(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              side: BorderSide(
                color: AppColors.primaryBlue.withValues(alpha: 0.40),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _renew() async {
    final job = _job;
    if (job == null || _renewing) return;
    setState(() => _renewing = true);
    try {
      final updated = await JobService.renewJob(job.id);
      if (!mounted) return;
      setState(() {
        _job = updated;
        _renewing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.successGreen,
          content: Text(
            'Renewed — listed for another 30 days.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _renewing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not renew. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  Future<void> _editJob() async {
    final job = _job;
    if (job == null) return;
    final changed = await context.pushNamed<bool>('edit_job', extra: job);
    if (changed == true && mounted) {
      _bootstrap();
    }
  }

  Future<void> _confirmDelete() async {
    final job = _job;
    if (job == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.sheet,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete this job?',
          style: AppTextStyles.titleLarge.copyWith(fontWeight: FontWeight.w700),
        ),
        content: Text(
          '"${job.title}" will be removed permanently. Applicants who '
          'already messaged you keep their chats.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: AppTextStyles.buttonText.copyWith(color: ctx.palette.text),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await JobService.deleteJob(job.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.successGreen,
          content: Text(
            'Job deleted.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
      if (context.canPop()) {
        context.pop();
      } else {
        context.goNamed('jobs');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not delete. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  Future<void> _messagePoster() async {
    final job = _job;
    if (job == null) return;
    // Open an empty chat with the poster — WhatsApp behaviour, no
    // auto-sent greeting. The user types whatever opener they want.
    try {
      final convo = await MessagingService.createConversation(
        otherUserId: job.posterId,
        otherUserName: job.posterName,
        source: 'job',
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      context.pushNamed('chat', pathParameters: {'id': convo.id}, extra: convo);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not open chat. Please try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  /// Share the job posting with a friendly invite to the app.
  /// Points at the canonical Netlify landing page recipients can use
  /// to download the app.
  Future<void> _shareJob() async {
    final job = _job;
    if (job == null) return;
    final shareUrl = jobShareUrl(job.id);
    final text =
        '${job.title}\n\n'
        'Job opportunity on Adventist Super App:\n$shareUrl';
    try {
      await Share.share(text, subject: job.title);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not open the share sheet.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  Future<void> _apply() async {
    final job = _job;
    final phone = job?.contactPhone?.trim() ?? '';
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            job?.isSeeking == true
                ? 'No contact number shared yet.'
                : 'Recruiter hasn\'t shared a contact number.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
      return;
    }
    // Try to deep-link into WhatsApp. If the device doesn't have
    // WhatsApp installed we fall back to copying the number so the
    // user can paste it into whichever messaging app they do have.
    // Normalised against the JOB's country — a local "077…" must become
    // +263 (or +254…), not be dialled as-is.
    final digits =
        Countries.toWhatsAppDigits(phone, countryCode: job?.country) ??
        phone.replaceAll(RegExp(r'\D'), '');
    final message = Uri.encodeComponent(
      'Hi, I saw "${job?.title ?? 'your listing'}" on Adventist Super App.'
      '\n${jobShareUrl(job?.id ?? '')}',
    );
    final waUri = Uri.parse('https://wa.me/$digits?text=$message');
    try {
      final launched = await launchUrl(
        waUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) throw Exception('launch returned false');
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: phone));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'WhatsApp number copied: $phone',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------
  //  Redesign (28 Oct 2026): the marketplace's language for a job — a
  //  flat header, the role and employer up top, key facts as tiles,
  //  hairline sections (About, Requirements, How to apply), an honest
  //  verification note, and one primary action ("Apply now") with every
  //  real application route behind it. The poster's identity stays hidden
  //  until a chat is opened (earlier owner decision).
  // ---------------------------------------------------------------------

  OrgPage? _employerPage;

  Future<void> _loadEmployer(Job job) async {
    final id = job.pageId;
    if (id == null || _employerPage?.id == id) return;
    try {
      final page = await PageService.fetch(id);
      if (mounted) setState(() => _employerPage = page);
    } catch (_) {}
  }

  Future<void> _toggleSaved() async {
    final job = _job;
    if (job == null) return;
    final saved = JobService.savedIds.value.contains(job.id);
    try {
      await JobService.setSaved(job.id, !saved);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(saved ? 'Removed from saved jobs.' : 'Job saved.'),
        ),
      );
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

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openContactSheet() async {
    final job = _job;
    if (job == null) return;
    final palette = context.palette;
    final hasPhone = (job.contactPhone ?? '').trim().isNotEmpty;
    final hasEmail = (job.contactEmail ?? '').trim().isNotEmpty;
    final hasUrl = (job.applyUrl ?? '').trim().isNotEmpty;
    final choice = await showModalBottomSheet<String>(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                job.isSeeking
                    ? 'Contact ${job.title}'
                    : 'Apply for ${job.title}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.titleLarge.copyWith(
                  color: palette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if ((job.applyInstructions ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  job.applyInstructions!,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: palette.textMuted,
                    height: 1.45,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (hasUrl) ...[
                MarketContactOption(
                  icon: Icons.open_in_new_rounded,
                  title: 'Apply online',
                  subtitle: websiteLabel(job.applyUrl!),
                  onTap: () => Navigator.pop(ctx, 'url'),
                ),
                const SizedBox(height: 10),
              ],
              if (hasEmail) ...[
                MarketContactOption(
                  icon: Icons.mail_outline,
                  title: 'Email',
                  subtitle: job.contactEmail!.trim(),
                  onTap: () => Navigator.pop(ctx, 'email'),
                ),
                const SizedBox(height: 10),
              ],
              if (hasPhone) ...[
                MarketContactOption(
                  icon: Icons.chat_rounded,
                  title: 'WhatsApp',
                  subtitle: 'Opens WhatsApp to ${job.contactPhone!.trim()}',
                  onTap: () => Navigator.pop(ctx, 'whatsapp'),
                ),
                const SizedBox(height: 10),
                MarketContactOption(
                  icon: Icons.call_outlined,
                  title: 'Call',
                  subtitle: job.contactPhone!.trim(),
                  onTap: () => Navigator.pop(ctx, 'call'),
                ),
                const SizedBox(height: 10),
              ],
              MarketContactOption(
                icon: Icons.forum_rounded,
                title: 'Message in the app',
                subtitle: 'Ask a question before you apply',
                onTap: () => Navigator.pop(ctx, 'chat'),
              ),
              const SizedBox(height: 12),
              Text(
                'Never pay to apply for a job. Report listings that ask for '
                'money.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    await _runRoute(job, choice);
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;
    if (job != null) {
      _loadEmployer(job);
      _loadExtras(job);
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _buildBody(),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (job != null && !_gone && !_isPoster) _buildActionBar(job),
          const SafeArea(
            top: false,
            child: AdBanner(padding: EdgeInsets.symmetric(vertical: 6)),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar(Job job) {
    final open = job.isOpen && !job.isExpired;
    return AnimatedBuilder(
      animation: Listenable.merge([
        JobService.savedIds,
        JobApplicationService.appliedJobIds,
      ]),
      builder: (context, _) {
        final saved = JobService.savedIds.value;
        final applied = JobApplicationService.appliedJobIds.value.contains(
          job.id,
        );
        final isSaved = saved.contains(job.id);
        final palette = context.palette;
        return MarketActionBar(
          chat: Semantics(
            button: true,
            label: isSaved ? 'Remove from saved jobs' : 'Save job',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: _toggleSaved,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: palette.scaffoldBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: palette.divider),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isSaved
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      size: 20,
                      color: isSaved ? AppColors.primaryBlue : palette.text,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isSaved ? 'Saved' : 'Save',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: palette.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          primary: open && applied
              ? MarketPill(
                  label: 'Applied',
                  leading: Icons.check_circle_rounded,
                  bg: AppColors.successGreen.withValues(alpha: 0.12),
                  fg: AppColors.successGreen,
                  onTap: () => context.pushNamed(
                    'my_jobs',
                    queryParameters: {'tab': 'applied'},
                  ),
                )
              : open
              ? MarketPill(
                  label: job.isSeeking
                      ? 'Contact this person'
                      : _quickApply
                      ? 'Quick apply'
                      : 'Apply now',
                  trailing: const Icon(Icons.arrow_forward_rounded, size: 18),
                  bg: AppColors.primaryBlue,
                  fg: AppColors.white,
                  raised: true,
                  onTap: _openApplySheet,
                )
              : MarketPill(
                  label: job.isFilled
                      ? 'Position filled'
                      : job.isExpired
                      ? 'No longer accepting applications'
                      : 'Not open yet',
                  bg: palette.cardMuted,
                  fg: palette.textMuted,
                  onTap: null,
                ),
        );
      },
    );
  }

  Widget _buildTopBar(Job job) {
    return FlatStatusBar(
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: Row(
            children: [
              const ScreenHeroBackButton(fallbackRoute: 'jobs'),
              const Spacer(),
              HeaderIconButton(
                icon: Icons.ios_share_rounded,
                tooltip: 'Share job',
                onTap: _shareJob,
              ),
              if (!_isPoster) ...[
                const SizedBox(width: 8),
                HeaderIconButton(
                  icon: Icons.flag_outlined,
                  tooltip: 'Report job',
                  onTap: () => showReportSheet(
                    context,
                    contentType: 'job',
                    contentId: job.id,
                    contentLabel: job.title,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_gone) return _buildGone();
    if (_loading && _job == null) {
      return const Center(child: BrandSpinner(size: 30));
    }
    if (_error != null && _job == null) {
      return _withBack(
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: AppColors.red),
                const SizedBox(height: 12),
                Text(_error!, style: AppTextStyles.bodyMedium),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _error = null;
                    });
                    _bootstrap();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final job = _job!;
    final palette = context.palette;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _buildTopBar(job),
        AnimatedBuilder(
          animation: _entrance,
          builder: (context, child) => Opacity(
            opacity: _fade.value,
            child: Transform.translate(
              offset: Offset(0, _slide.value),
              child: child,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildIntro(job),
                const SizedBox(height: 20),
                _buildFacts(job),
                const SizedBox(height: 16),
                _buildTrustNote(),
                if (_isPoster)
                  MarketSection(
                    title: 'Your listing',
                    child: _buildOwnerTools(job),
                  ),
                if ((job.description ?? '').trim().isNotEmpty)
                  MarketSection(
                    title: job.isSeeking ? 'About me' : 'About the role',
                    child: ExpandableText(
                      text: job.description!.trim(),
                      collapsedLines: 8,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: palette.text,
                        height: 1.6,
                      ),
                    ),
                  ),
                if (job.requirements.isNotEmpty)
                  MarketSection(
                    title: job.isSeeking
                        ? 'Skills & experience'
                        : 'Requirements',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final r in job.requirements)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(
                                    top: 8,
                                    right: 12,
                                  ),
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: AppColors.primaryBlue,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    r,
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      color: palette.text,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                if (!job.isSeeking)
                  MarketSection(
                    title: 'How to apply',
                    child: _buildHowToApply(job),
                  ),
                if (_employerPage != null)
                  MarketSection(
                    title: 'About the employer',
                    child: PageTile(
                      page: _employerPage!,
                      onTap: () => context.pushNamed(
                        'page_details',
                        pathParameters: {'id': _employerPage!.id},
                        extra: _employerPage,
                      ),
                    ),
                  ),
                if (_similar.isNotEmpty)
                  MarketSection(
                    title: job.isSeeking ? 'Others available' : 'Similar jobs',
                    child: SizedBox(
                      height: 156,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none,
                        itemCount: _similar.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, i) {
                          final j = _similar[i];
                          return SizedBox(
                            width: 280,
                            child: JobCard(
                              job: j,
                              compact: true,
                              onTap: () => context.pushReplacementNamed(
                                'job_details',
                                pathParameters: {'id': j.id},
                                extra: j,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String get _employerName {
    final job = _job!;
    if (_employerPage != null) return _employerPage!.name;
    return job.company.trim().isNotEmpty
        ? job.company.trim()
        : (job.isSeeking ? 'Looking for work' : 'Employer not named');
  }

  Widget _buildIntro(Job job) {
    final palette = context.palette;
    final cat = JobCategory.byId(job.category);
    final logo = _employerPage?.logoUrl;
    final initials = _employerName
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                width: 64,
                height: 64,
                child: logo != null
                    ? CachedImage(logo, fit: BoxFit.cover)
                    : ColoredBox(
                        color: AppColors.primaryBlue.withValues(alpha: 0.10),
                        child: Center(
                          child: job.isSeeking
                              ? const Icon(
                                  Icons.person_search_outlined,
                                  color: AppColors.primaryBlue,
                                  size: 28,
                                )
                              : (job.company.trim().isEmpty
                                    ? Icon(
                                        cat?.icon ?? Icons.work_outline,
                                        color: AppColors.primaryBlue,
                                        size: 28,
                                      )
                                    : Text(
                                        initials,
                                        style: AppTextStyles.titleLarge
                                            .copyWith(
                                              color: AppColors.primaryBlue,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      )),
                        ),
                      ),
              ),
            ),
            const Spacer(),
            if (job.isSeeking)
              const _Tag(text: 'Looking for work', color: AppColors.primaryBlue)
            else if (job.isFilled)
              const _Tag(text: 'Filled', color: AppColors.successGreen)
            else if (job.isExpired)
              const _Tag(text: 'Closed', color: AppColors.red)
            else if (job.status == 'pending')
              const _Tag(
                text: 'Waiting for review',
                color: AppColors.goldAccent,
              )
            else if (job.status == 'rejected')
              const _Tag(text: 'Not approved', color: AppColors.red),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          job.title,
          style: AppTextStyles.headlineSmall.copyWith(
            color: palette.text,
            fontWeight: FontWeight.w700,
            fontSize: 24,
            height: 1.25,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: _employerPage == null
              ? null
              : () => context.pushNamed(
                  'page_details',
                  pathParameters: {'id': _employerPage!.id},
                  extra: _employerPage,
                ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _employerName,
                  style: AppTextStyles.titleSmall.copyWith(
                    color: _employerPage != null
                        ? AppColors.primaryBlue
                        : palette.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_employerPage?.isVerified ?? false)
                const VerifiedTick(size: 15),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          [
            job.place,
            'Posted ${_ago(job.createdAt)}',
          ].where((s) => s.isNotEmpty).join('  ·  '),
          style: AppTextStyles.bodyMedium.copyWith(color: palette.textMuted),
        ),
        if (job.payLabel != null || job.isUrgent) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              if (job.payLabel != null)
                Flexible(
                  child: Text(
                    job.payLabel!,
                    style: AppTextStyles.headlineSmall.copyWith(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w700,
                      fontSize: 22,
                    ),
                  ),
                ),
              if (job.payLabel != null && job.isUrgent)
                const SizedBox(width: 10),
              if (job.isUrgent)
                job.isSeeking
                    ? const StatusBadge('Available now')
                    : const JobChip.urgent(),
            ],
          ),
        ],
        if (job.isHiring && job.isOpen && _applicantCount != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.people_outline_rounded,
                size: 16,
                color: palette.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                _applicantCount == 0
                    ? 'Be one of the first to apply'
                    : _applicantCount == 1
                    ? '1 person has applied'
                    : '$_applicantCount people have applied',
                style: AppTextStyles.bodySmall.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildFacts(Job job) {
    final tiles = <(IconData, String, String)>[
      (Icons.work_outline, 'Type', job.formatType()),
      (Icons.trending_up_rounded, 'Experience', job.levelLabel()),
      if (job.workArrangementLabel != null)
        (Icons.home_work_outlined, 'Where', job.workArrangementLabel!),
      // Pay leads the page in large type above these tiles.
      (
        JobCategory.byId(job.category)?.icon ?? Icons.category_outlined,
        'Field',
        JobCategory.labelFor(job.category),
      ),
      if (job.expiresAt != null && !job.isExpired)
        (Icons.event_outlined, 'Closes', _date(job.expiresAt!)),
    ];
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final w = (c.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final t in tiles)
                  Container(
                    width: w,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: palette.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: palette.divider),
                    ),
                    child: Row(
                      children: [
                        Icon(t.$1, size: 18, color: AppColors.primaryBlue),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.$2,
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: palette.textMuted,
                                ),
                              ),
                              Text(
                                t.$3,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.labelLarge.copyWith(
                                  color: palette.text,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        if (job.sabbathFriendly || job.isSdaInstitution) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (job.sabbathFriendly)
                const _Tag(
                  text: 'Sabbath-friendly hours',
                  color: AppColors.primaryBlue,
                  icon: Icons.brightness_3_outlined,
                ),
              if (job.isSdaInstitution)
                const _Tag(
                  text: 'Adventist institution',
                  color: AppColors.primaryBlue,
                  icon: Icons.church_outlined,
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// Says plainly what has and hasn't been checked.
  Widget _buildTrustNote() {
    final palette = context.palette;
    final verified = _employerPage?.isVerified ?? false;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (verified ? AppColors.successGreen : AppColors.goldAccent)
            .withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            verified ? Icons.verified_outlined : Icons.info_outline_rounded,
            size: 18,
            color: verified ? AppColors.successGreen : AppColors.goldAccent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              verified
                  ? 'The employer is a verified organization. Job details are '
                        'written by the employer.'
                  : 'Details are written by the poster and haven\'t been '
                        'verified by the app team. Never pay to apply.',
              style: AppTextStyles.bodySmall.copyWith(
                color: palette.text,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHowToApply(Job job) {
    final palette = context.palette;
    final routes = [
      if (_quickApply) 'with Quick apply here',
      if ((job.applyUrl ?? '').isNotEmpty) 'online',
      if ((job.contactEmail ?? '').trim().isNotEmpty) 'by email',
      if ((job.contactPhone ?? '').trim().isNotEmpty) 'by WhatsApp or phone',
      'by message in the app',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((job.applyInstructions ?? '').isNotEmpty) ...[
          Text(
            job.applyInstructions!,
            style: AppTextStyles.bodyMedium.copyWith(
              color: palette.text,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 10),
        ],
        Text(
          'Apply ${routes.join(', ')}.'
          '${job.expiresAt != null && !job.isExpired ? ' Closes ${_date(job.expiresAt!)}.' : ''}',
          style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
        ),
      ],
    );
  }

  Widget _buildOwnerTools(Job job) {
    final palette = context.palette;
    Widget action(
      IconData icon,
      String label,
      VoidCallback? onTap, {
      bool danger = false,
    }) => OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: danger ? AppColors.red : palette.text,
        side: BorderSide(color: palette.divider),
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    final statusText = switch (job.status) {
      'pending' =>
        'Waiting for review — it goes live once a moderator approves it.',
      'rejected' =>
        'Not approved by the moderators. Edit it and contact support if you think this is a mistake.',
      'filled' => 'Marked as filled and hidden from new applicants.',
      _ when job.isExpired => 'Expired and hidden from applicants.',
      _ => 'Live — people can see and apply.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          statusText,
          style: AppTextStyles.bodyMedium.copyWith(
            color: palette.text,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 12),
        _buildExpiryBanner(job),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (job.isHiring && JobApplicationService.available)
              FilledButton.icon(
                onPressed: () => context.pushNamed(
                  'job_applicants',
                  pathParameters: {'id': job.id},
                  extra: job,
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  minimumSize: const Size(0, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.people_alt_outlined, size: 18),
                label: Text(
                  _applicantCount == null || _applicantCount == 0
                      ? 'Applicants'
                      : 'Applicants · $_applicantCount',
                ),
              ),
            action(Icons.edit_outlined, 'Edit', _editJob),
            if (job.isOpen && !job.isExpired)
              action(
                Icons.check_circle_outline,
                _markingFilled ? 'Saving…' : 'Mark as filled',
                _markingFilled ? null : _confirmMarkFilled,
              ),
            // Paid boosts (patch 289) — Android only, live jobs only.
            if (!kHidePayments && job.isOpen && !job.isExpired)
              action(
                Icons.trending_up_rounded,
                job.isFeatured ? 'Feature again' : 'Feature this job',
                () {
                  final id = int.tryParse(job.id);
                  if (id == null) return;
                  showBoostSheet(
                    context,
                    kind: BoostKind.job,
                    targetId: id,
                    targetTitle: job.title,
                  );
                },
              ),
            if (job.isFilled)
              action(
                Icons.replay_rounded,
                _reopening ? 'Reopening…' : 'Reopen',
                _reopening ? null : _confirmReopen,
              ),
            action(
              Icons.delete_outline,
              _deleting ? 'Deleting…' : 'Delete',
              _deleting ? null : _confirmDelete,
              danger: true,
            ),
          ],
        ),
      ],
    );
  }

  static String _ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays >= 1) return '${diff.inDays}d ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    return 'just now';
  }

  static String _date(DateTime d) {
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day} ${m[d.month - 1]}';
  }

  Widget _withBack(Widget child) {
    return SafeArea(
      child: Stack(
        children: [
          child,
          const Positioned(top: 4, left: 4, child: BackButton()),
        ],
      ),
    );
  }

  Widget _buildGone() {
    final palette = context.palette;
    return _withBack(
      Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.work_off_outlined, size: 48, color: palette.textMuted),
              const SizedBox(height: 12),
              Text(
                'This job is no longer available',
                textAlign: TextAlign.center,
                style: AppTextStyles.titleMedium.copyWith(
                  color: palette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'The poster may have removed it.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _emailPoster(Job job) async {
    final email = (job.contactEmail ?? '').trim();
    final subject = Uri.encodeComponent(
      job.isSeeking ? 'Re: ${job.title}' : 'Application: ${job.title}',
    );
    try {
      final ok = await launchUrl(
        Uri.parse('mailto:$email?subject=$subject'),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) throw Exception('launch failed');
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: email));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No email app found. Address copied: $email')),
      );
    }
  }

  /// Direct phone-call shortcut for the job's contact_phone.
  /// Complements _apply() (WhatsApp) so the poster can be reached
  /// however the applicant prefers.
  Future<void> _callPoster() async {
    final phone = (_job?.contactPhone ?? '').trim();
    if (phone.isEmpty) return;
    final cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$cleaned');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw Exception('launch failed');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not start the call.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  // _buildEmployerCard removed — the job screen no longer reveals the
  // poster's identity. The poster is only reachable via "Contact
  // poster", which resolves their real name from their profile.
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color, this.icon});
  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: AppTextStyles.labelSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
