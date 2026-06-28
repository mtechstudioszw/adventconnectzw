import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/support_sheet.dart';
import 'widgets/auth_hero.dart';

/// Sets a new password. Two modes:
///  - OTP mode ([email] non-null): the user typed their email on the
///    forgot-password screen, we emailed a 6-digit code; here they enter the
///    code + a new password (no link, no leaving the app).
///  - Session mode ([email] null): legacy path where a recovery deep-link
///    already established a session and we just set the new password.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.email});

  final String? email;

  bool get isOtpMode => email != null && email!.isNotEmpty;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _resending = false;

  // Resend throttle: a code was just emailed when we arrived, so start a
  // 60s cooldown before the user can request another (matches Supabase's
  // smtp_max_frequency; the server also caps at 3 reset emails/hour).
  static const _resendCooldownSeconds = 60;
  int _resendIn = _resendCooldownSeconds;
  Timer? _cooldownTimer;

  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _saving = false;
  bool _success = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slide = Tween<double>(begin: 16, end: 0).animate(
      CurvedAnimation(parent: _entrance, curve: Curves.easeOut),
    );
    if (widget.isOtpMode) _startCooldown();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _resendIn = _resendCooldownSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _resendIn -= 1);
      if (_resendIn <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _entrance.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 8) return 'Must be at least 8 characters';
    if (!RegExp(r'[A-Z]').hasMatch(value)) return 'Add an uppercase letter';
    if (!RegExp(r'[0-9]').hasMatch(value)) return 'Add a number';
    return null;
  }

  String? _validateConfirm(String? value) {
    if (value != _passwordController.text) return 'Passwords do not match';
    return null;
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      if (widget.isOtpMode) {
        // Verify the emailed 6-digit code, then set the new password.
        final result = await AuthService.resetPasswordWithOtp(
          email: widget.email!,
          token: _codeController.text,
          newPassword: _passwordController.text,
        );
        if (!mounted) return;
        if (result.isSuccess) {
          setState(() {
            _saving = false;
            _success = true;
          });
        } else {
          setState(() {
            _saving = false;
            _error = result.errorMessage ?? 'Could not reset your password.';
          });
        }
        return;
      }
      // Legacy session mode (recovery deep-link already signed us in).
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _passwordController.text),
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _success = true;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not update your password. Try again.';
      });
    }
  }

  Future<void> _resendCode() async {
    if (_resending || _resendIn > 0 || widget.email == null) return;
    setState(() => _resending = true);
    final result = await AuthService.sendPasswordReset(widget.email!);
    if (!mounted) return;
    setState(() => _resending = false);
    if (result.isSuccess) {
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New code sent to your email.')),
      );
    } else {
      // Surfaces the server rate-limit message (max 3 reset emails/hour).
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errorMessage ?? 'Could not resend.')),
      );
    }
  }

  Future<void> _continueAfterSuccess() async {
    if (!mounted) return;
    // OTP mode signs the user out, so send them to login to sign in with the
    // new password. Session mode is still signed in → home.
    context.goNamed(widget.isOtpMode ? 'login' : 'home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: SingleChildScrollView(
        child: Column(
          children: [
            AuthHero(
              title: 'Reset password',
              subtitle: 'Choose a new password for your account.',
              tagline: 'Almost there',
              onBack: () => context.canPop()
                  ? context.pop()
                  : context.goNamed('login'),
            ),
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
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: _success ? _buildSuccess() : _buildForm(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Card(
        elevation: 0,
        color: context.palette.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.isOtpMode) ...[
                Text(
                  'We emailed a 6-digit code to ${widget.email}. Enter it below '
                  'with your new password.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '6-DIGIT CODE',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  validator: (v) => (v == null || v.trim().length < 6)
                      ? 'Enter the 6-digit code'
                      : null,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 8,
                  ),
                  decoration: _passwordDecoration(
                    hint: '------',
                    obscure: false,
                    onToggle: () {},
                  ).copyWith(
                    counterText: '',
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(left: 14, right: 10),
                      child: Icon(Icons.pin_outlined,
                          color: AppColors.primaryBlue, size: 20),
                    ),
                    suffixIcon: null,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: () => showSupportSheet(context,
                          topic: 'Didn\'t get my reset code'),
                      icon: const Icon(Icons.help_outline,
                          size: 15, color: AppColors.textMuted),
                      label: Text('No code? Get help',
                          style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w600)),
                    ),
                    TextButton(
                      onPressed:
                          (_resending || _resendIn > 0) ? null : _resendCode,
                      child: Text(
                          _resending
                              ? 'Sending…'
                              : _resendIn > 0
                                  ? 'Resend in ${_resendIn}s'
                                  : 'Resend code',
                          style: AppTextStyles.labelMedium.copyWith(
                              color: _resendIn > 0
                                  ? AppColors.textMuted
                                  : AppColors.primaryBlue)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              Text(
                'NEW PASSWORD',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                keyboardType: TextInputType.text,
                enableSuggestions: false,
                autocorrect: false,
                validator: _validatePassword,
                style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                decoration: _passwordDecoration(
                  hint: 'At least 8 chars, 1 upper, 1 number',
                  obscure: _obscurePassword,
                  onToggle: () => setState(
                    () => _obscurePassword = !_obscurePassword,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'CONFIRM PASSWORD',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _confirmController,
                obscureText: _obscureConfirm,
                keyboardType: TextInputType.text,
                enableSuggestions: false,
                autocorrect: false,
                validator: _validateConfirm,
                style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                decoration: _passwordDecoration(
                  hint: 'Type it again',
                  obscure: _obscureConfirm,
                  onToggle: () => setState(
                    () => _obscureConfirm = !_obscureConfirm,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                _ErrorBanner(message: _error!),
              ],
              const SizedBox(height: 24),
              _GradientButton(
                label: _saving ? 'Saving...' : 'Save new password',
                busy: _saving,
                onTap: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess() {
    return Card(
      elevation: 0,
      color: context.palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.successGreen.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: AppColors.successGreen,
                size: 40,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Password updated',
              style: AppTextStyles.headlineMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'You can use your new password the next time you sign in.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            _GradientButton(
              label: widget.isOtpMode ? 'Sign in' : 'Continue',
              busy: false,
              onTap: _continueAfterSuccess,
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _passwordDecoration({
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: const Padding(
        padding: EdgeInsets.only(left: 14, right: 10),
        child: Icon(Icons.lock_outline, color: AppColors.primaryBlue, size: 20),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      suffixIcon: IconButton(
        icon: Icon(
          obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          color: AppColors.textMuted,
          size: 20,
        ),
        onPressed: onToggle,
      ),
      filled: true,
      fillColor: context.palette.inputFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:  BorderSide(color: AppColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:  BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.red, width: 1.5),
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
      opacity: onTap == null && !busy ? 0.6 : 1,
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
