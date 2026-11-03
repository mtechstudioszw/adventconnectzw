import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth_service.dart';
import '../../services/two_step_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import 'widgets/auth_shell.dart';

/// "Enter the code from your authenticator app" — shown after the password
/// (or Google / Apple) step for a member who turned two-step on.
///
/// The router sends every location here while
/// [TwoStepService.challengePending] is true, so this screen has no back
/// arrow: the only ways out are a correct code or signing out.
class TwoStepChallengeScreen extends StatefulWidget {
  const TwoStepChallengeScreen({super.key});

  @override
  State<TwoStepChallengeScreen> createState() => _TwoStepChallengeScreenState();
}

class _TwoStepChallengeScreenState extends State<TwoStepChallengeScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await TwoStepService.verifyLogin(_code.text);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      _code.clear();
      return;
    }
    HapticFeedback.mediumImpact();
    // Splash re-runs the normal hand-off (biometric, profile setup, home).
    context.goNamed('splash');
  }

  Future<void> _signOut() async {
    await AuthService.signOut();
    if (!mounted) return;
    context.goNamed('login');
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      eyebrow: 'Two-step verification',
      title: 'Enter your\ncode',
      subtitle: 'Open your authenticator app and type the 6-digit code '
          'for Adventist Super App.',
      icon: Icons.verified_user_outlined,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: _busy ? null : _signOut,
            child: Text(
              'Sign out',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            'Lost your phone? Call or WhatsApp +263 77 809 2494',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: context.palette.textMuted,
              fontSize: 12,
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TwoStepCodeField(
            controller: _code,
            enabled: !_busy,
            onCompleted: _submit,
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.red),
            ),
          ],
          const SizedBox(height: 22),
          TwoStepButton(
            label: _busy ? 'Checking…' : 'Verify',
            busy: _busy,
            onTap: _busy ? null : _submit,
          ),
        ],
      ),
    );
  }
}

/// The 6-digit input, shared with the setup screen. Submits itself on the
/// sixth digit so a member never has to find the button.
class TwoStepCodeField extends StatelessWidget {
  const TwoStepCodeField({
    super.key,
    required this.controller,
    required this.onCompleted,
    this.enabled = true,
  });

  final TextEditingController controller;
  final VoidCallback onCompleted;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: true,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      maxLength: 6,
      autofillHints: const [AutofillHints.oneTimeCode],
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (v) {
        if (v.length == 6) onCompleted();
      },
      style: AppTextStyles.headlineMedium.copyWith(
        letterSpacing: 10,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        counterText: '',
        hintText: '000000',
        hintStyle: AppTextStyles.headlineMedium.copyWith(
          letterSpacing: 10,
          color: context.palette.textMuted.withValues(alpha: 0.4),
        ),
        filled: true,
        fillColor: context.palette.inputFill,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: AppColors.primaryBlue, width: 1.5),
        ),
      ),
    );
  }
}

/// Gradient primary button (design rule: gradient blue, radius 14).
class TwoStepButton extends StatelessWidget {
  const TwoStepButton({
    super.key,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.6 : 1,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppColors.white,
                        ),
                      )
                    : Text(
                        label,
                        style: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
