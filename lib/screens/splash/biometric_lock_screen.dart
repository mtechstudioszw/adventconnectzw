import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../../theme/app_colors.dart';
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
class BiometricLockScreen extends StatefulWidget {
  const BiometricLockScreen({super.key, this.autoPrompt = true});

  /// Whether to fire the biometric prompt as soon as the screen mounts.
  /// True for cold-start + resume entries (the common case); false if
  /// some other flow needs to land here without an immediate prompt.
  final bool autoPrompt;

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen>
    with SingleTickerProviderStateMixin {
  bool _prompting = false;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    // Continuous "sonar" pulse behind the fingerprint badge so the lock
    // screen feels alive while it waits for the biometric prompt.
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
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
    super.dispose();
  }

  Future<void> _tryUnlock() async {
    if (_prompting) return;
    setState(() => _prompting = true);
    final ok = await BiometricService.authenticate(
      reason: 'Unlock Advent Connect ZW',
    );
    if (!mounted) return;
    setState(() => _prompting = false);
    if (ok) {
      // After a successful unlock, route to home (or profile setup if
      // they never finished onboarding). Mirrors the splash logic so
      // both entry points end up in the same place.
      final completed = await AuthService.hasCompletedProfileSetup();
      if (!mounted) return;
      if (!completed) {
        context.goNamed('profile_setup');
      } else {
        context.goNamed('home');
      }
    }
    // On cancel / failure we intentionally do nothing — the user
    // stays on this screen and can tap Try again. The session is
    // untouched.
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
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
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
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) {
                  final t = _pulse.value; // 0 → 1, repeating
                  // Two staggered rings expand outward + fade — a calm
                  // "scanning" sonar pulse.
                  Widget ring(double phase) {
                    final p = (t + phase) % 1.0;
                    return Opacity(
                      opacity: (1 - p) * 0.30,
                      child: Container(
                        width: 112 + p * 96,
                        height: 112 + p * 96,
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

                  // Gentle breathing of the core badge (triangle wave 1→1.05).
                  final breathe = 1 + 0.05 * (0.5 - (t - 0.5).abs()) * 2;
                  return SizedBox(
                    width: 216,
                    height: 216,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        ring(0.0),
                        ring(0.5),
                        Transform.scale(scale: breathe, child: child),
                      ],
                    ),
                  );
                },
                child: Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.goldAccent, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryBlue.withValues(alpha: 0.30),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.fingerprint,
                    color: AppColors.white,
                    size: 56,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Advent Connect ZW is locked',
                textAlign: TextAlign.center,
                style: AppTextStyles.headlineMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Use your fingerprint or face to unlock the app.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: context.palette.textMuted,
                  height: 1.5,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _prompting ? null : _tryUnlock,
                  icon: _prompting
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
                    _prompting ? 'Waiting…' : 'Try again',
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
                onPressed: _prompting ? null : _signOut,
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
}
