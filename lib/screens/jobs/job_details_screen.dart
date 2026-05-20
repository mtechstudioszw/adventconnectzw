import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/job_model.dart';
import '../../services/job_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/start_conversation_sheet.dart';

class JobDetailsScreen extends StatefulWidget {
  const JobDetailsScreen({
    super.key,
    required this.jobId,
    this.initialJob,
  });

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
  bool _markingFilled = false;
  bool _reopening = false;

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
    _slide = Tween<double>(begin: 12, end: 0).animate(
      CurvedAnimation(parent: _entrance, curve: Curves.easeOut),
    );
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
        _job = fetched ?? _job;
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
        backgroundColor: AppColors.white,
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
              style: AppTextStyles.buttonText.copyWith(
                color: AppColors.textDark,
              ),
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
        _job = Job(
          id: job.id,
          posterId: job.posterId,
          posterName: job.posterName,
          title: job.title,
          company: job.company,
          location: job.location,
          type: job.type,
          salaryMin: job.salaryMin,
          salaryMax: job.salaryMax,
          currency: job.currency,
          description: job.description,
          requirements: job.requirements,
          category: job.category,
          contactPhone: job.contactPhone,
          companyLogoUrl: job.companyLogoUrl,
          isActive: job.isActive,
          status: 'filled',
          createdAt: job.createdAt,
        );
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
        backgroundColor: AppColors.white,
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
              style: AppTextStyles.buttonText.copyWith(
                color: AppColors.textDark,
              ),
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
        _job = Job(
          id: job.id,
          posterId: job.posterId,
          posterName: job.posterName,
          title: job.title,
          company: job.company,
          location: job.location,
          type: job.type,
          salaryMin: job.salaryMin,
          salaryMax: job.salaryMax,
          currency: job.currency,
          description: job.description,
          requirements: job.requirements,
          category: job.category,
          contactPhone: job.contactPhone,
          companyLogoUrl: job.companyLogoUrl,
          isActive: job.isActive,
          status: 'open',
          createdAt: job.createdAt,
        );
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

