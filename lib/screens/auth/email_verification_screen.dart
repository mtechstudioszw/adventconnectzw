import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import 'widgets/auth_shell.dart';

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
    with WidgetsBindingObserver {
  // No entrance / pulse controllers: AuthShell owns the staggered rise
  // and the ambient motion for every screen in this flow, so each one
  // no longer invents its own fade and its own pulsing ring.
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

  // True while a clipboard-sourced code is being auto-verified, so we can
  // show a tiny "code detected" hint instead of a silent jump.
  bool _autoFilled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Auto-verify the instant a full 6-digit code is entered or pasted —
    // no "Verify" tap needed (WhatsApp-style).
    _otpController.addListener(_onOtpChanged);
    // If the user already copied the code (e.g. from a notification) before
    // landing here, grab it on first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryClipboardAutofill());
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
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _cooldownTimer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Coming back from the email app — the user has likely just copied the
    // code. Pull it straight off the clipboard and verify (WhatsApp-style).
    if (state == AppLifecycleState.resumed) _tryClipboardAutofill();
  }

  /// Auto-verify as soon as a full 6-digit code is present.
  void _onOtpChanged() {
    if (_checking) return;
    if (_otpController.text.length == 6) _verifyCode();
  }

  /// If a 6-digit code is sitting on the clipboard and the field is empty,
  /// fill it in (which triggers [_onOtpChanged] -> auto-verify).
  Future<void> _tryClipboardAutofill() async {
    if (!mounted || _checking || _otpController.text.isNotEmpty) return;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      final match = RegExp(r'(?<!\d)(\d{6})(?!\d)').firstMatch(text);
      if (match == null) return;
      if (!mounted || _otpController.text.isNotEmpty) return;
      _autoFilled = true;
      _otpController.text = match.group(1)!;
    } catch (_) {
      // Clipboard not readable (permissions / empty) — ignore silently.
    }
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
      setState(() => _error =
          'Couldn\'t open your email app automatically. Open your email app manually and look for the verification code. Check your spam folder if you don\'t see it.');
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
      // Server-side throttle (patch_125): 3 resends per hour per email, then
      // a 1-hour lockout. Persists across app restart/reinstall (the old
      // in-memory cap reset every launch). Fail-open on a network error so a
      // flaky connection never blocks a legitimate user.
      try {
        final verdict = await Supabase.instance.client.rpc(
          'register_otp_resend',
          params: {'p_email': widget.email},
        );
        if (verdict is Map && verdict['allowed'] == false) {
          final retry =
              (verdict['retry_after_seconds'] as num?)?.toInt() ?? 3600;
          final mins = (retry / 60).ceil();
          if (!mounted) return;
          setState(() {
            _resending = false;
            _cooldown = retry;
            _error =
                'Too many code requests. Please try again in about $mins '
                'minute${mins == 1 ? '' : 's'}, or use Change email to try a '
                'different address.';
          });
          _startCooldown();
          return;
        }
      } catch (_) {
        // Throttle RPC unreachable — proceed (fail-open).
      }
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
    // On AuthShell like the rest of the flow, so the ambient field from
    // the intro keeps running and the heading enters on the same stagger
    // as forgot-password and reset. The bespoke top bar, entrance
    // controller and pulsing success ring this used to own are all
    // furniture the shell now provides once.
    return AuthShell(
      eyebrow: 'One last step',
      title: 'Check your inbox',
      subtitle: 'We sent a 6-digit code to the address below. If it isn\'t '
          'there in a minute, check your spam folder.',
      icon: Icons.mark_email_read_outlined,
      onBack: () =>
          context.canPop() ? context.pop() : context.goNamed('signup'),
      footer: _buildFooter(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                  color: AppColors.primaryBlue.withValues(alpha: 0.18),
                ),
              ),
              child: Text(
                _maskedEmail(),
                style: AppTextStyles.bodyMedium.copyWith(
                  color: context.palette.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(height: 26),
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
            label: _checking
                ? (_autoFilled ? 'Code detected — verifying…' : 'Verifying…')
                : 'Verify code',
            busy: _checking,
            onTap: _checking ? null : _verifyCode,
          ),
          const SizedBox(height: 12),
          _SecondaryButton(
            icon: Icons.mark_email_unread_outlined,
            label: 'Open email app',
            onTap: _openEmailApp,
          ),
        ],
      ),
    );
  }

  /// Resend + change-email, pinned to the bottom. These are escape
  /// hatches, not part of the task, so they belong out of the column the
  /// eye reads top-to-bottom.
  Widget _buildFooter() {
    final resendDisabled = _cooldown > 0 || _resending;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: resendDisabled ? null : _resend,
          child: Text(
            _cooldown > 0
                ? 'Resend in $_cooldown s'
                : (_resending ? 'Sending…' : 'Resend code'),
            style: AppTextStyles.bodyMedium.copyWith(
              color: resendDisabled
                  ? context.palette.textMuted
                  : AppColors.primaryBlue,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        TextButton(
          onPressed: _changeEmail,
          child: Text(
            'Use a different email',
            style: AppTextStyles.bodySmall.copyWith(
              color: context.palette.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

}

// =============================================================================
// Sub-widgets
// =============================================================================

class _OtpField extends StatelessWidget {
  const _OtpField({required this.controller, required this.onSubmit});

  final TextEditingController controller;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.divider,
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
        // Lets the OS offer the code as a one-tap suggestion above the
        // keyboard (iOS surfaces one-time codes; Android offers clipboard).
        autofillHints: const [AutofillHints.oneTimeCode],
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
            color: AppColors.divider,
            letterSpacing: 12,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
          counterText: '',
          filled: true,
          fillColor: context.palette.cardMuted,
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
                  // TODO(dark-mode): const CircularProgressIndicator — sits on primaryGradient.
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
      color: context.palette.card,
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
