import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/maintenance_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../onboarding/widgets/film_scenes.dart';

/// The blocking screen shown while maintenance is on (#22).
///
/// Its job is to explain, not to enforce — enforcement is the database
/// trigger from `patch_187`, which refuses every content write regardless of
/// what any client thinks. So this screen is free to be calm and useful
/// rather than defensive.
///
/// It is also, on the worst day the app has, the ONLY screen anybody sees.
/// That is the argument for spending real design on it: an outage handled
/// with grace reads as a team in control, and a grey box with a spinner
/// reads as something broken. It borrows the onboarding film's own
/// `AmbientPainter` so the moment still looks like Advent Connect rather
/// than like an error page.
///
/// It polls, so the app comes back on its own when maintenance ends. Nobody
/// should have to guess when to try again, and "force quit and reopen" is
/// not an instruction a premium app gives.
class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key, this.autoPoll = true});

  /// False in tests — the timer otherwise reaches Supabase forever.
  final bool autoPoll;

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen>
    with TickerProviderStateMixin {
  Timer? _poll;
  bool _checking = false;

  late final AnimationController _ambient;
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();

    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
    _entrance = AnimationController(
      vsync: this,
      duration: AppMotion.entrance * 2,
    )..forward();

    if (widget.autoPoll) {
      // 20s: often enough to feel responsive when it ends, rare enough that
      // a few hundred phones sitting on this screen are not a load problem
      // for the very server that is being worked on.
      _poll = Timer.periodic(const Duration(seconds: 20), (_) => _recheck());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _ambient.dispose();
    _entrance.dispose();
    super.dispose();
  }

  Future<void> _recheck() async {
    if (_checking || !mounted) return;
    setState(() => _checking = true);
    final state = await MaintenanceService.check();
    if (!mounted) return;
    setState(() => _checking = false);
    // `blocked`, not `active` — a super admin is exempt server-side and must
    // be let back into the app they are here to fix.
    if (!state.blocked) {
      _poll?.cancel();
      if (mounted) context.goNamed('splash');
    }
  }

  String? _backWhen() {
    final ends = MaintenanceService.last.endsAt?.toLocal();
    if (ends == null) return null;
    if (ends.isBefore(DateTime.now())) return null;
    final hh = ends.hour.toString().padLeft(2, '0');
    final mm = ends.minute.toString().padLeft(2, '0');
    final sameDay = DateUtils.isSameDay(ends, DateTime.now());
    return sameDay
        ? 'Expected back around $hh:$mm'
        : 'Expected back ${ends.day}/${ends.month} around $hh:$mm';
  }

  /// Staggered reveal, one step per element.
  Widget _step(int index, Widget child) {
    final start = (index * 0.09).clamp(0.0, 0.7);
    final curve = CurvedAnimation(
      parent: _entrance,
      curve: Interval(start, (start + 0.5).clamp(0.0, 1.0),
          curve: AppMotion.easeOut),
    );
    return AnimatedBuilder(
      animation: curve,
      builder: (context, _) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
          offset: Offset(0, (1 - curve.value) * 14),
          child: child,
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final backWhen = _backWhen();
    final animate = AppMotion.enabled(context);

    return PopScope(
      // There is nowhere to go back to. Leaving this screen would land on a
      // shell whose every action is being refused by the server.
      canPop: false,
      child: Scaffold(
        backgroundColor: palette.scaffoldBg,
        body: Stack(
          children: [
            // The same slow-drifting light as the onboarding film and the
            // auth screens, so this reads as part of the app rather than as
            // a stray error page.
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _ambient,
                  builder: (context, _) => CustomPaint(
                    painter: AmbientPainter(
                      loop: animate ? _ambient.value : 0.2,
                      film: 0,
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 24,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _step(0, _BreathingMark(animate: animate)),
                        const SizedBox(height: 30),
                        _step(
                          1,
                          Text(
                            'Back shortly',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.headlineMedium.copyWith(
                              color: palette.text,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _step(
                          2,
                          Text(
                            MaintenanceService.last.message,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: palette.textMuted,
                              height: 1.55,
                            ),
                          ),
                        ),
                        if (backWhen != null) ...[
                          const SizedBox(height: 18),
                          _step(3, _EtaPill(text: backWhen)),
                        ],
                        const SizedBox(height: 32),
                        _step(
                          4,
                          _CheckButton(
                            checking: _checking,
                            onTap: _recheck,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _step(
                          5,
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _LiveDot(animate: animate),
                              const SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  // Says what the screen is doing, so nobody
                                  // sits there tapping.
                                  'Checking on its own — this page will come '
                                  'back by itself.',
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.caption.copyWith(
                                    color: palette.textMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The mark at the top: a soft brand halo that breathes.
///
/// A spinner would say "working"; nothing here is working on this phone. A
/// slow pulse says "alive, waiting", which is the honest state.
class _BreathingMark extends StatefulWidget {
  const _BreathingMark({required this.animate});

  final bool animate;

  @override
  State<_BreathingMark> createState() => _BreathingMarkState();
}

class _BreathingMarkState extends State<_BreathingMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return SizedBox(
          width: 132,
          height: 132,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Two haloes at different phases, so the edge never lands on a
              // single hard ring.
              _halo(112 + t * 16, 0.05 + (1 - t) * 0.04),
              _halo(88 + t * 10, 0.10 + (1 - t) * 0.05),
              child!,
            ],
          ),
        );
      },
      child: Container(
        width: 74,
        height: 74,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.primaryGradient,
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withValues(alpha: 0.30),
              blurRadius: 26,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: const Icon(
          Icons.build_rounded,
          size: 32,
          color: AppColors.white,
        ),
      ),
    );
  }

  Widget _halo(double size, double alpha) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primaryBlue.withValues(alpha: alpha),
        ),
      );
}

/// "Expected back around 21:30" — a fact, given the weight of one.
class _EtaPill extends StatelessWidget {
  const _EtaPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: AppColors.primaryBlue.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.schedule_rounded,
            size: 15,
            color: AppColors.primaryBlue,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              text,
              style: AppTextStyles.labelMedium.copyWith(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small dot that pulses in time with the poll, so "it is checking" is
/// something you can see rather than only read.
class _LiveDot extends StatefulWidget {
  const _LiveDot({required this.animate});

  final bool animate;

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = math.sin(_c.value * 2 * math.pi) * 0.5 + 0.5;
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primaryBlue.withValues(alpha: 0.35 + t * 0.65),
          ),
        );
      },
    );
  }
}

/// The one action on the screen.
class _CheckButton extends StatelessWidget {
  const _CheckButton({required this.checking, required this.onTap});

  final bool checking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: checking ? null : AppColors.primaryGradient,
          color: checking ? context.palette.cardMuted : null,
          borderRadius: BorderRadius.circular(AppRadius.button),
          boxShadow: checking
              ? null
              : [
                  BoxShadow(
                    color: AppColors.primaryBlue.withValues(alpha: 0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: checking ? null : onTap,
            borderRadius: BorderRadius.circular(AppRadius.button),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: Center(
                child: checking
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: context.palette.textMuted,
                        ),
                      )
                    : Text(
                        'Check again',
                        style: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w700,
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
