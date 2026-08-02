import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';
import '../../onboarding/widgets/film_scenes.dart'
    show AmbientPainter, GoldRingPainter;

/// Shared shell for every screen in the account flow — forgot password,
/// reset, email verification, profile setup, biometric unlock.
///
/// WHY THIS REPLACES AuthHero
///
/// AuthHero was a full-bleed navy gradient slab with a curved bottom
/// edge and a rounded logo tile. Three problems:
///
///  1. It is the single most recognisable "free template" shape in
///     mobile design. The founder's note was that these screens look
///     cheap; this was why.
///  2. It contradicts the app's own flat-header rule (CLAUDE.md, founder
///     2026-07-28): headers share `palette.scaffoldBg` and never paint a
///     navy slab. Auth was the last place still doing it.
///  3. The onboarding film's own documentation promises that "intro →
///     auth feels like the same film continuing" — and then auth opened
///     on a completely unrelated navy header. The seam was jarring
///     precisely at the moment we ask someone to commit.
///
/// So this shell keeps the film running. It paints the SAME
/// [AmbientPainter] the intro uses, on the same flat background, with a
/// slow independent loop — the light field the user was just watching
/// simply carries on behind the form. The heading block then rises in
/// with a short stagger instead of appearing whole.
///
/// The brand mark is a small ring, not a 64dp gradient tile: at this
/// point the user has already seen the logo for 42 seconds, and a
/// second big badge is noise.
class AuthShell extends StatefulWidget {
  const AuthShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.eyebrow,
    this.onBack,
    this.icon,
    this.hero,
    this.footer,
  });

  /// Large headline. One line ideally, two at most.
  final String title;

  /// Supporting line under the title.
  final String subtitle;

  /// Small uppercase label above the title ("ACCOUNT RECOVERY").
  final String? eyebrow;

  /// Back affordance. Null hides it (e.g. a locked biometric screen).
  final VoidCallback? onBack;

  /// Optional glyph inside the brand ring — gives each screen in the
  /// flow its own identity without changing the furniture.
  final IconData? icon;

  /// Replaces the 52dp brand ring entirely. Only for a screen whose own
  /// mark IS the subject — the biometric lock screen's sonar badge is
  /// already a gradient disc inside a gold ring, and stacking the brand
  /// ring above it makes two of the same object at two sizes, which is
  /// the exact noise this shell exists to remove. Ignored when null;
  /// [icon] is then unused.
  final Widget? hero;

  /// The screen's content, laid out under the heading.
  final Widget child;

  /// Pinned to the bottom, outside the scroll area (e.g. "Back to sign
  /// in"). Optional.
  final Widget? footer;

  @override
  State<AuthShell> createState() => _AuthShellState();
}

class _AuthShellState extends State<AuthShell> with TickerProviderStateMixin {
  /// Continues the intro's light field. Independent of the entrance so
  /// the background keeps breathing after everything has settled.
  late final AnimationController _ambient;

  /// One-shot entrance for the heading + content.
  late final AnimationController _enter;

  @override
  void initState() {
    super.initState();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.enabled(context)) {
      if (!_ambient.isAnimating) _ambient.repeat();
      if (_enter.value == 0) _enter.forward();
    } else {
      // "Remove animations": land on the finished frame at once.
      _ambient.stop();
      _enter.value = 1;
    }
  }

  @override
  void dispose() {
    _ambient.dispose();
    _enter.dispose();
    super.dispose();
  }

  /// Staggered slice of the entrance: item [i] starts a beat after [i-1].
  double _step(int i) {
    const span = 0.34;
    final start = (i * 0.13).clamp(0.0, 1 - span);
    return Curves.easeOutCubic.transform(
      ((_enter.value - start) / span).clamp(0.0, 1.0),
    );
  }

  Widget _rise(int index, Widget child) {
    final v = _step(index);
    return Opacity(
      opacity: v,
      child: Transform.translate(offset: Offset(0, 22 * (1 - v)), child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The intro's ambient field, still running. Own repaint layer
          // so the form above it never re-rasterises with it.
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _ambient,
              builder: (context, _) => CustomPaint(
                painter: AmbientPainter(loop: _ambient.value, film: 1.0),
              ),
            ),
          ),
          SafeArea(
            child: AnimatedBuilder(
              animation: _enter,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Heading AND content share one scroll view. They used
                  // to be split — a fixed heading block above an
                  // Expanded scroll area — which meant the heading alone
                  // could outgrow the viewport: at 2.5x text scale on a
                  // 360x640 phone every screen in this flow overflowed
                  // (95px on the lock screen) and the clipped part was
                  // simply unreachable. iOS accessibility sizes go past
                  // 3x, so that was reachable. Nothing moves at normal
                  // scales, because there is nothing to scroll.
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 44,
                            child: widget.onBack == null
                                ? null
                                : Align(
                                    alignment: Alignment.centerLeft,
                                    child: _BackChip(onTap: widget.onBack!),
                                  ),
                          ),
                          const SizedBox(height: 12),
                          _rise(
                            0,
                            widget.hero ?? _BrandRing(icon: widget.icon),
                          ),
                          const SizedBox(height: 20),
                          if (widget.eyebrow != null) ...[
                            _rise(
                              1,
                              Text(
                                widget.eyebrow!.toUpperCase(),
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.primaryBlue,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.8,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          _rise(
                            2,
                            Text(
                              widget.title,
                              style: AppTextStyles.displayMedium.copyWith(
                                color: palette.text,
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                height: 1.12,
                                letterSpacing: -0.6,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _rise(
                            3,
                            Text(
                              widget.subtitle,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: palette.textMuted,
                                fontSize: 14,
                                height: 1.45,
                              ),
                            ),
                          ),
                          const SizedBox(height: 26),
                          // Explicit full width: this Column is
                          // start-aligned for the heading, but screens
                          // hand us a `stretch` Column and expect the
                          // viewport's width.
                          SizedBox(
                            width: double.infinity,
                            child: _rise(4, widget.child),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.footer != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: _rise(5, widget.footer!),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Quiet back affordance. A bordered chip on the flat background rather
/// than a translucent white square on navy.
class _BackChip extends StatelessWidget {
  const _BackChip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.divider),
          ),
          child: Icon(Icons.arrow_back_ios_new, size: 14, color: palette.text),
        ),
      ),
    );
  }
}

/// A 52dp ring with the screen's glyph — the same gold-ring vocabulary
/// the intro uses for its story rings and its finale, so the flow reads
/// as one piece.
class _BrandRing extends StatelessWidget {
  const _BrandRing({this.icon});
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(52, 52),
            painter: GoldRingPainter(sweep: 1, strokeWidth: 2),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.primaryGradient,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.28),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(
              icon ?? Icons.church_rounded,
              color: AppColors.white,
              size: 19,
            ),
          ),
        ],
      ),
    );
  }
}
