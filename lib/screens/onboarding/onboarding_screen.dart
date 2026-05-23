import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/secure_storage_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const onboardingFlagKey = 'has_seen_onboarding';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final _pageController = PageController();
  late final AnimationController _ambient;
  Timer? _autoTimer;
  int _index = 0;
  double _page = 0;
  bool _autoPaused = false;

  static const _slides = <_Slide>[
    _Slide(
      tag: 'CHURCHES',
      icon: Icons.church_rounded,
      headline: '2,600 churches.\nOne community.',
      description:
          'Discover every Seventh-day Adventist church across Zimbabwe — '
          'with directions, services, and pastors at your fingertips.',
      accent: Color(0xFF1A4480),
    ),
    _Slide(
      tag: 'EVENTS',
      icon: Icons.event_available_rounded,
      headline: 'Never miss\na gathering.',
      description:
          'RSVP to conferences, youth programs, and revival meetings near '
          'you — your spiritual calendar, always in tune.',
      accent: Color(0xFF1456A8),
    ),
    _Slide(
      tag: 'MARKETPLACE',
      icon: Icons.storefront_rounded,
      headline: 'Trade within\na trusted circle.',
      description:
          'Buy and sell with verified members — health food, books, modest '
          'fashion, and more, all in one safe place.',
      accent: Color(0xFF15498F),
    ),
    _Slide(
      tag: 'OPPORTUNITY',
      icon: Icons.work_outline_rounded,
      headline: 'Build your\nfuture together.',
      description:
          'Discover jobs and opportunities shared by members and recruiters '
          'who walk the same path as you.',
      accent: Color(0xFF1A3F73),
    ),
    _Slide(
      tag: 'PRAYER',
      icon: Icons.volunteer_activism_rounded,
      headline: 'Carry each\nother in prayer.',
      description:
          'Lift up requests, intercede for one another, and witness how '
          'God moves through community.',
      accent: Color(0xFF143966),
    ),
    _Slide(
      tag: 'CONNECT',
      icon: Icons.forum_rounded,
      headline: 'Fellowship,\nwherever you are.',
      description:
          'Message members, build prayer circles, and form lasting '
          'friendships rooted in Christ.',
      accent: Color(0xFF1565C0),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
    _pageController.addListener(_onPage);
    _startAutoAdvance();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _ambient.dispose();
    _pageController.removeListener(_onPage);
    _pageController.dispose();
    super.dispose();
  }

  void _onPage() {
    if (!mounted) return;
    final p = _pageController.page;
    if (p == null) return;
    setState(() => _page = p);
  }

  void _startAutoAdvance() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(const Duration(milliseconds: 4800), (_) {
      if (!mounted || _autoPaused) return;
      if (_index >= _slides.length - 1) {
        _autoTimer?.cancel();
        return;
      }
      _pageController.nextPage(
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  Future<void> _finish() async {
    HapticFeedback.mediumImpact();
    await SecureStorageService.write(
      OnboardingScreen.onboardingFlagKey,
      'true',
    );
    if (!mounted) return;
    // Skip the standalone age screen — AuthScreen's signup stage
    // collects the birth date inline as part of the create-account
    // form.
    context.goNamed('login');
  }

  void _next() {
    HapticFeedback.selectionClick();
    if (_index >= _slides.length - 1) {
      _finish();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 750),
      curve: Curves.easeOutCubic,
    );
  }

  Color _lerpAccent() {
    final base = _page.floor().clamp(0, _slides.length - 1);
    final next = (base + 1).clamp(0, _slides.length - 1);
    final t = (_page - base).clamp(0.0, 1.0);
    return Color.lerp(_slides[base].accent, _slides[next].accent, t) ??
        _slides[base].accent;
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _index == _slides.length - 1;
    final accent = _lerpAccent();

    return Scaffold(
      backgroundColor: AppColors.darkNavy,
      body: GestureDetector(
        onTapDown: (_) => setState(() => _autoPaused = true),
        onTapUp: (_) => setState(() => _autoPaused = false),
        onTapCancel: () => setState(() => _autoPaused = false),
        child: Stack(
          children: [
            // Layer 1 — mood gradient (lerps between slides)
            AnimatedContainer(
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.darkNavy, accent],
                ),
              ),
            ),

            // Layer 2 — drifting ambient orbs
            AnimatedBuilder(
              animation: _ambient,
              builder: (context, _) => _AmbientOrbs(
                t: _ambient.value,
                accent: accent,
              ),
            ),

            // Layer 3 — floating particles
            AnimatedBuilder(
              animation: _ambient,
              builder: (context, _) => CustomPaint(
                painter: _ParticlesPainter(t: _ambient.value),
                size: Size.infinite,
              ),
            ),

            // Layer 4 — soft vignette so the centre pops
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 1.1,
                    colors: [
                      Color(0x00000000),
                      Color(0x550A1430),
                    ],
                  ),
                ),
                child: SizedBox.expand(),
              ),
            ),

            // Layer 5 — content
            SafeArea(
              child: Column(
                children: [
                  _buildTopBar(isLast),
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: _slides.length,
                      physics: const BouncingScrollPhysics(),
                      onPageChanged: (i) {
                        HapticFeedback.lightImpact();
                        setState(() => _index = i);
                      },
                      itemBuilder: (context, i) {
                        final delta = (i - _page).clamp(-1.2, 1.2);
                        return _SlideView(
                          slide: _slides[i],
                          delta: delta,
                          active: i == _index,
                          ambient: _ambient,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildProgress(),
                  const SizedBox(height: 26),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                    child: _ShimmerButton(
                      label: isLast ? 'Get started' : 'Continue',
                      isLast: isLast,
                      ambient: _ambient,
                      onTap: _next,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(bool isLast) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.white.withValues(alpha: 0.14),
                  AppColors.white.withValues(alpha: 0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: AppColors.white.withValues(alpha: 0.15),
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.church_rounded,
                color: AppColors.goldAccent,
                size: 20,
              ),
            ),
          ),
          if (!isLast)
            TextButton(
              onPressed: _finish,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Skip',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: AppColors.white.withValues(alpha: 0.80),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 14,
                    color: AppColors.white.withValues(alpha: 0.70),
                  ),
                ],
              ),
            )
          else
            const SizedBox(width: 56),
        ],
      ),
    );
  }

  Widget _buildProgress() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: Row(
        children: List.generate(_slides.length, (i) {
          final isFilled = i <= _index;
          final isActive = i == _index;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              height: 3,
              decoration: BoxDecoration(
                gradient: isFilled
                    ? const LinearGradient(
                        colors: [
                          AppColors.goldAccent,
                          Color(0xFFE0C780),
                        ],
                      )
                    : null,
                color: isFilled
                    ? null
                    : AppColors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(2),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: AppColors.goldAccent.withValues(alpha: 0.45),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _Slide {
  const _Slide({
    required this.tag,
    required this.icon,
    required this.headline,
    required this.description,
    required this.accent,
  });

  final String tag;
  final IconData icon;
  final String headline;
  final String description;
  final Color accent;
}

// ────────────────────────────────────────────────────────────────────
//  Slide
// ────────────────────────────────────────────────────────────────────

class _SlideView extends StatefulWidget {
  const _SlideView({
    required this.slide,
    required this.delta,
    required this.active,
    required this.ambient,
  });

  final _Slide slide;
  final double delta;
  final bool active;
  final AnimationController ambient;

  @override
  State<_SlideView> createState() => _SlideViewState();
}

class _SlideViewState extends State<_SlideView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.active) _entrance.forward();
  }

  @override
  void didUpdateWidget(covariant _SlideView old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _entrance
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  Animation<double> _stage(double begin, double end) => CurvedAnimation(
        parent: _entrance,
        curve: Interval(begin, end, curve: Curves.easeOutCubic),
      );

  @override
  Widget build(BuildContext context) {
    final tagAnim = _stage(0.00, 0.55);
    final iconAnim = _stage(0.05, 0.80);
    final headlineAnim = _stage(0.25, 0.90);
    final descAnim = _stage(0.45, 1.00);

    // Parallax — depth layers shift at different rates
    final tagPx = widget.delta * -18;
    final iconPx = widget.delta * -42;
    final textPx = widget.delta * -64;

    return AnimatedBuilder(
      animation: _entrance,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Tag chip
              Transform.translate(
                offset: Offset(tagPx, (1 - tagAnim.value) * 22),
                child: Opacity(
                  opacity: tagAnim.value,
                  child: _TagChip(text: widget.slide.tag),
                ),
              ),
              const SizedBox(height: 36),

              // Hero orb
              Transform.translate(
                offset: Offset(iconPx, (1 - iconAnim.value) * 36),
                child: Transform.scale(
                  scale: 0.82 + iconAnim.value * 0.18,
                  child: Opacity(
                    opacity: iconAnim.value,
                    child: _HeroOrb(
                      icon: widget.slide.icon,
                      ambient: widget.ambient,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 48),

              // Headline
              Transform.translate(
                offset: Offset(textPx, (1 - headlineAnim.value) * 28),
                child: Opacity(
                  opacity: headlineAnim.value,
                  child: Text(
                    widget.slide.headline,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      color: AppColors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Description
              Transform.translate(
                offset: Offset(textPx * 1.15, (1 - descAnim.value) * 28),
                child: Opacity(
                  opacity: descAnim.value,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      widget.slide.description,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: AppColors.white.withValues(alpha: 0.80),
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: AppColors.goldAccent.withValues(alpha: 0.55),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: AppColors.goldAccent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.goldAccent.withValues(alpha: 0.7),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 9),
          Text(
            text,
            style: GoogleFonts.poppins(
              color: AppColors.goldAccent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Hero orb — pulse rings + breathing + rotating shimmer
// ────────────────────────────────────────────────────────────────────

class _HeroOrb extends StatelessWidget {
  const _HeroOrb({required this.icon, required this.ambient});
  final IconData icon;
  final AnimationController ambient;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      height: 240,
      child: AnimatedBuilder(
        animation: ambient,
        builder: (context, _) {
          final t = ambient.value;
          final breathe = 1.0 + math.sin(t * math.pi * 2) * 0.035;
          final rotate = t * math.pi * 2;

          return Stack(
            alignment: Alignment.center,
            children: [
              _pulseRing(t, 0.00),
              _pulseRing(t, 0.33),
              _pulseRing(t, 0.66),

              // Outer halo glow
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.40),
                      blurRadius: 70,
                      spreadRadius: 8,
                    ),
                    BoxShadow(
                      color: AppColors.goldAccent.withValues(alpha: 0.12),
                      blurRadius: 30,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),

              // Outer rotating shimmer ring
              Transform.rotate(
                angle: rotate,
                child: Container(
                  width: 188,
                  height: 188,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        AppColors.white.withValues(alpha: 0.0),
                        AppColors.white.withValues(alpha: 0.0),
                        AppColors.goldAccent.withValues(alpha: 0.55),
                        AppColors.white.withValues(alpha: 0.35),
                        AppColors.white.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.55, 0.78, 0.90, 1.0],
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 178,
                      height: 178,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.darkNavy,
                      ),
                    ),
                  ),
                ),
              ),

              // Outer glass frame
              Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.white.withValues(alpha: 0.10),
                      AppColors.white.withValues(alpha: 0.02),
                    ],
                  ),
                  border: Border.all(
                    color: AppColors.white.withValues(alpha: 0.18),
                    width: 1,
                  ),
                ),
              ),

              // Inner glass disk (breathing) with the icon
              Transform.scale(
                scale: breathe,
                child: Container(
                  width: 138,
                  height: 138,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.white.withValues(alpha: 0.22),
                        AppColors.white.withValues(alpha: 0.06),
                      ],
                    ),
                    border: Border.all(
                      color: AppColors.white.withValues(alpha: 0.30),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryBlue.withValues(alpha: 0.35),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Center(
                    child: ShaderMask(
                      shaderCallback: (rect) => const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFFFFFFF), Color(0xFFE6ECF7)],
                      ).createShader(rect),
                      child: Icon(
                        icon,
                        size: 62,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                ),
              ),

              // Small gold orbiting accent
              Transform.rotate(
                angle: rotate * 0.6,
                child: Align(
                  alignment: const Alignment(0.85, -0.85),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.goldAccent,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.goldAccent.withValues(alpha: 0.8),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _pulseRing(double t, double phase) {
    final progress = (t + phase) % 1.0;
    final size = 150 + progress * 90;
    final opacity = (1.0 - progress) * 0.35;
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.white.withValues(alpha: opacity),
            width: 1,
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Ambient orbs — soft drifting blobs behind everything
// ────────────────────────────────────────────────────────────────────

class _AmbientOrbs extends StatelessWidget {
  const _AmbientOrbs({required this.t, required this.accent});
  final double t;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    final a = math.sin(t * math.pi * 2);
    final b = math.cos(t * math.pi * 2);
    final c = math.sin(t * math.pi * 2 + 1.4);

    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: w * 0.05 + a * 28,
            top: h * 0.05 + b * 22,
            child: _orb(300, accent.withValues(alpha: 0.45)),
          ),
          Positioned(
            right: -40 + b * 36,
            top: h * 0.30 + a * 28,
            child: _orb(260, AppColors.primaryBlue.withValues(alpha: 0.28)),
          ),
          Positioned(
            left: w * 0.20 + c * 50,
            bottom: h * 0.05 + a * 24,
            child: _orb(280, AppColors.goldAccent.withValues(alpha: 0.10)),
          ),
        ],
      ),
    );
  }

  Widget _orb(double s, Color color) {
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0.0)],
          stops: const [0.0, 1.0],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
//  Particles — slow rising dust motes
// ────────────────────────────────────────────────────────────────────

class _ParticlesPainter extends CustomPainter {
  _ParticlesPainter({required this.t});
  final double t;

  static final math.Random _rng = math.Random(42);
  static final List<_Particle> _particles = List.generate(
    32,
    (_) => _Particle(
      x: _rng.nextDouble(),
      speed: 0.18 + _rng.nextDouble() * 0.45,
      seed: _rng.nextDouble(),
      radius: 0.6 + _rng.nextDouble() * 1.6,
      alpha: 0.10 + _rng.nextDouble() * 0.35,
    ),
  );

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in _particles) {
      final progress = (t * p.speed + p.seed) % 1.0;
      final y = size.height * (1.0 - progress);
      final drift = math.sin((progress + p.seed) * math.pi * 4) * 16;
      final x = size.width * p.x + drift;
      final alpha =
          (p.alpha * (1.0 - (progress - 0.5).abs() * 2).clamp(0.0, 1.0))
              .clamp(0.0, 1.0);
      final paint = Paint()
        ..color = AppColors.white.withValues(alpha: alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6);
      canvas.drawCircle(Offset(x, y), p.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlesPainter old) => old.t != t;
}

class _Particle {
  _Particle({
    required this.x,
    required this.speed,
    required this.seed,
    required this.radius,
    required this.alpha,
  });
  final double x;
  final double speed;
  final double seed;
  final double radius;
  final double alpha;
}

// ────────────────────────────────────────────────────────────────────
//  Primary button — gold gradient with travelling shimmer
// ────────────────────────────────────────────────────────────────────

class _ShimmerButton extends StatelessWidget {
  const _ShimmerButton({
    required this.label,
    required this.isLast,
    required this.ambient,
    required this.onTap,
  });

  final String label;
  final bool isLast;
  final AnimationController ambient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ambient,
      builder: (context, _) {
        // travelling shimmer position
        final shimmer = ambient.value;
        return Container(
          decoration: BoxDecoration(
            gradient: isLast
                ? const LinearGradient(
                    colors: [Color(0xFFC8A951), Color(0xFFE0C780)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : LinearGradient(
                    colors: [
                      AppColors.white,
                      AppColors.white.withValues(alpha: 0.92),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: (isLast ? AppColors.goldAccent : AppColors.white)
                    .withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                // shimmer streak
                Positioned.fill(
                  child: IgnorePointer(
                    child: Align(
                      alignment: Alignment(-1.0 + shimmer * 2.0, 0),
                      child: Transform.rotate(
                        angle: -0.35,
                        child: Container(
                          width: 60,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                AppColors.white.withValues(alpha: 0.55),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            label,
                            style: AppTextStyles.buttonText.copyWith(
                              color: isLast
                                  ? AppColors.darkNavy
                                  : AppColors.primaryBlue,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            isLast
                                ? Icons.arrow_forward_rounded
                                : Icons.chevron_right_rounded,
                            color: isLast
                                ? AppColors.darkNavy
                                : AppColors.primaryBlue,
                            size: isLast ? 18 : 22,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
