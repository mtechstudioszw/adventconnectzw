import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
    with SingleTickerProviderStateMixin {
  final _pageController = PageController();
  Timer? _autoTimer;
  int _index = 0;
  bool _autoPaused = false;

  static const _slides = <_Slide>[
    _Slide(
      tag: 'CHURCHES',
      icon: Icons.church,
      headline: '2,600 SDA Churches',
      description:
          'Find and connect with Seventh-day Adventist churches across Zimbabwe.',
    ),
    _Slide(
      tag: 'EVENTS',
      icon: Icons.event_available,
      headline: 'Never Miss a Gathering',
      description:
          'RSVP to conferences, youth programs, and community events near you.',
    ),
    _Slide(
      tag: 'MARKETPLACE',
      icon: Icons.storefront,
      headline: 'Buy & Sell Safely',
      description: 'Trade within the trusted SDA community in Zimbabwe.',
    ),
    _Slide(
      tag: 'JOBS',
      icon: Icons.work_outline,
      headline: 'Find Opportunities',
      description:
          'Discover jobs posted by community members and recruiters.',
    ),
    _Slide(
      tag: 'PRAYER',
      icon: Icons.volunteer_activism,
      headline: 'Lift Each Other Up',
      description:
          'Share prayer requests and support one another in faith.',
    ),
    _Slide(
      tag: 'CONNECT',
      icon: Icons.chat_bubble_outline,
      headline: 'Stay Connected',
      description:
          'Message members and build lasting friendships in Christ.',
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
    _autoTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || _autoPaused) return;
      if (_index >= _slides.length - 1) {
        _autoTimer?.cancel();
        return;
      }
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<void> _finish() async {
    await SecureStorageService.write(
      OnboardingScreen.onboardingFlagKey,
      'true',
    );
    if (!mounted) return;
    context.goNamed('age_verification');
  }

  void _next() {
    if (_index >= _slides.length - 1) {
      _finish();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _index == _slides.length - 1;
    return Scaffold(
      body: GestureDetector(
        onTapDown: (_) => setState(() => _autoPaused = true),
        onTapUp: (_) => setState(() => _autoPaused = false),
        onTapCancel: () => setState(() => _autoPaused = false),
        child: Container(
          decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
          child: SafeArea(
            child: Column(
              children: [
                _buildTopBar(isLast),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _slides.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) {
                      return _SlideView(
                        slide: _slides[i],
                        active: i == _index,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                _buildDots(),
                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                  child: _buildPrimaryButton(isLast),
                ),
              ],
            ),
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
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.white.withValues(alpha: 0.12),
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.church,
                color: AppColors.goldAccent,
                size: 20,
              ),
            ),
          ),
          if (!isLast)
            TextButton(
              onPressed: _finish,
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: Text(
                'Skip',
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.white.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  letterSpacing: 0.6,
                ),
              ),
            )
          else
            const SizedBox(width: 56),
        ],
      ),
    );
  }

  Widget _buildDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_slides.length, (i) {
        final selected = i == _index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: selected ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.white
                : AppColors.white.withValues(alpha: 0.30),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  Widget _buildPrimaryButton(bool isLast) {
    final label = isLast ? 'Get started' : 'Next';
    return Container(
      decoration: BoxDecoration(
        color: isLast ? null : AppColors.white,
        gradient: isLast
            ? const LinearGradient(
                colors: [Color(0xFFC8A951), Color(0xFFD9BD6B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: (isLast
                    ? AppColors.goldAccent
                    : AppColors.white)
                .withValues(alpha: 0.30),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _next,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: AppTextStyles.buttonText.copyWith(
                    color:
                        isLast ? AppColors.darkNavy : AppColors.primaryBlue,
                    fontSize: 15,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  isLast ? Icons.arrow_forward : Icons.chevron_right,
                  color:
                      isLast ? AppColors.darkNavy : AppColors.primaryBlue,
                  size: isLast ? 18 : 22,
                ),
              ],
            ),
          ),
        ),
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
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slide = Tween<double>(begin: 16, end: 0).animate(
      CurvedAnimation(parent: _entrance, curve: Curves.easeOut),
    );
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _entrance,
      builder: (context, child) => Opacity(
        opacity: _fade.value,
        child: Transform.translate(
          offset: Offset(0, _slide.value),
          child: child,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildIcon(),
            const SizedBox(height: 40),
            Text(
              widget.slide.tag,
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.goldAccent,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.slide.headline,
              textAlign: TextAlign.center,
              style: AppTextStyles.displayMedium.copyWith(
                color: AppColors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              widget.slide.description,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyLarge.copyWith(
                color: AppColors.white.withValues(alpha: 0.78),
                fontSize: 16,
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon() {
    return Container(
      width: 180,
      height: 180,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.white.withValues(alpha: 0.08),
        border: Border.all(
          color: AppColors.white.withValues(alpha: 0.15),
          width: 1.5,
        ),
      ),
      child: Center(
        child: Container(
          width: 130,
          height: 130,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.white.withValues(alpha: 0.06),
            border: Border.all(
              color: AppColors.white.withValues(alpha: 0.18),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryBlue.withValues(alpha: 0.25),
                blurRadius: 40,
                spreadRadius: 8,
              ),
            ],
          ),
          child: Icon(
            widget.slide.icon,
            size: 60,
            color: AppColors.white,
          ),
        ),
      ),
    );
  }
}
