import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import 'widgets/auth_hero.dart';

/// Dedicated screen for requesting a password-reset email. Replaces
/// the inline dialog that used to live inside login. Once the email
/// goes out we show a confirmation state — the actual password change
/// happens in reset_password_screen after the user opens the link.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  bool _sending = false;
  bool _sent = false;
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
  }

  @override
  void dispose() {
    _entrance.dispose();
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
      setState(() => _sent = true);
    } else {
      setState(() => _error = result.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: SingleChildScrollView(
        child: Column(
          children: [
            AuthHero(
              title: 'Forgot password?',
              subtitle: 'Enter your email and we\'ll send you a reset link.\n if dosent work contact us at +263 778092494',
              tagline: 'Account recovery',
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
                child: _sent ? _buildSent() : _buildForm(),
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
                    color: const Color.fromRGBO(26, 26, 46, 0.65),
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
                      borderSide: const BorderSide(
                        color: Color.fromRGBO(26, 26, 46, 0.06),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color.fromRGBO(26, 26, 46, 0.06),
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
                    color: const Color.fromRGBO(26, 26, 46, 0.55),
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
            label: _sending ? 'Sending...' : 'Send reset link',
            busy: _sending,
            onTap: _sending ? null : _send,
          ),
          const SizedBox(height: 18),
          Center(
            child: TextButton(
              onPressed: () => context.goNamed('login'),
              child: Text(
                'Back to sign in',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSent() {
    return Container(
      padding: const EdgeInsets.all(28),
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
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.successGreen.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.mark_email_read_outlined,
              color: AppColors.successGreen,
              size: 38,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Check your inbox',
            textAlign: TextAlign.center,
            style: AppTextStyles.headlineMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'We sent a reset link to',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.65),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _emailController.text.trim(),
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.primaryBlue,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Tap the link in that email to choose a new password. The link expires in 1 hour.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.6),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          _GradientButton(
            label: 'Back to sign in',
            busy: false,
            onTap: () => context.goNamed('login'),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => setState(() {
              _sent = false;
              _error = null;
            }),
            child: Text(
              'Use a different email',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
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
