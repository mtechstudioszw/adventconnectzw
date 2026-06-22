import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../models/church_model.dart';
import '../../services/church_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/screen_shell.dart';

/// Apply to manage a church. Two steps:
///   1. A showcase of what a church admin can do (the "power" pitch).
///   2. A short contact form (name + WhatsApp + optional email + role + note).
/// Inserts a `church_admins` row (status='pending'); the super admin talks
/// to the applicant on WhatsApp and approves from the dashboard. No document
/// upload — verification is the off-app conversation.
class ClaimChurchScreen extends StatefulWidget {
  const ClaimChurchScreen({super.key, required this.church});

  final Church church;

  @override
  State<ClaimChurchScreen> createState() => _ClaimChurchScreenState();
}

class _ClaimChurchScreenState extends State<ClaimChurchScreen> {
  int _step = 0; // 0 = showcase, 1 = form
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _note = TextEditingController();
  String _role = 'Elder';
  bool _saving = false;
  String? _error;

  // Eligibility gate (patch_121). While true we show a spinner; if the
  // user/church isn't eligible to claim, [_block] holds the reason and
  // the form is never shown.
  bool _checking = true;
  _ClaimBlock? _block;

  static const _roles = [
    'Pastor',
    'Elder',
    'Church Clerk',
    'Communications',
    'Deacon / Deaconess',
    'Other leader',
  ];

  @override
  void initState() {
    super.initState();
    _checkEligibility();
  }

