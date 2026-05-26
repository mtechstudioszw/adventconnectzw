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

    _progress = AnimationController(
      vsync: this,
      duration: _minLoaderDuration,
    )..forward();

    _navigate();
  }

  @override
  void dispose() {
    _entrance.dispose();
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
      // Gate the home tab behind profile completion. A user can sign
      // up, start onboarding, kill the app halfway, then re-open — the
      // session still exists but their profile is empty. Sending them
      // to home in that state lets them bypass onboarding entirely.
      // hasCompletedProfileSetup() checks profiles.username (the
      // authoritative "finished onboarding" flag — see auth_service).
      final completed = await AuthService.hasCompletedProfileSetup();
      if (!mounted) return;
      if (!completed) {
        context.goNamed('profile_setup');
        return;
      }
      context.goNamed('home');
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

    if (!mounted) return;
    context.goNamed('login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: DecoratedBox(
        decoration: const BoxDecoration(color: AppColors.white),
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
                    bottom: 30,
                    child: Column(
                      children: [
                        // Single refined loader — the bouncing dots were
                        // dropped (redundant alongside the progress bar
                        // and part of the "busy / AI-generated" feel).
                        _buildProgressBar(),
                        const SizedBox(height: 18),
                        Text(
                          'MTECH STUDIOS ZW',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.textDark.withValues(alpha: 0.35),
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
    // Subtle blue halo behind the emblem on the white canvas — gives
    // depth without the "busy" feel. Very low alpha so it reads as a
    // soft premium glow, not a gradient.
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.25),
            radius: 0.9,
            colors: [
              AppColors.primaryBlue.withValues(alpha: 0.06),
              AppColors.primaryBlue.withValues(alpha: 0.0),
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
            // The actual brand logo (assets/icon/logo.png) — same
            // image as the launcher icon so the splash → app handoff
            // feels continuous. The disc / ring / glow framing keeps
            // the premium feel on the white splash canvas.
            child: Container(
              width: 116,
              height: 116,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.primaryGradient,
                border: Border.all(
                  color: AppColors.goldAccent,
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.goldAccent.withValues(alpha: 0.30),
                    blurRadius: 28,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: AppColors.primaryBlue.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Image.asset(
                  'assets/icon/logo.png',
                  fit: BoxFit.contain,
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
                color: AppColors.darkNavy,
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
              color: AppColors.primaryBlue.withValues(alpha: 0.75),
              fontSize: 12,
              fontWeight: FontWeight.w600,
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
              color: AppColors.primaryBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: Curves.easeInOut.transform(_progress.value),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        AppColors.primaryBlue,
                        AppColors.goldAccent,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.goldAccent.withValues(alpha: 0.40),
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

}
