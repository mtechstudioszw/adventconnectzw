import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../../services/secure_storage_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../onboarding/onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Keep the loader visible for at least this long so the brand
  // animation lands and the loading bar can run end-to-end. Must be
  // >= the progress bar duration below.
  static const Duration _minLoaderDuration = Duration(milliseconds: 3200);

  late final AnimationController _entrance;
  late final AnimationController _dots;
  late final AnimationController _progress;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _wordmarkOpacity;
  late final Animation<double> _wordmarkSlide;
  late final Animation<double> _taglineOpacity;

  @override
  void initState() {
    super.initState();

    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..forward();

    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _entrance,
        curve: const Interval(0.0, 0.35, curve: Curves.easeOutBack),
      ),
    );
    _logoOpacity = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
    );
    _wordmarkOpacity = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.15, 0.35, curve: Curves.easeOut),
    );
    _wordmarkSlide = Tween<double>(begin: 16, end: 0).animate(
      CurvedAnimation(
        parent: _entrance,
        curve: const Interval(0.15, 0.35, curve: Curves.easeOut),
      ),
    );
    _taglineOpacity = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.30, 0.50, curve: Curves.easeOut),
    );

    _dots = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _progress = AnimationController(
      vsync: this,
      duration: _minLoaderDuration,
    )..forward();

    _navigate();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _dots.dispose();
    _progress.dispose();
    super.dispose();
  }

  Future<void> _navigate() async {
    await Future.delayed(_minLoaderDuration);
    if (!mounted) return;

    if (AuthService.isSignedIn) {
      // If the user opted into biometric quick-unlock from Settings,
      // gate access to the app behind a fingerprint/Face ID prompt.
      // Failure to authenticate signs them out so the next person on
      // the device can't see their data.
      final biometricEnabled = await BiometricService.isEnabled();
      if (biometricEnabled) {
        final ok = await BiometricService.authenticate(
          reason: 'Unlock Advent Connect ZW',
        );
        if (!mounted) return;
        if (!ok) {
          await AuthService.signOut();
          if (!mounted) return;
          context.goNamed('login');
          return;
        }
      }
      final ageVerified = await AuthService.isAgeVerified();
      if (!mounted) return;
      context.goNamed(ageVerified ? 'home' : 'age_verification');
      return;
    }

    final hasSeenOnboarding = await SecureStorageService.read(
          OnboardingScreen.onboardingFlagKey,
        ) ==
        'true';
    if (!mounted) return;

    if (!hasSeenOnboarding) {
      context.goNamed('onboarding');
      return;
    }

    final ageVerified = await AuthService.isAgeVerified();
    if (!mounted) return;
    context.goNamed(ageVerified ? 'login' : 'age_verification');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        child: Stack(
          children: [
            _buildAtmosphereOverlay(),
            SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildLogoTile(),
                        const SizedBox(height: 28),
                        _buildWordmark(),
                        const SizedBox(height: 12),
                        _buildTagline(),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 24,
                    child: Column(
                      children: [
                        _buildProgressBar(),
                        const SizedBox(height: 14),
                        _buildDots(),
                        const SizedBox(height: 16),
                        Text(
                          'MTECH STUDIOS ZW',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.white.withValues(alpha: 0.35),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 2.0,
                          ),
                        ),
                      ],
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

  Widget _buildAtmosphereOverlay() {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.25),
            radius: 0.9,
            colors: [
              AppColors.white.withValues(alpha: 0.06),
              AppColors.white.withValues(alpha: 0.0),
            ],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _buildLogoTile() {
    return AnimatedBuilder(
      animation: _entrance,
      builder: (context, _) {
        return Opacity(
          opacity: _logoOpacity.value,
          child: Transform.scale(
            scale: _logoScale.value,
            child: Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: AppColors.white.withValues(alpha: 0.12),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryBlue.withValues(alpha: 0.30),
                    blurRadius: 24,
                    spreadRadius: 1,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.church,
                  size: 48,
                  color: AppColors.goldAccent,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWordmark() {
    return AnimatedBuilder(
      animation: _entrance,
      builder: (context, _) {
        return Opacity(
          opacity: _wordmarkOpacity.value,
          child: Transform.translate(
            offset: Offset(0, _wordmarkSlide.value),
            child: Text(
              'Advent Connect ZW',
              style: AppTextStyles.displayMedium.copyWith(
                color: AppColors.white,
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                height: 1.1,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTagline() {
    return AnimatedBuilder(
      animation: _entrance,
      builder: (context, _) {
        return Opacity(
          opacity: _taglineOpacity.value,
          child: Text(
            'COMMUNITY  •  FAITH  •  ZIMBABWE',
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.white.withValues(alpha: 0.65),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 2.4,
            ),
          ),
        );
      },
    );
  }

  Widget _buildProgressBar() {
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, _) {
        return Center(
          child: Container(
            width: 140,
            height: 3,
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: Curves.easeInOut.transform(_progress.value),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.goldAccent.withValues(alpha: 0.85),
                        AppColors.white.withValues(alpha: 0.95),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.goldAccent.withValues(alpha: 0.45),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDots() {
    return AnimatedBuilder(
      animation: _dots,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            final phase = (_dots.value - i * 0.18) % 1.0;
            final wave = phase < 0.5
                ? phase * 2
                : (1.0 - phase) * 2;
            final alpha = 0.25 + (0.75 * wave.clamp(0.0, 1.0));
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.white.withValues(alpha: alpha),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
