import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Shown immediately after a successful signup. Supabase sends the
/// confirmation code itself — this screen surfaces that, lets the user
/// resend, opens the system email app, and verifies the 6-digit code.
/// It also listens for the signed-in auth event so it can advance the
/// moment a user taps the email link on the same device (older flow).
class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key, required this.email});

  final String email;

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entrance;
  late final AnimationController _pulse;
  late final Animation<double> _fade;
  late final Animation<double> _slide;
  late final Animation<double> _iconScale;

  StreamSubscription<AuthState>? _authSub;
  Timer? _cooldownTimer;
  bool _resending = false;
  bool _checking = false;
  int _cooldown = 0;
  int _resendCount = 0;
  // Rate-limit knobs: cooldown grows after each resend (30, 60, 120
  // ...) and we stop accepting new resends after [_resendCap]. This
  // protects Supabase's SMTP quota AND the user's inbox from people
  // hammering the button while waiting on a slow email.
  static const _baseCooldown = 60;
  static const _resendCap = 5;
  String? _info;
  String? _error;
  final _otpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slide = Tween<double>(begin: 16, end: 0).animate(
      CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic),
    );
    _iconScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _entrance, curve: Curves.elasticOut),
    );

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _authSub =
        Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      // Supabase fires signedIn when the user taps the magic link
      // from the confirmation email on the same device. At that point
      // emailConfirmedAt is populated — advance to profile setup.
      final user = state.session?.user;
      if (user != null && user.emailConfirmedAt != null && mounted) {
        context.goNamed('profile_setup');
      }
    });
  }

  @override
  void dispose() {
    _entrance.dispose();
    _pulse.dispose();
    _authSub?.cancel();
    _cooldownTimer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  String _maskedEmail() {
    final raw = widget.email.trim();
    final at = raw.indexOf('@');
    if (at < 2) return raw;
    final local = raw.substring(0, at);
    final domain = raw.substring(at);
    if (local.length <= 2) return '${local[0]}•$domain';
    final first = local[0];
    final last = local[local.length - 1];
    final dots = '•' * (local.length - 2).clamp(2, 6);
    return '$first$dots$last$domain';
  }

  Future<void> _openEmailApp() async {
    HapticFeedback.selectionClick();
    // We want the user to land on their INBOX (where the new
    // verification email is sitting), not on the compose / account
    // picker screen. The right tool varies by platform:
    //
    //   Android  →  intent with category=APP_EMAIL pops the
    //               default email app's inbox.
    //   iOS      →  message:// opens Apple Mail at the inbox.
    //               Fall back to googlegmail:// for Gmail-only
    //               users who don't have Mail set up.
    //
    // Each candidate is tried in order; the first one that
    // canLaunchUrl wins. If none work we drop a small instruction
    // line so the user knows to switch apps manually.
    final candidates = <String>[
      if (Platform.isAndroid)
        'intent://#Intent;action=android.intent.action.MAIN;'
            'category=android.intent.category.APP_EMAIL;end',
      if (Platform.isIOS) 'message://',
      // Both platforms: try the Gmail app directly. Works if it's
      // installed even when no default mail app is registered.
      'googlegmail://',
    ];

    for (final raw in candidates) {
      final uri = Uri.parse(raw);
      try {
        final canLaunch = await canLaunchUrl(uri);
        if (!canLaunch) continue;
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok) return;
      } catch (_) {
        // Try the next candidate.
      }
    }

    if (mounted) {
      setState(() => _info =
          'Couldn\'t open your inbox automatically — open your email '
          'app and look for the code if dont see it try sign up or in with google.');
    }
  }

  Future<void> _resend() async {
    if (_resending || _cooldown > 0) return;
    if (_resendCount >= _resendCap) {
      setState(() => _error =
          'You\'ve resent the code a few times already. Check your '
          'Spam folder, or use Change email to try a different address.');
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _resending = true;
      _info = null;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: widget.email,
      );
      if (!mounted) return;
      // Backoff: 60s the first time, then double each subsequent
      // resend up to 5 minutes. Keeps casual retries fast but
      // discourages anyone pounding the button on a flaky network.
      _resendCount += 1;
      final next = (_baseCooldown * (1 << (_resendCount - 1))).clamp(60, 300);
      setState(() {
        _resending = false;
        _info = 'Confirmation email sent again.';
        _cooldown = next;
      });
      _startCooldown();
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _resending = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _resending = false;
        _error = 'Could not resend the email. Try again in a moment.\n or try sign in or up with google';
      });
    }
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _cooldown -= 1);
      if (_cooldown <= 0) timer.cancel();
    });
  }

  void _changeEmail() {
    HapticFeedback.selectionClick();
    context.goNamed('signup');
  }

  Future<void> _verifyCode() async {
    if (_checking) return;
    final token = _otpController.text.trim();
    // Supabase projects can be configured with 6, 7, or 8-digit OTPs
    // (dashboard: Authentication -> Providers -> Email -> OTP Length).
    // Accept the full 4-10 range so the app doesn't truncate a longer
    // code into "invalid token" errors.
    if (token.length < 4) {
      setState(() => _error = 'Enter the code from your email.');
      return;
    }
    setState(() {
      _checking = true;
      _info = null;
      _error = null;
    });
    final result = await AuthService.verifySignupOtp(
      email: widget.email,
      token: token,
    );
    if (!mounted) return;
    if (result.isSuccess) {
      HapticFeedback.mediumImpact();
      context.goNamed('profile_setup');
      return;
    }
    setState(() {
      _checking = false;
      _error = result.errorMessage ?? 'Could not verify the code.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGrey,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: AnimatedBuilder(
            animation: _entrance,
            builder: (context, child) => Opacity(
              opacity: _fade.value,
              child: Transform.translate(
                offset: Offset(0, _slide.value),
                child: child,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopBar(onBack: () => context.canPop()
                    ? context.pop()
                    : context.goNamed('signup')),
                const SizedBox(height: 8),
                _SuccessRing(scale: _iconScale, pulse: _pulse),
                const SizedBox(height: 28),
                Text(
                  'Verify your email',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.displayMedium.copyWith(
                    color: AppColors.darkNavy,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'We sent a 6-digit verification code to your email '
                    'address.\n if you dont recieve the code check your spam folder \n if it persist try sign up or in by Google',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: const Color.fromRGBO(26, 26, 46, 0.65),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color:
                            AppColors.primaryBlue.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Text(
                      _maskedEmail(),
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.darkNavy,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                _OtpField(
                  controller: _otpController,
                  onSubmit: _verifyCode,
                ),
                if (_info != null) ...[
                  const SizedBox(height: 14),
                  _InfoBanner(message: _info!),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  _ErrorBanner(message: _error!),
                ],
                const SizedBox(height: 24),
                _PrimaryButton(
                  label: _checking ? 'Verifying…' : 'Verify code',
                  busy: _checking,
                  onTap: _checking ? null : _verifyCode,
                ),
                const SizedBox(height: 12),
                _SecondaryButton(
                  icon: Icons.mark_email_unread_outlined,
                  label: 'Open Email App',
                  onTap: _openEmailApp,
                ),
                const SizedBox(height: 18),
                Center(
                  child: TextButton(
                    onPressed:
                        (_cooldown > 0 || _resending) ? null : _resend,
                    child: Text(
                      _cooldown > 0
                          ? 'Resend in $_cooldown s'
                          : (_resending ? 'Sending…' : 'Resend email'),
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: (_cooldown > 0 || _resending)
                            ? const Color.fromRGBO(26, 26, 46, 0.45)
                            : AppColors.primaryBlue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Center(
                  child: TextButton(
                    onPressed: _changeEmail,
                    child: Text(
                      'Change email',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: const Color.fromRGBO(26, 26, 46, 0.55),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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

// =============================================================================
// Sub-widgets
// =============================================================================

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onBack,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color.fromRGBO(26, 26, 46, 0.08),
                ),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                size: 14,
                color: AppColors.darkNavy,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SuccessRing extends StatelessWidget {
  const _SuccessRing({required this.scale, required this.pulse});
  final Animation<double> scale;
  final AnimationController pulse;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: Listenable.merge([scale, pulse]),
        builder: (context, _) {
          final s = scale.value.clamp(0.0, 1.0);
          // Two halo rings that grow and fade as the controller cycles —
          // gives the icon a calm "we're listening" pulse.
          final t = pulse.value;
          return SizedBox(
            width: 180,
            height: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _Halo(progress: t),
                _Halo(progress: (t + 0.5) % 1.0),
                Transform.scale(
                  scale: s,
                  child: Container(
                    width: 108,
                    height: 108,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryBlue
                              .withValues(alpha: 0.36),
                          blurRadius: 32,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.mark_email_read_outlined,
                      color: AppColors.white,
                      size: 52,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Halo extends StatelessWidget {
  const _Halo({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    // progress is 0..1. As it grows the ring expands and fades.
    final size = 108 + (progress * 72);
    final opacity = (1 - progress).clamp(0.0, 1.0) * 0.5;
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.primaryBlue.withValues(alpha: opacity),
            width: 2,
          ),
        ),
      ),
    );
  }
}

class _OtpField extends StatelessWidget {
  const _OtpField({required this.controller, required this.onSubmit});

  final TextEditingController controller;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color.fromRGBO(26, 26, 46, 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(6),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        autofocus: true,
        // Allow up to 10 digits — Supabase projects can be configured
        // for 6, 7, or 8-digit OTPs (and that's been the cause of
        // mysterious "token expired" errors when the field truncated
        // an 8-digit code to 6).
        maxLength: 10,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: (_) => onSubmit(),
        style: AppTextStyles.displayMedium.copyWith(
          fontSize: 28,
          letterSpacing: 12,
          fontWeight: FontWeight.w800,
          color: AppColors.darkNavy,
        ),
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          hintText: '••••••',
          hintStyle: AppTextStyles.displayMedium.copyWith(
            color: const Color.fromRGBO(26, 26, 46, 0.18),
            letterSpacing: 12,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
          counterText: '',
          filled: true,
          fillColor: AppColors.lightGrey,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(
              color: AppColors.primaryBlue,
              width: 1.6,
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
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
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withValues(alpha: 0.30),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              alignment: Alignment.center,
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: AppColors.white,
                        strokeWidth: 2.4,
                      ),
                    )
                  : Text(
                      label,
                      style: AppTextStyles.buttonText.copyWith(
                        fontSize: 15.5,
                        letterSpacing: 0.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppColors.primaryBlue.withValues(alpha: 0.30),
              width: 1.4,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.primaryBlue, size: 20),
              const SizedBox(width: 10),
              Text(
                label,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.successGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.successGreen.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline,
            color: AppColors.successGreen,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.successGreen,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
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
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.error_outline, color: AppColors.red, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.red,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
