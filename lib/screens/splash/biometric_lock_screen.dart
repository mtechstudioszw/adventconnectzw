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
import '../auth/widgets/auth_shell.dart';
import '../onboarding/widgets/film_scenes.dart' show GoldRingPainter;

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
/// This sits on [AuthShell] like every other account screen, so the
/// intro film's ambient light keeps running behind it and the heading
/// rises on the same stagger — cold start → intro → auth is one piece.
/// `onBack` is null on purpose: a locked screen must not offer a way out.
/// The shell's 52dp brand ring is replaced by this screen's own badge
/// via `hero`, because the badge is already a gradient disc in a gold
/// ring and two of those stacked is noise.
///
/// The badge shows the sensor this device actually uses
/// ([BiometricService.primaryKind]) and animates the act of reading it,
/// which is not the same act for a fingertip and a camera:
/// * idle — fingerprint: calm sonar ripples; face/iris: a resting
///   viewfinder reticle;
/// * sensing — a bright band sweeps across the sensor with a gold
///   leading edge (what a real reader does). Fingerprint keeps its
///   ripples and tightens them; face drops the ripples entirely (nothing
///   is touching the phone) and closes the reticle in instead;
/// * success — a gold ring draws around the badge and the glyph morphs
///   to a check, in ONE short beat, then we navigate;
/// * failure — the badge shakes and flashes toward red, then settles
///   back to idle.
///
/// SPEED IS A FEATURE HERE. A returning user passes through this screen
/// several times a day, so the unlock is kept as close to WhatsApp's as
/// the platform allows: the splash hands off without its 320ms fade, the
/// biometric channel is pre-warmed during boot, the confirmation is one
/// 200ms beat rather than 740ms of celebration, and the profile-setup
/// network check is timeboxed below that so it can never be the slowest
/// thing in the path. Nothing on screen says "waiting".
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

  /// What this device actually reads. Defaults to fingerprint — the
  /// common sensor on the hardware this app runs on — and is corrected
  /// from the platform the moment [BiometricService.primaryKind]
  /// answers. Usually already cached: the splash pre-warms it during boot.
  BiometricKind _kind =
      BiometricService.kindCached ?? BiometricKind.fingerprint;

  late final AnimationController _pulse;
  late final AnimationController _success;
  late final AnimationController _shake;

  /// Drives the scan sweep that crosses the sensor while it is actually
  /// reading. Runs ONLY during [_LockStage.sensing] — the badge should
  /// look like it is doing something because it is, not as decoration.
  late final AnimationController _scan;

  /// Only success locks the button out. Sensing used to as well, which
  /// meant a prompt that never returned left a dead, greyed-out control
  /// on screen with nothing the user could do.
  bool get _busy => _stage == _LockStage.success;

  @override
  void initState() {
    super.initState();
    // Continuous "sonar" pulse behind the fingerprint badge so the lock
    // screen feels alive while it waits for the biometric prompt. NOT
    // started here — didChangeDependencies owns that, because whether it
    // may run at all depends on MediaQuery (see below).
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _scan = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    // WhatsApp-fast. This was AppMotion.celebrate (600ms) plus a 140ms
    // breather — 740ms of animation AFTER the finger was already
    // recognised, on a screen a returning user passes through several
    // times a day. One short beat is enough to confirm; anything more is
    // the app making the user wait to admire it.
    _success = AnimationController(vsync: this, duration: AppMotion.quick);
    _shake =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 480),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed &&
              mounted &&
              _stage == _LockStage.failure) {
            setState(() => _stage = _LockStage.idle);
          }
        });
    // Correct the sensor kind if the splash's pre-warm hasn't landed yet.
    // Cheap and cached, so this is normally a no-op.
    if (BiometricService.kindCached == null) {
      BiometricService.primaryKind().then((kind) {
        if (mounted && kind != _kind) setState(() => _kind = kind);
      });
    }
    if (widget.autoPrompt) {
      // Defer one frame so the lock screen paints before the system
      // dialog appears — otherwise the user sees a white flash behind
      // the prompt the first time around.
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryUnlock());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The sonar used to `..repeat()` straight out of initState, so a user
    // with the OS "remove animations" setting on got a permanently
    // expanding sonar and a breathing badge — and the screen never idled,
    // holding vsync on a screen people sit and stare at. Only the failure
    // shake was ever gated. Everything reads the flag now.
    _syncMotion();
  }

  /// Runs the sonar and the scan sweep only when each is both wanted and
  /// allowed. `value = 0` is the calm resting frame: rings sit at their
  /// smallest radius and the badge is at its natural size, so the still
  /// version still reads as a deliberate halo rather than a half-finished
  /// animation.
  void _syncMotion() {
    final animate = AppMotion.enabled(context);
    if (!animate || _stage == _LockStage.success) {
      _pulse.stop();
      _pulse.value = 0;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
    // The sweep is the sensor reading — it exists only while that is
    // literally true, so an idle badge never pretends to be scanning.
    if (animate && _stage == _LockStage.sensing) {
      if (!_scan.isAnimating) _scan.repeat();
    } else {
      _scan.stop();
      _scan.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _success.dispose();
    _shake.dispose();
    _scan.dispose();
    super.dispose();
  }

  void _setStage(_LockStage stage) {
    if (!mounted || _stage == stage) return;
    setState(() => _stage = stage);
    // The sonar tightens while the sensor is actually listening.
    _pulse.duration = Duration(
      milliseconds: stage == _LockStage.sensing ? 1100 : 2000,
    );
    _syncMotion();
  }

  /// True while the OS prompt is genuinely in flight, so a second tap
  /// can't call into `local_auth` concurrently (the plugin throws).
  /// Separate from [_busy], which is only about disabling the button.
  bool _prompting = false;

  Future<void> _tryUnlock() async {
    if (_prompting || _busy) return;
    _prompting = true;
    _setStage(_LockStage.sensing);
    final ok = await BiometricService.authenticate(
      reason: 'Unlock Adventist Super App',
    );
    _prompting = false;
    if (!mounted) return;
    if (ok) {
      // Route to home (or profile setup if they never finished
      // onboarding). The profile-setup check is a NETWORK call — run it
      // in PARALLEL with the confirmation instead of before it, and
      // timebox it SHORTER than that animation so it can never become the
      // critical path. The box used to be 700ms, sized against a 740ms
      // celebration; now that the confirmation is one 200ms beat, a 700ms
      // box would be the slowest thing in the unlock. A returning
      // (biometric) user has completed setup by definition — they signed
      // in and then enabled biometrics — so a slow connection defaults to
      // home rather than stalling the door.
      final completedFuture = AuthService.hasCompletedProfileSetup()
          .timeout(const Duration(milliseconds: 180), onTimeout: () => true)
          .catchError((_) => true);
      // One short beat: gold ring draws in, sensor glyph becomes a check.
      _setStage(_LockStage.success);
      HapticFeedback.mediumImpact();
      if (AppMotion.enabled(context)) {
        await _success.forward();
      } else {
        _success.value = 1;
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
              style: AppTextStyles.labelMedium.copyWith(color: AppColors.text),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
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

  bool get _isFace =>
      _kind == BiometricKind.face || _kind == BiometricKind.iris;

  /// The glyph the badge wears. A phone that unlocks by camera should not
  /// show a fingerprint.
  IconData get _sensorIcon => switch (_kind) {
    BiometricKind.face => Icons.face_rounded,
    BiometricKind.iris => Icons.remove_red_eye_rounded,
    BiometricKind.fingerprint => Icons.fingerprint,
  };

  /// The live status line. The shell's subtitle carries the stable
  /// explanation; this one carries the state, and sits under the badge
  /// where the user is already looking.
  ///
  /// Nothing here says "waiting". The sensor is the thing doing work, not
  /// the app, and copy that says otherwise makes a fast unlock feel slow.
  String get _status {
    switch (_stage) {
      case _LockStage.idle:
        return _isFace
            ? 'Look at your phone to unlock.'
            : 'Touch the fingerprint sensor to unlock.';
      case _LockStage.sensing:
        return _isFace ? 'Reading your face…' : 'Reading your fingerprint…';
      case _LockStage.success:
        return 'Unlocked.';
      case _LockStage.failure:
        return _isFace
            ? 'Didn’t recognise you — try again.'
            : 'Didn’t read that — try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AuthShell(
      eyebrow: 'Locked',
      title: 'Welcome back',
      subtitle:
          'Your session is still active — unlock with your '
          'fingerprint or face to carry on.',
      // A locked screen must not offer a way back out.
      onBack: null,
      hero: _buildBadge(context),
      footer: TextButton(
        onPressed: _busy ? null : _signOut,
        child: Text(
          'Sign out',
          style: AppTextStyles.labelMedium.copyWith(
            color: palette.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSwitcher(
            duration: AppMotion.maybe(context, AppMotion.quick),
            child: Text(
              _status,
              key: ValueKey(_stage),
              style: AppTextStyles.bodyMedium.copyWith(
                color: _stage == _LockStage.failure
                    ? AppColors.red
                    : palette.textMuted,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 22),
          // The button no longer says "Waiting…" while the sensor reads.
          // The OS sheet is up at that moment and the app is not the
          // thing working — labelling our own button as waiting made a
          // sub-second unlock read as a stall. The badge and the status
          // line carry the sensing state; the button just stays what it
          // is, and stays tappable so a prompt that never returns isn't a
          // dead end.
          _UnlockButton(
            icon: _sensorIcon,
            label: _stage == _LockStage.failure ? 'Try again' : 'Unlock',
            onTap: _busy ? null : _tryUnlock,
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(BuildContext context) {
    // The old screen hard-coded a 216dp box. Combined with two Spacers
    // and no scroll, that overflowed by 49px at 2.0x text scale on a
    // 360x640 phone (262px at 2.5x) — Android's accessibility font size
    // reaches 2.0x, so it was reachable. The shell scrolls its child, but
    // the hero sits in the fixed heading block, so the badge has to give
    // ground when the type grows.
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final box = (208 - (scale - 1) * 90).clamp(118.0, 208.0);
    final core = box * 0.538;

    return AnimatedBuilder(
      animation: Listenable.merge([_pulse, _success, _shake, _scan]),
      builder: (context, child) {
        final t = _pulse.value; // 0 → 1, repeating
        final successT = Curves.easeOutCubic.transform(_success.value);
        final shakeT = _shake.value;
        final sensing = _stage == _LockStage.sensing;

        // Failure shake: decaying horizontal wobble.
        final shakeX = shakeT == 0 || shakeT == 1
            ? 0.0
            : math.sin(shakeT * math.pi * 5) * 9 * (1 - shakeT);

        // Two staggered rings expand outward + fade. This is a fingertip
        // idea — a ripple spreading from the point of contact — so a
        // face/iris device gets a reticle instead of ripples. Suppressed
        // while a face is being read: the camera is not touching anything.
        Widget ring(double phase) {
          final p = (t + phase) % 1.0;
          final grow = core * (sensing ? 0.68 : 0.86);
          return Opacity(
            opacity: (1 - p) * (sensing ? 0.45 : 0.30) * (1 - successT),
            child: Container(
              width: core + p * grow,
              height: core + p * grow,
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
          offset: Offset(shakeX, 0),
          child: SizedBox(
            width: box,
            height: box,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!(_isFace && sensing)) ...[ring(0.0), ring(0.5)],
                // Face/iris: a reticle that closes in while the camera
                // reads, the way a viewfinder acquires a subject.
                if (_isFace)
                  CustomPaint(
                    size: Size(box * 0.92, box * 0.92),
                    painter: _ReticlePainter(
                      // Brackets sit wide at rest and tighten onto the
                      // face as the read happens.
                      close: sensing
                          ? Curves.easeOutCubic.transform(
                              (_scan.value * 2).clamp(0.0, 1.0),
                            )
                          : 0,
                      opacity: (sensing ? 0.85 : 0.35) * (1 - successT),
                    ),
                  ),
                if (successT > 0)
                  // Gold ring draws clockwise around the badge as the
                  // unlock lands — the same GoldRingPainter the intro, the
                  // splash and the shell's brand mark all use, so the
                  // moment belongs to the film instead of inventing its
                  // own ring. (This screen used to carry a private copy.)
                  CustomPaint(
                    size: Size(core * 1.32, core * 1.32),
                    painter: GoldRingPainter(sweep: successT, strokeWidth: 3.5),
                  ),
                Transform.scale(scale: breathe * pop, child: child),
                // The read itself: a bright band crossing the sensor,
                // clipped to the disc. This is the part that makes the
                // badge look like it is scanning rather than decorating,
                // and it exists only while the sensor is genuinely live.
                if (sensing && successT == 0)
                  IgnorePointer(
                    // Same scale as the disc beneath it. Without this the
                    // sweep stays at rest size while the badge breathes
                    // to 1.05, leaving a thin rim the light never
                    // crosses — which reads as a misaligned overlay
                    // rather than light moving over the sensor.
                    child: Transform.scale(
                      scale: breathe * pop,
                      child: SizedBox(
                        width: core,
                        height: core,
                        child: ClipOval(
                          child: CustomPaint(
                            painter: _ScanSweepPainter(progress: _scan.value),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
      child: _BadgeCore(size: core, stage: _stage, sensorIcon: _sensorIcon),
    );
  }
}

/// The scan band: a soft bright sweep travelling across the sensor while
/// it reads, with a brighter leading edge — the thing every real
/// fingerprint reader animation does. Clipped to the badge disc by the
/// caller, so it reads as light moving *over* the sensor surface.
class _ScanSweepPainter extends CustomPainter {
  _ScanSweepPainter({required this.progress});

  /// 0 → 1, repeating. Travels from just above the disc to just below.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    // Ease the travel so the band slows slightly at the extremes rather
    // than strobing at a constant rate.
    final eased = Curves.easeInOutSine.transform(progress);
    final band = h * 0.42;
    final centreY = -band / 2 + eased * (h + band);
    final rect = Rect.fromLTWH(0, centreY - band / 2, size.width, band);

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00FFFFFF), Color(0x38FFFFFF), Color(0x00FFFFFF)],
          stops: [0.0, 0.5, 1.0],
        ).createShader(rect),
    );

    // Leading edge — a thin bright line so the sweep has a direction.
    canvas.drawLine(
      Offset(0, centreY + band / 2),
      Offset(size.width, centreY + band / 2),
      Paint()
        ..color = AppColors.goldAccent.withValues(alpha: 0.55)
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(_ScanSweepPainter old) => old.progress != progress;
}

/// Four corner brackets around the badge — a viewfinder acquiring a
/// subject. Only for face/iris devices: ripples spreading from a point of
/// contact are a fingertip idea and say the wrong thing about a camera.
class _ReticlePainter extends CustomPainter {
  _ReticlePainter({required this.close, required this.opacity});

  /// 0 = resting wide, 1 = closed in on the subject.
  final double close;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    // Brackets travel inward by up to 8% of the box as the read lands.
    final inset = size.width * (0.02 + 0.08 * close);
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );
    final arm = size.width * 0.17;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = AppColors.primaryBlue.withValues(alpha: opacity);

    void corner(Offset c, double dx, double dy) {
      canvas.drawLine(c, c.translate(arm * dx, 0), paint);
      canvas.drawLine(c, c.translate(0, arm * dy), paint);
    }

    corner(rect.topLeft, 1, 1);
    corner(rect.topRight, -1, 1);
    corner(rect.bottomLeft, 1, -1);
    corner(rect.bottomRight, -1, -1);
  }

  @override
  bool shouldRepaint(_ReticlePainter old) =>
      old.close != close || old.opacity != opacity;
}

/// The gradient disc itself — split out so the sonar's AnimatedBuilder
/// rebuilds only the moving parts and this stays a cached child.
class _BadgeCore extends StatelessWidget {
  const _BadgeCore({
    required this.size,
    required this.stage,
    required this.sensorIcon,
  });

  final double size;
  final _LockStage stage;

  /// Fingerprint, face or iris — whatever this device actually reads.
  final IconData sensorIcon;

  @override
  Widget build(BuildContext context) {
    final success = stage == _LockStage.success;
    return AnimatedContainer(
      duration: AppMotion.maybe(context, AppMotion.quick),
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        shape: BoxShape.circle,
        border: Border.all(
          color: stage == _LockStage.failure
              ? AppColors.red
              : AppColors.goldAccent,
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (success ? AppColors.goldAccent : AppColors.primaryBlue)
                .withValues(alpha: success ? 0.45 : 0.30),
            blurRadius: success ? 34 : 24,
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
          success ? Icons.check_rounded : sensorIcon,
          key: ValueKey(success ? Icons.check_rounded : sensorIcon),
          color: AppColors.white,
          size: size * 0.5,
        ),
      ),
    );
  }
}

/// Primary CTA. Matches the gradient pill the rest of the account flow
/// uses rather than a stock FilledButton, so the lock screen doesn't
/// look like a different app than the screen before it.
class _UnlockButton extends StatelessWidget {
  const _UnlockButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.6 : 1,
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // No spinner. A spinner here would say the app is
                  // working, which it isn't — the sensor is, and the
                  // badge above already shows that.
                  Icon(icon, color: AppColors.white, size: 20),
                  const SizedBox(width: 10),
                  // Flexible, not fixed: "Waiting…" at 2.5x text scale is
                  // wider than a 360dp phone once the icon is in the row.
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.buttonText.copyWith(
                        fontSize: 15.5,
                        letterSpacing: 0.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
