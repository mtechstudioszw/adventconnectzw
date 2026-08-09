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
/// ## Why the deletion no longer starts on open
///
/// It used to. The reasoning was that the survey should FILL the wait
/// rather than add to it, so `initState` kicked off `deleteAccount()` while
/// the member was still reading the question — the motion rule applied
/// literally.
///
/// Applied to the one screen where it must never be. A member tapped
/// Delete account, read "What made you decide to leave?", changed their
/// mind, and pressed back — and their posts, prayers, messages, friends and
/// profile photo were already gone, because the work had begun on the first
/// frame. There was no cancel path, and none was possible: the back arrow
/// popped a screen whose future was already running to completion.
///
/// Nothing may be destroyed until the member has said so on THIS screen,
/// with a final confirmation naming what goes. Deleting an account is not
/// a wait to be hidden — it is a decision to be sure of, and the seconds
/// it takes are the only honest part of it.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

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

  bool _submitting = false;

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  /// The last gate. Names what goes, and makes the destructive word the
  /// thing you have to tap — "Continue" was what the first dialog said,
  /// which reads as a step in a wizard rather than the end of one.
  Future<bool> _confirm() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'Your profile, photo, posts, prayers, messages and friends will '
          'be permanently deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep my account'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Delete for ever'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _finish() async {
    if (_submitting) return;
    if (!await _confirm()) return;
    if (!mounted) return;
    setState(() => _submitting = true);

    // The survey goes FIRST, while the session still exists.
    //
    // `account_deletion_survey_submit` is SECURITY DEFINER and stores
    // `auth.uid()`, so it has to run before the deletion signs the member
    // out — afterwards `auth.uid()` is null and the answer is lost. A
    // failure here must still never trap someone in an account they asked
    // to leave, hence the swallow.
    if (_reason != null) {
      try {
        await Supabase.instance.client
            .rpc(
              'account_deletion_survey_submit',
              params: {
                'p_reason': _reason,
                'p_detail': _detail.text.trim().isEmpty
                    ? null
                    : _detail.text.trim(),
              },
            )
            .timeout(const Duration(seconds: 4));
      } catch (_) {
        // Losing a survey answer is not a reason to stop the deletion.
      }
    }

    final result = await AuthService.deleteAccount();
    if (!mounted) return;

    // A failed deletion leaves the account whole. Stay on this screen and
    // say so, rather than routing to login as if it had worked.
    if (!result.isSuccess) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.darkNavy,
          content: Text(
            result.errorMessage ?? 'Deletion failed. Contact support.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
      return;
    }

    // The message goes up on the login screen, after we have left — a
    // snackbar on a screen that is being torn down is a snackbar nobody
    // reads.
    final messenger = ScaffoldMessenger.of(context);
    context.goNamed('login');
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: AppColors.successGreen,
        content: Text(
          'Your account has been deleted.',
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
              subtitle: 'One question. Nothing is deleted until you confirm.',
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
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: palette.text,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Anything else? (optional)',
                      hintStyle: AppTextStyles.bodyMedium.copyWith(
                        color: palette.textMuted,
                      ),
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
                              _reason == null
                                  ? 'Delete without saying'
                                  : 'Delete my account',
                              style: AppTextStyles.labelLarge.copyWith(
                                color: AppColors.white,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    // True again. This used to read "Your account is
                    // already being removed" — which was accurate, and was
                    // the bug: it was already being removed because the
                    // screen had started deleting it on open.
                    'Nothing has been deleted yet. You can still go back.',
                    textAlign: TextAlign.center,
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
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 20,
                    color: AppColors.primaryBlue,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