  /// Decide whether this user can claim this church. Mirrors the server
  /// guard (church_admins_enforce_single_claim) so the user sees a clear
  /// message instead of a raw DB error on submit.
  Future<void> _checkEligibility() async {
    final state = await ChurchService.fetchClaimState(widget.church.id);
    if (!mounted) return;
    _ClaimBlock? block;
    if (state == null) {
      // Couldn't read state — fail open and let the form + server guard
      // handle it rather than blocking a legitimate claim.
      block = null;
    } else if (state.myClaimApproved) {
      block = const _ClaimBlock(
        icon: Icons.verified_rounded,
        title: 'You already manage this church',
        message:
            'Your admin access for this church is approved. Open it from the '
            'church page to post announcements and manage details.',
      );
    } else if (state.myClaimPending) {
      block = const _ClaimBlock(
        icon: Icons.hourglass_top_rounded,
        title: 'We\'re still reviewing your application',
        message:
            'Thanks for applying to manage this church. We\'re verifying your '
            'request and will let you know as soon as it\'s approved.',
      );
    } else if (state.churchHasApprovedAdmin) {
      block = const _ClaimBlock(
        icon: Icons.lock_outline_rounded,
        title: 'This church is already claimed',
        message:
            'Someone is already verified to manage this church, so it can\'t '
            'be claimed again.',
      );
    } else if (state.churchHasPendingOther) {
      block = const _ClaimBlock(
        icon: Icons.hourglass_top_rounded,
        title: 'A claim is already under review',
        message:
            'Someone has already applied to manage this church and we\'re '
            'reviewing it. If they\'re not approved, you can try again.',
      );
    } else if (state.myOtherPendingCount > 0) {
      block = const _ClaimBlock(
        icon: Icons.hourglass_top_rounded,
        title: 'You already have an application under review',
        message:
            'You can manage only one church. We\'re still reviewing your other '
            'application and will let you know once it\'s decided.',
      );
    } else if (state.myOtherApprovedCount > 0) {
      block = const _ClaimBlock(
        icon: Icons.info_outline_rounded,
        title: 'You can only manage one church',
        message:
            'You\'re already the admin of another church. Each member can '
            'manage a single church.',
      );
    }
    setState(() {
      _block = block;
      _checking = false;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Combine the applicant's church position with their free-text note so
  /// the super-admin sees both in the approval queue (the position can't go
  /// in the DB `role` column — that's reserved for the admin tier).
  String _composedNote() {
    final extra = _note.text.trim();
    final position = 'Position: $_role';
    return extra.isEmpty ? position : '$position\n$extra';
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ChurchService.applyForChurchAdmin(
        churchId: widget.church.id,
        // DB admin tier — the constraint only allows 'primary'/'standard'.
        // A claimant is requesting to be the church's primary admin; their
        // church position (Elder/Pastor/…) is captured in the note instead.
        role: 'primary',
        applicantName: _name.text,
        applicantPhone: _phone.text,
        applicantEmail: _email.text.trim().isEmpty ? null : _email.text,
        note: _composedNote(),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ctx.palette.sheet,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Application sent 🙏', style: AppTextStyles.headlineSmall),
          content: Text(
            'Thanks! We\'ll reach out on WhatsApp to verify you, then approve '
            'your access to manage ${widget.church.name}.',
            style: AppTextStyles.bodyMedium.copyWith(height: 1.5),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text('Got it', style: AppTextStyles.labelLarge),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (context.canPop()) context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Translate the server guard's coded exceptions (patch_121) into the
  /// same plain-language messages the eligibility gate uses. These only
  /// surface on a race (two people claiming at once); the normal path is
  /// blocked before the form even shows.
  String _friendlyError(Object e) {
    final raw = e.toString();
    if (raw.contains('CHURCH_ALREADY_CLAIMED')) {
      return 'This church has just been claimed by someone else.';
    }
    if (raw.contains('CHURCH_CLAIM_UNDER_REVIEW')) {
      return 'Someone else just applied for this church. If they\'re not '
          'approved, you can try again.';
    }
    if (raw.contains('USER_ALREADY_HAS_CLAIM')) {
      return 'You can only manage one church, and you already have a claim.';
    }
    return raw.replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: _checking
          ? _buildChecking(context)
          : _block != null
              ? _buildBlocked(context, _block!)
              : _step == 0
                  ? _buildShowcase(context)
                  : _buildForm(context),
    );
  }

  Widget _buildChecking(BuildContext context) {
    return Column(
      children: [
        ScreenHero(
          title: 'Manage your church',
          tagline: widget.church.name,
          subtitle: 'Checking availability…',
          fallbackRoute: 'churches',
        ),
        const Expanded(
          child: Center(
            child: CircularProgressIndicator(color: AppColors.primaryBlue),
          ),
        ),
      ],
    );
  }

  Widget _buildBlocked(BuildContext context, _ClaimBlock block) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHero(
            title: 'Manage your church',
            tagline: widget.church.name,
            subtitle: 'Become a verified admin for this church.',
            fallbackRoute: 'churches',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(block.icon,
                      color: AppColors.primaryBlue, size: 34),
                ),
                const SizedBox(height: 18),
                Text(
                  block.title,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.titleLarge.copyWith(
                    fontWeight: FontWeight.w800,
                    color: context.palette.text,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  block.message,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: context.palette.textMuted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 26),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.goNamed('churches'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text('Back to church',
                        style: AppTextStyles.buttonText),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- Step 1: showcase the power of being a church admin ----------------
  Widget _buildShowcase(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHero(
            title: 'Manage your church',
            tagline: widget.church.name,
            subtitle: 'Become a verified admin for this church.',
            fallbackRoute: 'churches',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'What you can do as a church admin',
                  style: AppTextStyles.titleLarge.copyWith(
                    fontWeight: FontWeight.w800,
                    color: context.palette.text,
                  ),
                ),
                const SizedBox(height: 16),
                const _Capability(
                  icon: Icons.campaign_rounded,
                  title: 'Post announcements',
                  body:
                      'Share notices that reach every member — in the church '
                      'feed AND your church channel in Advent Chat.',
                ),
                const _Capability(
                  icon: Icons.photo_camera_back_rounded,
                  title: 'Brand your church page',
                  body:
                      'Upload a cover photo + logo and keep your service '
                      'times, location and about up to date.',
                ),
                const _Capability(
                  icon: Icons.event_available_rounded,
                  title: 'Post events',
                  body: 'Add services, programmes and special events to the '
                      'events feed.',
                ),
                const _Capability(
                  icon: Icons.groups_rounded,
                  title: 'See your members',
                  body: 'Know who follows your church and grows with you.',
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_user_outlined,
                          color: AppColors.primaryBlue, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Admins are verified manually. After you apply we '
                          'reach out on WhatsApp before approving.',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: context.palette.textMuted,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => setState(() => _step = 1),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text('Apply to manage this church',
                        style: AppTextStyles.buttonText),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- Step 2: the contact form ------------------------------------------
  Widget _buildForm(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHero(
            title: 'Apply to manage',
            tagline: widget.church.name,
            subtitle: 'We\'ll verify you on WhatsApp before approving.',
            fallbackRoute: 'churches',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Label('Your name'),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(hintText: 'Full name'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter your name'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  _Label('WhatsApp number'),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                    ],
                    decoration:
                        const InputDecoration(hintText: 'e.g. +263 77 123 4567'),
                    validator: (v) => (v == null || v.trim().length < 7)
                        ? 'Enter a reachable WhatsApp number'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  _Label('Email (optional)'),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration:
                        const InputDecoration(hintText: 'you@example.com'),
                  ),
                  const SizedBox(height: 16),
                  _Label('Your role at the church'),
                  DropdownButtonFormField<String>(
                    initialValue: _role,
                    items: _roles
                        .map((r) =>
                            DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                    onChanged: (v) => setState(() => _role = v ?? _role),
                  ),
                  const SizedBox(height: 16),
                  _Label('Anything else? (optional)'),
                  TextFormField(
                    controller: _note,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 300,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText:
                          'Tell us a bit about your role / how to reach you',
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.red)),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.4, color: AppColors.white),
                            )
                          : Text('Send application',
                              style: AppTextStyles.buttonText),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _saving ? null : () => setState(() => _step = 0),
                    child: Text('Back',
                        style: AppTextStyles.labelMedium
                            .copyWith(color: context.palette.textMuted)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reason the claim form is blocked (already claimed / under review /
/// one-church limit). Rendered by [_ClaimChurchScreenState._buildBlocked].
class _ClaimBlock {
  const _ClaimBlock({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;
}

class _Capability extends StatelessWidget {
  const _Capability(
      {required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primaryBlue, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTextStyles.titleMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.palette.text,
                    )),
                const SizedBox(height: 2),
                Text(body,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: context.palette.textMuted,
                      height: 1.4,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Text(
        text,
        style: AppTextStyles.labelMedium.copyWith(
          fontWeight: FontWeight.w700,
          color: context.palette.text,
        ),
      ),
    );
  }
}