  Future<void> _messagePoster() async {
    final job = _job;
    if (job == null) return;
    await showStartConversationSheet(
      context,
      otherUserId: job.posterId,
      otherUserName: job.posterName,
      source: 'job_details',
    );
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
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final waUri = Uri.parse('https://wa.me/$digits');
    try {
      final launched =
          await launchUrl(waUri, mode: LaunchMode.externalApplication);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGrey,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _job == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryBlue),
      );
    }
    if (_error != null && _job == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: AppColors.red),
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
      );
    }
    final job = _job!;
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildHero(job),
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
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSummary(job),
                  const SizedBox(height: 16),
                  _buildApplyButton(),
                  const SizedBox(height: 20),
                  if (job.description != null && job.description!.isNotEmpty) ...[
                    _buildDescription(job),
                    const SizedBox(height: 16),
                  ],
                  if (job.requirements.isNotEmpty) ...[
                    _buildRequirements(job),
                    const SizedBox(height: 16),
                  ],
                  _buildEmployerCard(job),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero(Job job) {
    return ClipPath(
      clipper: _HeroClipper(),
      child: Container(
        decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _CircleIconButton(
                      icon: Icons.arrow_back,
                      onTap: () => context.canPop()
                          ? context.pop()
                          : context.goNamed('jobs'),
                    ),
                    const Spacer(),
                    _CircleIconButton(
                      icon: Icons.share_outlined,
                      onTap: () {},
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.white.withValues(alpha: 0.2),
                          ),
                        ),
                        child: job.companyLogoUrl != null &&
                                job.companyLogoUrl!.isNotEmpty
                            ? Image.network(
                                job.companyLogoUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    _logoFallback(job.company),
                              )
                            : _logoFallback(job.company),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              job.company,
                              style: AppTextStyles.labelMedium.copyWith(
                                color: AppColors.white.withValues(alpha: 0.7),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              job.title,
                              style: AppTextStyles.displayMedium.copyWith(
                                color: AppColors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _logoFallback(String company) {
    final parts = company
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    final initials = parts.isEmpty
        ? '?'
        : parts.length == 1
            ? parts.first.substring(0, 1).toUpperCase()
            : (parts.first.substring(0, 1) + parts[1].substring(0, 1))
                .toUpperCase();
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: AppTextStyles.titleMedium.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
    );
  }

  Widget _buildSummary(Job job) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _SummaryTile(
            icon: Icons.attach_money,
            label: 'Salary',
            value: job.formatSalary(),
          ),
          _verticalDivider(),
          _SummaryTile(
            icon: Icons.work_outline,
            label: 'Type',
            value: job.formatType(),
          ),
          _verticalDivider(),
          _SummaryTile(
            icon: Icons.place_outlined,
            label: 'Location',
            value:
                (job.location ?? '').isEmpty ? 'TBD' : job.location!,
          ),
        ],
      ),
    );
  }

  Widget _verticalDivider() {
    return Container(
      width: 1,
      height: 40,
      color: const Color.fromRGBO(26, 26, 46, 0.08),
    );
  }

  Widget _buildApplyButton() {
    final job = _job!;
    final hasPhone = (job.contactPhone ?? '').trim().isNotEmpty;

    if (_isPoster) {
      if (job.isFilled) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusPill(
              icon: Icons.check_circle_outline,
              label: 'Position filled',
              background: AppColors.successGreen.withValues(alpha: 0.12),
              foreground: AppColors.successGreen,
            ),
            const SizedBox(height: 10),
            _ReopenButton(
              loading: _reopening,
              onTap: _confirmReopen,
            ),
          ],
        );
      }
      return _MarkFilledButton(
        loading: _markingFilled,
        onTap: _confirmMarkFilled,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (job.isFilled) ...[
          _StatusPill(
            icon: Icons.check_circle_outline,
            label: 'Position filled',
            background: AppColors.successGreen.withValues(alpha: 0.12),
            foreground: AppColors.successGreen,
          ),
          const SizedBox(height: 10),
        ],
        _PrimaryActionButton(
          icon: Icons.chat_bubble_outline,
          label: 'Contact poster',
          onTap: _messagePoster,
        ),
        if (!job.isFilled && hasPhone) ...[
          const SizedBox(height: 10),
          _SecondaryActionButton(
            icon: Icons.send_outlined,
            label: job.isSeeking
                ? 'Contact via WhatsApp'
                : 'Apply via WhatsApp',
            onTap: _apply,
          ),
        ],
      ],
    );
  }

  Widget _buildDescription(Job job) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'About the role',
            style: AppTextStyles.titleLarge.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            job.description!,
            style: AppTextStyles.bodyMedium.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.85),
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequirements(Job job) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What you\'ll need',
            style: AppTextStyles.titleLarge.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          for (final req in job.requirements) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 6, right: 10),
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryBlue,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text(
                    req,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: const Color.fromRGBO(26, 26, 46, 0.85),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
            if (req != job.requirements.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildEmployerCard(Job job) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.business_center,
              color: AppColors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.isSeeking ? 'POSTED BY JOB SEEKER' : 'POSTED BY RECRUITER',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: const Color.fromRGBO(26, 26, 46, 0.5),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  job.posterName,
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 28);
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width,
      size.height - 28,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.white.withValues(alpha: 0.10)),
          ),
          child: Icon(icon, color: AppColors.white, size: 18),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: foreground.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: foreground, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppTextStyles.buttonText.copyWith(
              color: foreground,
              fontSize: 15,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkFilledButton extends StatelessWidget {
  const _MarkFilledButton({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryBlue, width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: loading ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primaryBlue,
                    ),
                  )
                else
                  const Icon(
                    Icons.check_circle_outline,
                    color: AppColors.primaryBlue,
                    size: 18,
                  ),
                const SizedBox(width: 8),
                Text(
                  loading ? 'Marking…' : 'Mark as filled',
                  style: AppTextStyles.buttonText.copyWith(
                    color: AppColors.primaryBlue,
                    fontSize: 15,
                    letterSpacing: 0.4,
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

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.30),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: AppColors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: AppTextStyles.buttonText.copyWith(
                    fontSize: 15,
                    letterSpacing: 0.4,
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

class _SecondaryActionButton extends StatelessWidget {
  const _SecondaryActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryBlue, width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: AppColors.primaryBlue, size: 18),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: AppTextStyles.buttonText.copyWith(
                    color: AppColors.primaryBlue,
                    fontSize: 15,
                    letterSpacing: 0.4,
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

class _ReopenButton extends StatelessWidget {
  const _ReopenButton({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryBlue, width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: loading ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primaryBlue,
                    ),
                  )
                else
                  const Icon(
                    Icons.refresh,
                    color: AppColors.primaryBlue,
                    size: 18,
                  ),
                const SizedBox(width: 8),
                Text(
                  loading ? 'Reopening…' : 'Reopen position',
                  style: AppTextStyles.buttonText.copyWith(
                    color: AppColors.primaryBlue,
                    fontSize: 15,
                    letterSpacing: 0.4,
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

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: AppColors.primaryBlue),
          const SizedBox(height: 6),
          Text(
            label.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.5),
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.titleMedium.copyWith(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
