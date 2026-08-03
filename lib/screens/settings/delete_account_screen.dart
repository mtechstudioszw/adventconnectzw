import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/screen_shell.dart';

/// The exit survey, and the account deletion behind it (#17, #18).
///
/// Two problems, one screen. Deleting an account has to call an Edge
/// Function, wipe the profile row, revoke a Google grant and clear local
/// storage — that is not instant on a Harare connection, and the old flow
/// spent it sitting on a frozen dialog. And the founder wants to know why
/// people leave, which nothing was asking.
///
/// So the survey **fills** the wait instead of adding to it: the deletion
/// starts the moment this screen opens, while the member is still reading
/// the question. By the time they have picked a reason it has almost always
/// finished, and the tap that submits is the tap that leaves.
///
/// That is the founder's motion rule applied literally — the work happens
/// behind something real rather than behind a spinner that says "waiting".
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key, this.autoStart = true});

  /// False in tests: [initState] otherwise begins deleting the account.
  final bool autoStart;

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  static const _reasons = <(String, IconData)>[
    ('I found what I needed', Icons.check_circle_outline_rounded),
    ('Not enough people I know', Icons.people_outline_rounded),
    ('Too many notifications', Icons.notifications_off_outlined),
    ('Privacy concerns', Icons.lock_outline_rounded),
    ('The app is hard to use', Icons.help_outline_rounded),
    ('Something kept going wrong', Icons.bug_report_outlined),
    ('Other', Icons.more_horiz_rounded),
  ];

  String? _reason;
  final _detail = TextEditingController();

  /// The deletion, started on open and awaited only at the very end.
  Future<AuthResult>? _deletion;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // Starts NOW, not on submit. This is the whole point of the screen.
    if (widget.autoStart) _deletion = AuthService.deleteAccount();
  }

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    // The survey first, and never awaited for long: it has to be written
    // while the caller still has a session, but a failure here must not
    // stop someone leaving.
    if (_reason != null) {
      try {
        await Supabase.instance.client
            .rpc('account_deletion_survey_submit', params: {
          'p_reason': _reason,
          'p_detail': _detail.text.trim().isEmpty ? null : _detail.text.trim(),
        }).timeout(const Duration(seconds: 4));
      } catch (_) {
        // Losing a survey answer is not a reason to trap someone in an
        // account they asked to delete.
      }
    }

    // The null branch is the test seam (autoStart: false) — nothing was
    // ever started, so there is nothing to wait for.
    final result = await (_deletion ?? Future.value(AuthResult.success(null)));
    if (!mounted) return;

    // The message goes up on the login screen, after we have left — a
    // snackbar on a screen that is being torn down is a snackbar nobody
    // reads.
    final messenger = ScaffoldMessenger.of(context);
    context.goNamed('login');
    messenger.showSnackBar(
      SnackBar(
        backgroundColor:
            result.isSuccess ? AppColors.successGreen : AppColors.darkNavy,
        content: Text(
          result.isSuccess
              ? 'Your account has been deleted.'
              : (result.errorMessage ?? 'Deletion failed. Contact support.'),
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            const ScreenHero(
              title: 'Before you go',
              subtitle: 'One question, then your account is gone for good.',
              fallbackRoute: 'settings',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  Text(
                    'What made you decide to leave?',
                    style: AppTextStyles.titleSmall.copyWith(
                      color: palette.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Optional, and it stays anonymous in our reports. It is '
                    'the only way we find out what to fix.',
                    style: AppTextStyles.caption.copyWith(
                      color: palette.textMuted,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final (label, icon) in _reasons)
                    _ReasonTile(
                      label: label,
                      icon: icon,
                      selected: _reason == label,
                      onTap: () => setState(() => _reason = label),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _detail,
                    maxLines: 3,
                    maxLength: 500,
                    style: AppTextStyles.bodyMedium.copyWith(color: palette.text),
                    decoration: InputDecoration(
                      hintText: 'Anything else? (optional)',
                      hintStyle: AppTextStyles.bodyMedium
                          .copyWith(color: palette.textMuted),
                      filled: true,
                      fillColor: palette.inputFill,
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
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _submitting ? null : _finish,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.red,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _reason == null ? 'Delete without saying' : 'Delete my account',
                              style: AppTextStyles.labelLarge
                                  .copyWith(color: AppColors.white),
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    // Honest: by this point it is genuinely already running.
                    'Your account is already being removed.',
                    style: AppTextStyles.caption.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasonTile extends StatelessWidget {
  const _ReasonTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primaryBlue.withValues(alpha: 0.10)
                  : palette.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppColors.primaryBlue : palette.divider,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? AppColors.primaryBlue : palette.textMuted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: palette.text,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle_rounded,
                      size: 20, color: AppColors.primaryBlue),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
