import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import 'widgets/auth_shell.dart';

/// Dedicated screen for requesting a password-reset email. Replaces the
/// inline dialog that used to live inside login.
///
/// Supabase emails a **6-digit code**, not a link (see
/// [AuthService.sendPasswordReset] — no `redirectTo`, because deep links
/// were unreliable on mobile). On success this pushes straight to
/// reset_password_screen, where the code and the new password are
/// entered. Keep every string on this screen talking about a CODE.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  bool _sending = false;
  String? _error;

  // No entrance controller here any more — AuthShell owns the staggered
  // rise for every screen in the flow, so they all enter identically
  // instead of each one inventing its own fade.

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email is required';
    final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!regex.hasMatch(value.trim())) return 'Enter a valid email';
    return null;
  }

  Future<void> _send() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);

    final result =
        await AuthService.sendPasswordReset(_emailController.text.trim());
    if (!mounted) return;
    setState(() => _sending = false);

    if (result.isSuccess) {
      // We email a 6-digit CODE (not a link), so go straight to the in-app
      // code-entry screen with the email — the user never leaves the app.
      context.pushNamed('reset_password', extra: _emailController.text.trim());
    } else {
      setState(() => _error = result.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    // AuthShell, not AuthHero: the curved navy slab is gone (see
    // auth_shell.dart). The intro film's light field keeps running
    // behind this, so arriving here from onboarding is continuous
    // rather than a cut to an unrelated template header.
    //
    // No local "check your inbox" state either: on success we push
    // straight to the code-entry screen, which is where the user needs
    // to be. The old `_sent` branch was dead code — nothing ever set
    // the flag — and it told people to "tap the link in that email".
    return AuthShell(
      eyebrow: 'Account recovery',
      title: 'Forgot your\npassword?',
      // A CODE, not a link. AuthService.sendPasswordReset sends no
      // redirectTo, so Supabase emails a 6-digit recovery code which is
      // entered on the next screen — a deep link was unreliable on
      // mobile. This copy said "reset link" in three places, so members
      // sat waiting for a link that was never coming and never opened
      // the email they did get.
      subtitle: 'Enter your email and we\'ll send you a 6-digit reset '
          'code. It arrives in under a minute.',
      icon: Icons.lock_reset_rounded,
      onBack: () =>
          context.canPop() ? context.pop() : context.goNamed('login'),
      footer: _buildFooter(),
      child: _buildForm(),
    );
  }

  /// Support route, pinned at the bottom. It used to be jammed into the
  /// header subtitle as "if dosent work contact us at +263…", which put a
  /// phone number in the middle of an instruction.
  Widget _buildFooter() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: () => context.goNamed('login'),
          child: Text(
            'Back to sign in',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.primaryBlue,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          'Still stuck? Call or WhatsApp +263 77 809 2494',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySmall.copyWith(
            color: context.palette.textMuted,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: context.palette.card,
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
                  'EMAIL ADDRESS',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  validator: _validateEmail,
                  onFieldSubmitted: (_) => _send(),
                  style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'you@example.com',
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(left: 14, right: 10),
                      child: Icon(
                        Icons.email_outlined,
                        color: AppColors.primaryBlue,
                        size: 20,
                      ),
                    ),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 44, minHeight: 44),
                    filled: true,
                    fillColor: context.palette.inputFill,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:  BorderSide(
                        color: AppColors.divider,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:  BorderSide(
                        color: AppColors.divider,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: AppColors.primaryBlue,
                        width: 1.5,
                      ),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.red),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: AppColors.red,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'We\'ll only use this to verify it\'s you.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            _ErrorBanner(message: _error!),
          ],
          const SizedBox(height: 24),
          _GradientButton(
            label: _sending ? 'Sending…' : 'Send reset code',
            busy: _sending,
            onTap: _sending ? null : _send,
          ),
          // "Back to sign in" lives in the shell's footer now, pinned to
          // the bottom of the screen rather than floating under the
          // submit button where it competed with it.
        ],
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      // Dimmed whenever it can't be pressed, INCLUDING while sending —
      // the old condition excluded the busy case, so a button that was
      // mid-request still looked fully enabled.
      opacity: onTap == null ? 0.6 : 1,
      child: Container(
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
              child: Center(
                child: busy
                    // TODO(dark-mode): const CircularProgressIndicator — sits on primaryGradient.
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
                        style: AppTextStyles.buttonText.copyWith(
                          fontSize: 15,
                          letterSpacing: 0.4,
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

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.red, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.red,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
