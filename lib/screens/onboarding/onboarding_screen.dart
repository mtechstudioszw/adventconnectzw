import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../services/secure_storage_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// First-launch slides shown before sign-in. Repalette: matches the
/// post-verification profile-setup look — light grey background,
/// white cards, primary-blue accents, gold sparkle. The old dark-navy
/// shimmer + particles felt "AI generated" per user feedback; this
/// version is calm, branded, and consistent with the rest of the auth
/// flow.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const onboardingFlagKey = 'has_seen_onboarding';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final _pageController = PageController();
  Timer? _autoTimer;
  int _index = 0;
  bool _autoPaused = false;

  static const _slides = <_Slide>[
    _Slide(
      tag: 'CHURCHES',
      icon: Icons.church_rounded,
      headline: '2,600 churches.\nOne community.',
      description:
          'Discover every Seventh-day Adventist church across Zimbabwe — '
          'with directions, services, and pastors at your fingertips.',
    ),
    _Slide(
      tag: 'EVENTS',
      icon: Icons.event_available_rounded,
      headline: 'Never miss\na gathering.',
      description:
          'RSVP to conferences, youth programs, and revival meetings near '
          'you — your spiritual calendar, always in tune.',
    ),
    _Slide(
      tag: 'MARKETPLACE',
      icon: Icons.storefront_rounded,
      headline: 'Trade within\na trusted circle.',
      description:
          'Buy and sell with verified members — health food, books, modest '
          'fashion, and more, all in one safe place.',
    ),
    _Slide(
      tag: 'OPPORTUNITY',
      icon: Icons.work_outline_rounded,
      headline: 'Build your\nfuture together.',
      description:
          'Discover jobs and opportunities shared by members and recruiters '
          'who walk the same path as you.',
    ),
    _Slide(
      tag: 'PRAYER',
      icon: Icons.volunteer_activism_rounded,
      headline: 'Carry each\nother in prayer.',
      description:
          'Lift up requests, intercede for one another, and witness how '
          'God moves through community.',
    ),
    _Slide(
      tag: 'CONNECT',
      icon: Icons.forum_rounded,
      headline: 'Fellowship,\nwherever you are.',
      description:
          'Message members, build prayer circles, and form lasting '
          'friendships rooted in Christ.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _startAutoAdvance();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoAdvance() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(const Duration(milliseconds: 5500), (_) {
      if (!mounted || _autoPaused) return;
      if (_index >= _slides.length - 1) {
        _autoTimer?.cancel();
        return;
      }
      _pageController.nextPage(
        duration: const Duration(milliseconds: 700),
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
    context.goNamed('login');
  }

  void _next() {
    HapticFeedback.selectionClick();
    if (_index >= _slides.length - 1) {
      _finish();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _index == _slides.length - 1;
    return Scaffold(
      backgroundColor: AppColors.lightGrey,
      body: GestureDetector(
        onTapDown: (_) => setState(() => _autoPaused = true),
        onTapUp: (_) => setState(() => _autoPaused = false),
        onTapCancel: () => setState(() => _autoPaused = false),
        child: SafeArea(
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
                    return _SlideView(
                      slide: _slides[i],
                      active: i == _index,
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              _buildProgress(),
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                child: _PrimaryButton(
                  label: isLast ? 'Get started' : 'Continue',
                  onTap: _next,
                ),
              ),
            ],
          ),
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
          // Real brand mark — the actual logo PNG so the pre-signup
          // intro slides match the launcher icon and splash logo.
          Container(
            width: 44,
            height: 44,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.28),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: Image.asset(
                'assets/icon/logo.png',
                fit: BoxFit.contain,
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
              child: Text(
                'Skip',
                style: AppTextStyles.labelMedium.copyWith(
                  color: const Color.fromRGBO(26, 26, 46, 0.55),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.4,
                ),
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
          final active = i <= _index;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              height: 4,
              decoration: BoxDecoration(
                color: active
                    ? AppColors.primaryBlue
                    : const Color.fromRGBO(26, 26, 46, 0.10),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// =============================================================================
// Slide
// =============================================================================

class _Slide {
  const _Slide({
    required this.tag,
    required this.icon,
    required this.headline,
    required this.description,
  });

  final String tag;
  final IconData icon;
  final String headline;
  final String description;
}

class _SlideView extends StatefulWidget {
  const _SlideView({required this.slide, required this.active});

  final _Slide slide;
  final bool active;

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
      duration: const Duration(milliseconds: 700),
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
    final tagAnim = _stage(0.0, 0.6);
    final iconAnim = _stage(0.1, 0.8);
    final headlineAnim = _stage(0.25, 0.9);
    final descAnim = _stage(0.4, 1.0);

    return AnimatedBuilder(
      animation: _entrance,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Opacity(
                opacity: tagAnim.value,
                child: Transform.translate(
                  offset: Offset(0, (1 - tagAnim.value) * 12),
                  child: _TagChip(text: widget.slide.tag),
                ),
              ),
              const SizedBox(height: 28),
              Opacity(
                opacity: iconAnim.value,
                child: Transform.scale(
                  scale: 0.92 + iconAnim.value * 0.08,
                  child: _HeroCard(icon: widget.slide.icon),
                ),
              ),
              const SizedBox(height: 40),
              Opacity(
                opacity: headlineAnim.value,
                child: Transform.translate(
                  offset: Offset(0, (1 - headlineAnim.value) * 16),
                  child: Text(
                    widget.slide.headline,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.displayLarge.copyWith(
                      color: AppColors.darkNavy,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1.18,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Opacity(
                opacity: descAnim.value,
                child: Transform.translate(
                  offset: Offset(0, (1 - descAnim.value) * 16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      widget.slide.description,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: const Color.fromRGBO(26, 26, 46, 0.62),
                        fontSize: 14.5,
                        height: 1.55,
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.goldAccent.withValues(alpha: 0.12),
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
            decoration: const BoxDecoration(
              color: AppColors.goldAccent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: AppTextStyles.labelSmall.copyWith(
              color: const Color(0xFF8A6E1F),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.8,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Hero card — a clean white circle with the icon, primary-blue
// gradient inside, soft drop shadow, gold rim. Same vibe as the auth
// screen's _LogoMark + the success screen's checkmark.
// =============================================================================

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft halo
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.22),
                  blurRadius: 36,
                  spreadRadius: 4,
                ),
              ],
            ),
          ),
          // Gold rim
          Container(
            width: 170,
            height: 170,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.goldAccent.withValues(alpha: 0.55),
                width: 1.4,
              ),
            ),
          ),
          // Primary-blue gradient disk with the icon
          Container(
            width: 148,
            height: 148,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.primaryGradient,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.30),
                  blurRadius: 20,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Center(
              child: Icon(icon, color: AppColors.white, size: 64),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Primary button — same gradient + shadow as AuthScreen for visual
// consistency across the entire auth journey.
// =============================================================================

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.32),
            blurRadius: 22,
            offset: const Offset(0, 12),
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
              children: [
                Text(
                  label,
                  style: AppTextStyles.buttonText.copyWith(
                    color: AppColors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: AppColors.white,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
