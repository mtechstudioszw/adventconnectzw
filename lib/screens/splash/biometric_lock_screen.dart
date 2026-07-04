import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// WhatsApp-style biometric lock.
///
/// When a user with biometric unlock enabled either (a) cold-starts the
/// app or (b) resumes after the background threshold, they land here
/// instead of going straight to home. The OS biometric prompt fires
/// automatically; on success we navigate into the app. On cancel /
/// failure we DON'T sign the user out — we just leave them on this
/// screen with a Try Again CTA. The session is still valid; only the
/// in-app UI is gated.
///
/// Sign-out remains available as a deliberate, second-tap action so
/// the user can still escape if they really want to switch accounts.
///
/// The badge is a live status display, not a static icon:
/// * idle — calm sonar pulse;
/// * sensing — pulse tightens + speeds up while the OS prompt is up;
/// * success — pulse stops, a gold ring draws around the badge, the
///   fingerprint morphs into a check, THEN we navigate;
/// * failure — the badge shakes and flashes toward red, then settles
///   back to idle.
class BiometricLockScreen extends StatefulWidget {
  const BiometricLockScreen({super.key, this.autoPrompt = true});

  /// Whether to fire the biometric prompt as soon as the screen mounts.
  /// True for cold-start + resume entries (the common case); false if
  /// some other flow needs to land here without an immediate prompt.
  final bool autoPrompt;

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

enum _LockStage { idle, sensing, success, failure }

class _BiometricLockScreenState extends State<BiometricLockScreen>
    with TickerProviderStateMixin {
  _LockStage _stage = _LockStage.idle;
  late final AnimationController _pulse;
  late final AnimationController _success;
  late final AnimationController _shake;

  bool get _busy => _stage == _LockStage.sensing || _stage == _LockStage.success;

  @override
  void initState() {
    super.initState();
    // Continuous "sonar" pulse behind the fingerprint badge so the lock
    // screen feels alive while it waits for the biometric prompt.
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _success = AnimationController(
      vsync: this,
      duration: AppMotion.celebrate,
    );
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed &&
            mounted &&
            _stage == _LockStage.failure) {
          setState(() => _stage = _LockStage.idle);
        }
      });
    if (widget.autoPrompt) {
      // Defer one frame so the lock screen paints before the system
      // dialog appears — otherwise the user sees a white flash behind
      // the prompt the first time around.
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryUnlock());
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _success.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _setStage(_LockStage stage) {
    if (!mounted || _stage == stage) return;
    setState(() => _stage = stage);
    // The sonar tightens while the sensor is actually listening.
    _pulse.duration = Duration(milliseconds: stage == _LockStage.sensing ? 1100 : 2000);
    if (stage != _LockStage.success) _pulse.repeat();
  }

  Future<void> _tryUnlock() async {
    if (_busy) return;
    _setStage(_LockStage.sensing);
    final ok = await BiometricService.authenticate(
      reason: 'Unlock Advent Connect ZW',
    );
    if (!mounted) return;
    if (ok) {
      // Route to home (or profile setup if they never finished
      // onboarding). The profile-setup check is a NETWORK call — run it
      // in PARALLEL with the success choreography instead of before it,
      // so unlock takes ~600ms, not network + 600ms. Timeboxed and
      // defaulting to home so a slow connection never stalls the door.
      // Timeboxed SHORTER than the ~740ms success animation so the network
      // check resolves in parallel and is never on the critical path — a
      // returning (biometric) user has completed setup, so we default to
      // home on a slow connection instead of stalling the door ~2-3s.
      final completedFuture = AuthService.hasCompletedProfileSetup()
          .timeout(const Duration(milliseconds: 700), onTimeout: () => true)
          .catchError((_) => true);
      // Celebrate while the check runs — gold ring draws in, fingerprint
      // becomes a check — so unlocking feels like a moment, not a cut.
      _setStage(_LockStage.success);
      _pulse.stop();
      HapticFeedback.mediumImpact();
      if (AppMotion.enabled(context)) {
        await _success.forward();
        // Let the check breathe for a beat.
        await Future<void>.delayed(const Duration(milliseconds: 140));
      }
      final completed = await completedFuture;
      if (!mounted) return;
      if (!completed) {
        context.goNamed('profile_setup');
      } else {
        context.goNamed('home');
      }
      return;
    }
    // Cancel / not recognised: shake it off, stay signed in, offer Try
    // again. The session is untouched.
    _setStage(_LockStage.failure);
    HapticFeedback.heavyImpact();
    if (AppMotion.enabled(context)) {
      _shake.forward(from: 0);
    } else {
      _setStage(_LockStage.idle);
    }
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.sheet,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: Text('Sign out?', style: AppTextStyles.headlineSmall),
        content: Text(
          'You\'ll need to sign in again to access the community.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: AppTextStyles.labelMedium
                  .copyWith(color: AppColors.text),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: Text('Sign out', style: AppTextStyles.labelLarge),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await AuthService.signOut();
    if (!mounted) return;
    context.goNamed('login');
  }

  String get _subtitle {
    switch (_stage) {
      case _LockStage.idle:
        return 'Use your fingerprint or face to unlock the app.';
      case _LockStage.sensing:
        return 'Sensing… touch the fingerprint sensor.';
      case _LockStage.success:
        return 'Welcome back!';
      case _LockStage.failure:
        return 'Didn’t work — give it another try.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(),
              _buildBadge(context),
              const SizedBox(height: 28),
              Text(
                'Advent Connect ZW is locked',
                textAlign: TextAlign.center,
                style: AppTextStyles.headlineMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: AppMotion.maybe(context, AppMotion.quick),
                child: Text(
                  _subtitle,
                  key: ValueKey(_stage),
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: _stage == _LockStage.failure
                        ? AppColors.red
                        : context.palette.textMuted,
                    height: 1.5,
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _tryUnlock,
                  icon: _stage == _LockStage.sensing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: AppColors.white,
                            strokeWidth: 2.2,
                          ),
                        )
                      : const Icon(Icons.fingerprint, size: 20),
                  label: Text(
                    _stage == _LockStage.sensing ? 'Waiting…' : 'Try again',
                    style: AppTextStyles.labelLarge,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: AppColors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _busy ? null : _signOut,
                child: Text(
                  'Sign out',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: context.palette.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(BuildContext context) {
    final animate = AppMotion.enabled(context);
    return AnimatedBuilder(
      animation: Listenable.merge([_pulse, _success, _shake]),
      builder: (context, child) {
        final t = _pulse.value; // 0 → 1, repeating
        final successT = Curves.easeOutCubic.transform(_success.value);
        final shakeT = _shake.value;
        final sensing = _stage == _LockStage.sensing;

        // Failure shake: decaying horizontal wobble.
        final shakeX = shakeT == 0 || shakeT == 1
            ? 0.0
            : math.sin(shakeT * math.pi * 5) * 9 * (1 - shakeT);

        // Two staggered rings expand outward + fade — a calm "scanning"
        // sonar pulse (brighter + tighter while actually sensing).
        Widget ring(double phase) {
          final p = (t + phase) % 1.0;
          return Opacity(
            opacity: (1 - p) * (sensing ? 0.45 : 0.30) * (1 - successT),
            child: Container(
              width: 112 + p * (sensing ? 76 : 96),
              height: 112 + p * (sensing ? 76 : 96),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primaryBlue.withValues(alpha: 0.7),
                  width: 2,
                ),
              ),
            ),
          );
        }

        // Gentle breathing of the core badge (triangle wave 1→1.05),
        // with a proud little pop layered on top during success.
        final breathe = 1 + 0.05 * (0.5 - (t - 0.5).abs()) * 2;
        final pop = 1 + 0.08 * math.sin(successT * math.pi);

        return Transform.translate(
          offset: Offset(animate ? shakeX : 0, 0),
          child: SizedBox(
            width: 216,
            height: 216,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ring(0.0),
                ring(0.5),
                // Gold success ring draws clockwise around the badge.
                if (successT > 0)
                  CustomPaint(
                    size: const Size(148, 148),
                    painter: _SuccessRingPainter(progress: successT),
                  ),
                Transform.scale(scale: breathe * pop, child: child),
              ],
            ),
          ),
        );
      },
      child: AnimatedContainer(
        duration: AppMotion.maybe(context, AppMotion.quick),
        width: 112,
        height: 112,
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          shape: BoxShape.circle,
          border: Border.all(
            color: _stage == _LockStage.failure
                ? AppColors.red
                : AppColors.goldAccent,
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
              color: (_stage == _LockStage.success
                      ? AppColors.goldAccent
                      : AppColors.primaryBlue)
                  .withValues(alpha: _stage == _LockStage.success ? 0.45 : 0.30),
              blurRadius: _stage == _LockStage.success ? 34 : 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: AnimatedSwitcher(
          duration: AppMotion.maybe(context, AppMotion.quick),
          switchInCurve: AppMotion.spring,
          switchOutCurve: AppMotion.easeIn,
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: animation,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: Icon(
            _stage == _LockStage.success
                ? Icons.check_rounded
                : Icons.fingerprint,
            key: ValueKey(_stage == _LockStage.success),
            color: AppColors.white,
            size: 56,
          ),
        ),
      ),
    );
  }
}

/// Gold ring that draws clockwise from the top as the unlock succeeds —
/// the single gold element of this screen.
class _SuccessRingPainter extends CustomPainter {
  _SuccessRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 2;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      progress * 2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..color = AppColors.goldAccent,
    );
  }

  @override
  bool shouldRepaint(_SuccessRingPainter old) => old.progress != progress;
}
