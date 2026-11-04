import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth_service.dart';
import '../../services/phone_verification_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import 'two_step_challenge_screen.dart' show TwoStepButton, TwoStepCodeField;
import 'widgets/auth_shell.dart';

/// "Verify your phone number" — shown to a new account when the owner has
/// switched phone verification on (see PhoneVerificationService). Two
/// steps: number → SMS code. No back arrow; the way out is signing out.
class VerifyPhoneScreen extends StatefulWidget {
  const VerifyPhoneScreen({super.key});

  @override
  State<VerifyPhoneScreen> createState() => _VerifyPhoneScreenState();
}

class _VerifyPhoneScreenState extends State<VerifyPhoneScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String? _sentTo;
  bool _busy = false;
  String? _error;

  /// Resend wait — matches Supabase's own 60s cooldown, so the button never
  /// offers a resend the server would refuse.
  int _wait = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startWait() {
    _timer?.cancel();
    setState(() => _wait = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _wait--);
      if (_wait <= 0) t.cancel();
    });
  }

  Future<void> _send() async {
    final e164 = PhoneVerificationService.normalise(_phone.text);
    if (e164 == null) {
      setState(() => _error = 'Enter a valid phone number, e.g. 077 123 4567 '
          'or +27 82 123 4567.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await PhoneVerificationService.sendCode(e164);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
      if (err == null) _sentTo = e164;
    });
    if (err == null) _startWait();
  }

  Future<void> _confirm() async {
    final to = _sentTo;
    if (to == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await PhoneVerificationService.confirm(to, _code.text);
    if (!mounted) return;
    if (err != null) {
      _code.clear();
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    HapticFeedback.mediumImpact();
    if (context.canPop()) {
      context.pop(true);
    } else {
      context.goNamed('home');
    }
  }

  Future<void> _signOut() async {
    await AuthService.signOut();
    if (!mounted) return;
    context.goNamed('login');
  }

  @override
  Widget build(BuildContext context) {
    final sent = _sentTo != null;
    return PopScope(
      canPop: false,
      child: AuthShell(
        eyebrow: 'Required for every account',
        title: sent ? 'Enter the\nSMS code' : 'Verify your\nphone',
        subtitle: sent
            ? 'We sent a 6-digit code to $_sentTo.'
            : 'To keep fake accounts out, every member now confirms a phone '
                'number. Each number can verify one account, and we never '
                'show it to anyone. Until you verify, the app and its '
                'notifications are paused.',
        icon: Icons.phone_iphone_rounded,
        footer: TextButton(
          onPressed: _busy ? null : _signOut,
          child: Text(
            'Sign out',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.primaryBlue,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!sent)
              TextField(
                controller: _phone,
                enabled: !_busy,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                onSubmitted: (_) => _send(),
                style: AppTextStyles.bodyLarge.copyWith(fontSize: 16),
                decoration: InputDecoration(
                  hintText: '077 123 4567',
                  prefixIcon: const Icon(Icons.phone_outlined,
                      color: AppColors.primaryBlue),
                  filled: true,
                  fillColor: context.palette.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: AppColors.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: AppColors.divider),
                  ),
                ),
              )
            else
              TwoStepCodeField(
                controller: _code,
                enabled: !_busy,
                onCompleted: _confirm,
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
              label: sent ? 'Verify' : 'Send code',
              busy: _busy,
              onTap: _busy ? null : (sent ? _confirm : _send),
            ),
            if (sent)
              TextButton(
                onPressed: _busy || _wait > 0
                    ? null
                    : () => setState(() {
                          _sentTo = null;
                          _code.clear();
                          _error = null;
                        }),
                child: Text(_wait > 0
                    ? 'Change number or resend in ${_wait}s'
                    : 'Change number or resend'),
              ),
          ],
        ),
      ),
    );
  }
}
