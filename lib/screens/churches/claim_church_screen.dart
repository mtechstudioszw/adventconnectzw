import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../models/church_model.dart';
import '../../services/account_service.dart';
import '../../services/church_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/screen_shell.dart';

/// Apply to become a church's admin. Inserts into `church_admins` with
/// status='pending'. Reviewer verifies by WhatsApp.
class ClaimChurchScreen extends StatefulWidget {
  const ClaimChurchScreen({super.key, required this.church});

  final Church church;

  @override
  State<ClaimChurchScreen> createState() => _ClaimChurchScreenState();
}

class _ClaimChurchScreenState extends State<ClaimChurchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();

  String _role = 'standard';
  String? _letterUrl;
  bool _uploading = false;
  bool _saving = false;
  String? _error;

  AccountState? _account;
  bool _checkingAccount = true;

  @override
  void initState() {
    super.initState();
    _addressController.text = widget.church.address ?? '';
    _checkAccount();
  }

  Future<void> _checkAccount() async {
    try {
      final state = await AccountService.fetchMyAccount();
      if (!mounted) return;
      setState(() {
        _account = state;
        _checkingAccount = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _checkingAccount = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _pickLetter() async {
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final url = await StorageService.pickAndUploadEventFlyer();
      if (!mounted) return;
      if (url != null) setState(() => _letterUrl = url);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not upload letter. Try again.');
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    if (_letterUrl == null) {
      setState(() => _error = 'Upload your appointment letter or proof.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ChurchService.applyForChurchAdmin(
        churchId: widget.church.id,
        role: _role,
        appointmentLetterUrl: _letterUrl,
        applicantName: _nameController.text,
        applicantPhone: _phoneController.text,
      );
      // Also push the physical address through the church_edit_suggestions
      // queue so an admin can apply it to the church row. We do this on
      // every claim — addresses are the single most useful field for
      // distance sorting and directions, so we want it captured at
      // claim time even if the church already has one in the DB.
      final newAddress = _addressController.text.trim();
      if (newAddress.isNotEmpty &&
          newAddress != (widget.church.address ?? '').trim()) {
        try {
          await ChurchService.suggestEdit(
            churchId: widget.church.id,
            fieldName: 'address',
            currentValue: widget.church.address ?? '',
            suggestedValue: newAddress,
          );
        } catch (_) {
          // Best-effort — don't block the claim if this fails.
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.successGreen,
          content: Text(
            'Application sent — we\'ll verify via WhatsApp.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
      if (context.canPop()) context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAccount) {
      return Scaffold(
        backgroundColor: context.palette.scaffoldBg,
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.primaryBlue),
        ),
      );
    }
    if (_account != null && !_account!.isBusiness) {
      return Scaffold(
        backgroundColor: context.palette.scaffoldBg,
        body: SingleChildScrollView(
          child: Column(
            children: [
              ScreenHero(
                title: 'Claim this church',
                tagline: widget.church.name,
                subtitle: 'Business account required.',
                fallbackRoute: 'churches',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: _ClaimBusinessGate(account: _account!),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.lightGrey,
      body: SingleChildScrollView(
        child: Column(
          children: [
            ScreenHero(
              title: 'Claim this church',
              tagline: widget.church.name,
              subtitle:
                  'For pastors and church admins. We verify each application by WhatsApp.',
              fallbackRoute: 'churches',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InfoBanner(
                      icon: Icons.lock_outline,
                      message:
                          'Once approved you\'ll be able to post announcements, events and church information.',
                    ),
                    const SizedBox(height: 16),
                    ScreenCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Label(text: 'Your full name'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _nameController,
                            textCapitalization: TextCapitalization.words,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Name is required';
                              }
                              return null;
                            },
                            style: AppTextStyles.bodyLarge
                                .copyWith(fontSize: 15),
                            decoration: _decoration(
                              hint: 'Tendai Moyo',
                              icon: Icons.person_outline,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _Label(text: 'Phone (WhatsApp)'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9+\s\-]'),
                              ),
                            ],
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Phone is required';
                              }
                              if (v.replaceAll(RegExp(r'\D'), '').length <
                                  9) {
                                return 'Enter a valid number';
                              }
                              return null;
                            },
                            style: AppTextStyles.bodyLarge
                                .copyWith(fontSize: 15),
                            decoration: _decoration(
                              hint: '+263 77 123 4567',
                              icon: Icons.phone_outlined,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _Label(text: 'Physical address of the church'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _addressController,
                            textCapitalization: TextCapitalization.words,
                            minLines: 1,
                            maxLines: 2,
                            validator: (v) {
                              if (v == null || v.trim().length < 6) {
                                return 'Enter a real street address';
                              }
                              return null;
                            },
                            style: AppTextStyles.bodyLarge
                                .copyWith(fontSize: 15),
                            decoration: _decoration(
                              hint: 'e.g. 5 Samora Machel Ave, Harare',
                              icon: Icons.place_outlined,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Used to show the church on the map and sort by distance for nearby members.',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: const Color.fromRGBO(26, 26, 46, 0.6),
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _Label(text: 'Your role'),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _RoleChip(
                                label: 'Primary admin',
                                description: 'Full control. One per church.',
                                active: _role == 'primary',
                                onTap: () => setState(() => _role = 'primary'),
                              ),
                              const SizedBox(width: 10),
                              _RoleChip(
                                label: 'Standard admin',
                                description: 'Post content only.',
                                active: _role == 'standard',
                                onTap: () =>
                                    setState(() => _role = 'standard'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ScreenCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Label(text: 'Appointment letter / proof'),
                          const SizedBox(height: 8),
                          Text(
                            'Photo of your church appointment letter or a confirmation note from your pastor.',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: const Color.fromRGBO(26, 26, 46, 0.6),
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _LetterPicker(
                            url: _letterUrl,
                            uploading: _uploading,
                            onTap: _pickLetter,
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      ErrorBanner(message: _error!),
                    ],
                    const SizedBox(height: 24),
                    PrimaryGradientButton(
                      label: _saving ? 'Submitting...' : 'Submit application',
                      busy: _saving,
                      onTap: _saving ? null : _submit,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 14, right: 10),
        child: Icon(icon, color: AppColors.primaryBlue, size: 20),
      ),
      prefixIconConstraints:
          const BoxConstraints(minWidth: 44, minHeight: 44),
      filled: true,
      fillColor: AppColors.lightGrey,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color.fromRGBO(26, 26, 46, 0.06)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color.fromRGBO(26, 26, 46, 0.06)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            const BorderSide(color: AppColors.primaryBlue, width: 1.5),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: AppTextStyles.labelSmall.copyWith(
        color: const Color.fromRGBO(26, 26, 46, 0.65),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({
    required this.label,
    required this.description,
    required this.active,
    required this.onTap,
  });

  final String label;
  final String description;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.primaryBlue.withValues(alpha: 0.08)
                  : AppColors.lightGrey,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: active ? AppColors.primaryBlue : Colors.transparent,
                width: 1.4,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color:
                        active ? AppColors.primaryBlue : AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: const Color.fromRGBO(26, 26, 46, 0.6),
                    height: 1.4,
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

class _LetterPicker extends StatelessWidget {
  const _LetterPicker({
    required this.url,
    required this.uploading,
    required this.onTap,
  });

  final String? url;
  final bool uploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final has = url != null && url!.isNotEmpty;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: uploading ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: has
                ? AppColors.successGreen.withValues(alpha: 0.08)
                : AppColors.lightGrey,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: has
                  ? AppColors.successGreen
                  : AppColors.primaryBlue.withValues(alpha: 0.3),
              width: has ? 1.5 : 1.2,
              style: has ? BorderStyle.solid : BorderStyle.solid,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: has
                      ? AppColors.successGreen.withValues(alpha: 0.18)
                      : AppColors.primaryBlue.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  has ? Icons.check : Icons.upload_outlined,
                  color:
                      has ? AppColors.successGreen : AppColors.primaryBlue,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  uploading
                      ? 'Uploading…'
                      : has
                          ? 'Letter uploaded. Tap to replace.'
                          : 'Upload your appointment letter',
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color:
                        has ? AppColors.successGreen : AppColors.primaryBlue,
                  ),
                ),
              ),
              if (uploading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primaryBlue,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClaimBusinessGate extends StatelessWidget {
  const _ClaimBusinessGate({required this.account});

  final AccountState account;

  @override
  Widget build(BuildContext context) {
    final pending = account.hasPendingApplication;
    final rejected = account.hasRejectedApplication;

    final (String title, String body, String cta) =
        pending
            ? (
                'Your business application is in review',
                'Once your business account is approved, you\'ll be able '
                    'to claim this church listing.',
                'OK',
              )
            : rejected
                ? (
                    'Your last application was declined',
                    account.latestApplication?.reviewerNote?.trim().isNotEmpty == true
                        ? account.latestApplication!.reviewerNote!.trim()
                        : 'Please review your details and reapply.',
                    'Re-apply',
                  )
                : (
                    'Business account required',
                    'Claiming a church listing is only available to '
                        'business accounts. Apply for one from your profile '
                        'to get started.',
                    'Apply for Business',
                  );

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color.fromRGBO(26, 26, 46, 0.06),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(13, 27, 62, 0.06),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.darkNavy, Color(0xFF1A2F5A)],
              ),
            ),
            child: const Icon(
              Icons.business_center,
              color: AppColors.goldAccent,
              size: 30,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyles.headlineMedium.copyWith(
              color: AppColors.text,
              fontWeight: FontWeight.w700,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.70),
              fontSize: 14,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 22),
          Container(
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  // ClaimChurchScreen is currently routed to the
                  // ClaimChurchComingSoonScreen — this branch is dead
                  // until the full church-admin module ships. The old
                  // apply_business jump went away with patch_031; we
                  // just pop here so any leftover entry point still
                  // does something sensible.
                  context.pop();
                },
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      cta,
                      style: AppTextStyles.buttonText.copyWith(
                        color: AppColors.white,
                        fontSize: 15,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
