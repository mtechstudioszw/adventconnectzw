import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/two_step_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/screen_shell.dart';
import '../auth/two_step_challenge_screen.dart';

/// Settings → Account → Two-step verification.
///
/// Off → explain, then "Set up". Setting up shows a QR code (and the key
/// as text, for an app on the same phone that cannot scan its own screen),
/// then asks for the first code to prove the app was set up right. Only a
/// confirmed code switches it on — a half-finished setup protects nothing
/// and locks nobody out.
class TwoStepSetupScreen extends StatefulWidget {
  const TwoStepSetupScreen({super.key});

  @override
  State<TwoStepSetupScreen> createState() => _TwoStepSetupScreenState();
}

enum _Stage { loading, off, scanning, on }

class _TwoStepSetupScreenState extends State<TwoStepSetupScreen> {
  _Stage _stage = _Stage.loading;
  TOTPEnrollment? _enrol;
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final factors = await TwoStepService.verifiedFactors();
      if (!mounted) return;
      setState(() => _stage = factors.isEmpty ? _Stage.off : _Stage.on);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = TwoStepService.isOn ? _Stage.on : _Stage.off;
        _error = TwoStepService.friendlyError(e);
      });
    }
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final enrol = await TwoStepService.startSetup();
      if (!mounted) return;
      setState(() {
        _enrol = enrol;
        _stage = _Stage.scanning;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = TwoStepService.friendlyError(e);
      });
    }
  }

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await TwoStepService.finishSetup(_code.text);
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
    setState(() {
      _busy = false;
      _stage = _Stage.on;
      _enrol = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Two-step verification is on.')),
    );
  }

  Future<void> _turnOff() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Turn off two-step?'),
        content: const Text(
          'Anyone who learns your password will be able to sign in to '
          'your account without your phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Keep it on'),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Turn off',
                style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await TwoStepService.turnOff();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (err == null) {
        _stage = _Stage.off;
      } else {
        _error = err;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const ScreenHero(
              title: 'Two-step verification',
              tagline: 'A code from your phone, as well as your password',
              fallbackRoute: 'settings',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: switch (_stage) {
                _Stage.loading => const Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                _Stage.off => _offView(),
                _Stage.scanning => _scanView(),
                _Stage.on => _onView(),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required List<Widget> children}) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(18),
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
          children: children,
        ),
      );

  Widget _errorText() => _error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text(
            _error!,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.red),
          ),
        );

  Widget _step(String n, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.primaryBlue,
                shape: BoxShape.circle,
              ),
              child: Text(n,
                  style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.white, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: AppTextStyles.bodyMedium)),
          ],
        ),
      );

  Widget _offView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(children: [
          const Icon(Icons.shield_outlined,
              color: AppColors.primaryBlue, size: 32),
          const SizedBox(height: 12),
          Text('Protect your account', style: AppTextStyles.titleMedium),
          const SizedBox(height: 8),
          Text(
            'When you sign in on a new phone, we\'ll ask for a 6-digit code '
            'from an authenticator app as well as your password. Someone who '
            'steals or guesses your password still can\'t get in.',
            style: AppTextStyles.bodyMedium
                .copyWith(color: context.palette.textMuted),
          ),
          const SizedBox(height: 14),
          Text(
            'You need a free authenticator app such as Google Authenticator '
            'or Microsoft Authenticator.',
            style: AppTextStyles.bodySmall
                .copyWith(color: context.palette.textMuted),
          ),
          _errorText(),
        ]),
        const SizedBox(height: 20),
        TwoStepButton(
          label: 'Set up',
          busy: _busy,
          onTap: _busy ? null : _start,
        ),
      ],
    );
  }

  Widget _scanView() {
    final enrol = _enrol;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(children: [
          _step('1', 'Open your authenticator app and add a new account.'),
          _step('2', 'Scan this code — or, on this same phone, copy the key '
              'below and paste it in the app.'),
          const SizedBox(height: 6),
          if (enrol != null) ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  // White always: a QR on a dark card does not scan.
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: QrImageView(
                  data: enrol.uri,
                  version: QrVersions.auto,
                  size: 190,
                  backgroundColor: AppColors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Material(
              color: context.palette.inputFill,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: enrol.secret));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Key copied')),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          enrol.secret,
                          style: AppTextStyles.bodySmall.copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      const Icon(Icons.copy_rounded,
                          size: 18, color: AppColors.primaryBlue),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _step('3', 'Type the 6-digit code the app shows.'),
          const SizedBox(height: 4),
          TwoStepCodeField(
            controller: _code,
            enabled: !_busy,
            onCompleted: _confirm,
          ),
          _errorText(),
        ]),
        const SizedBox(height: 20),
        TwoStepButton(
          label: _busy ? 'Checking…' : 'Turn on',
          busy: _busy,
          onTap: _busy ? null : _confirm,
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                    _stage = _Stage.off;
                    _enrol = null;
                    _error = null;
                  }),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _onView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(children: [
          Row(
            children: [
              const Icon(Icons.verified_user_rounded,
                  color: AppColors.successGreen, size: 28),
              const SizedBox(width: 10),
              Text('Two-step is on', style: AppTextStyles.titleMedium),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Signing in on a new phone needs your password and a code from '
            'your authenticator app. Keep that app on your phone — if you '
            'lose it, contact support to get back in.',
            style: AppTextStyles.bodyMedium
                .copyWith(color: context.palette.textMuted),
          ),
          _errorText(),
        ]),
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: _busy ? null : _turnOff,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.red,
            side: const BorderSide(color: AppColors.red),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text('Turn off two-step'),
        ),
      ],
    );
  }
}
