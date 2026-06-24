import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_bootstrap.dart';
import '../../services/auth_service.dart';
import '../../services/cache_service.dart';
import '../../services/secure_supabase_storage.dart';
import '../../services/biometric_service.dart';
import '../../services/force_update_service.dart';
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
  // >= the entrance animation duration. Previously 3200ms — the
  // user reported the splash dragged, so trimmed to ~1100ms (the
  // entrance fade finishes at 1800ms but the user can already see
  // logo+wordmark by ~900ms because of the staggered intervals).
  static const Duration _minLoaderDuration = Duration(milliseconds: 700);

  late final AnimationController _entrance;
  late final AnimationController _progress;
  // Reverse-only exit fader — runs immediately before we hand off to
  // onboarding / login / home so the splash dissolves into the next
  // screen instead of a hard cut. User reported the previous
  // transition felt abrupt.
  late final AnimationController _exit;
  // First-launch only: a richer "blossom" hand-off into onboarding
  // — logo scales up and brightens, wordmark + tagline lift away,
  // gradient flares before the route hand-off. Runs forward from 0
  // → 1 immediately before goNamed('onboarding'). For every other
  // destination (home / login / profile_setup) we use the plain
  // _exit fade instead so warm-start hand-offs stay snappy.
  late final AnimationController _blossom;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _wordmarkOpacity;
  late final Animation<double> _wordmarkSlide;
  late final Animation<double> _taglineOpacity;
  late final Animation<double> _blossomLogoScale;
  late final Animation<double> _blossomLogoFade;
  late final Animation<double> _blossomWordmarkLift;
  late final Animation<double> _blossomTaglineFade;
  late final Animation<double> _blossomBackgroundFade;

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

    _exit = AnimationController(
      vsync: this,
      value: 1.0,
      duration: const Duration(milliseconds: 320),
    );

    _blossom = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _blossomLogoScale = Tween<double>(begin: 1.0, end: 1.45).animate(
      CurvedAnimation(parent: _blossom, curve: Curves.easeInOutCubic),
    );
    _blossomLogoFade = CurvedAnimation(
      parent: _blossom,
      curve: const Interval(0.45, 1.0, curve: Curves.easeOut),
      reverseCurve: Curves.easeIn,
    );
    _blossomWordmarkLift = Tween<double>(begin: 0, end: -28).animate(
      CurvedAnimation(parent: _blossom, curve: Curves.easeOut),
    );
    _blossomTaglineFade = CurvedAnimation(
      parent: _blossom,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
    );
    _blossomBackgroundFade = CurvedAnimation(
      parent: _blossom,
      curve: const Interval(0.55, 1.0, curve: Curves.easeIn),
    );

    _navigate();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _progress.dispose();
    _exit.dispose();
    _blossom.dispose();
    super.dispose();
  }

  /// Fade the splash out, then perform the route hand-off so the new
  /// screen comes up underneath as the brand panel dissolves.
  Future<void> _fadeOutThen(VoidCallback go) async {
    await _exit.reverse();
    if (!mounted) return;
    go();
  }

  /// First-launch hand-off into onboarding. Logo scales up and
  /// brightens, wordmark + tagline lift away, then the white
  /// background fades — the onboarding screen blooms into view
  /// instead of cutting in. Longer + showier than [_fadeOutThen] on
  /// purpose: this is the first impression the user gets.
  Future<void> _blossomOutThen(VoidCallback go) async {
    await _blossom.forward();
    if (!mounted) return;
    go();
  }

  Future<void> _navigate() async {
    // Run the brand animation and the deferred Supabase init in
    // parallel — main.dart no longer awaits Supabase before runApp,
    // so we MUST wait for it here before the AuthService reads
    // below (they'd throw "Supabase has not been initialized").
    // Timebox the Supabase wait. initialize() restores the saved session
    // locally (fast) but then does a NETWORK token refresh that can hang
    // for many seconds on a slow connection — we must NOT block the splash
    // on that. After ~2.5s we proceed (the local session is already
    // restored, so routing is correct) and the refresh finishes in the
    // background while home paints from cache.
    // Kick the force-update check off the moment Supabase is ready so its
    // (fast, indexed) app_config query OVERLAPS the cache open + min-loader
    // window instead of adding ~1s to the splash tail. Fails open.
    final updateFuture = AppBootstrap.awaitSupabaseReady()
        .then((_) => ForceUpdateService.check())
        .catchError((_) => UpdateCheck.none);

    await Future.wait([
      Future.delayed(_minLoaderDuration),
      AppBootstrap.awaitSupabaseReady()
          .timeout(const Duration(milliseconds: 2500), onTimeout: () {}),
      // Cache box open (moved off the pre-runApp path). Timeboxed so a
      // large/slow box can't stall the splash — home tolerates no cache.
      CacheService.initialize()
          .timeout(const Duration(milliseconds: 1500), onTimeout: () {}),
    ]);
    if (!mounted) return;

    // Force-update gate (patch_091): below the hard floor — or past the
    // grace window for a newer build — block here before anything else.
    // A `recommended` result is stashed on ForceUpdateService.last so the
    // home screen can surface a dismissible "update available" nudge. The
    // check started above; cap the tail wait at 400ms so a dead network
    // (Supabase never became ready) can't stall the splash — fail open.
    final update = await updateFuture.timeout(
      const Duration(milliseconds: 400),
      onTimeout: () => UpdateCheck.none,
    );
    if (update.level == UpdateLevel.required) {
      if (!mounted) return;
      context.goNamed('update_required');
      return;
    }
    if (!mounted) return;

    // Decide signed-in from the PERSISTED session, not just the live one.
    // When the access token has expired, Supabase restores the session by
    // doing a NETWORK refresh first and only then exposes currentSession —
    // so on a slow network currentSession can still be null here even
    // though the user is logged in. Checking the persisted token (a local
    // secure-storage read) means a returning user is NEVER bounced to
    // login; the refresh finishes in the background.
    final signedIn =
        AuthService.isSignedIn || await SecureLocalStorage().hasAccessToken();
    if (!mounted) return;
    // Banned accounts hit a full lockout screen (backend already blocks
    // their actions via user_is_active()). Check the PERSISTED flag first so
    // a banned account is locked INSTANTLY + offline on every cold start —
    // even before the live session restores — and can't escape by killing
    // the app. The lockout screen re-checks the server and releases on unban.
    if (signedIn && await AuthService.isBannedLocally()) {
      if (!mounted) return;
      context.goNamed('account_banned');
      return;
    }
    // Refresh the server ban state in the BACKGROUND — don't block the
    // biometric prompt / home on a 3s network round-trip. The persisted flag
    // above already locks known-banned accounts instantly, and main.dart's
    // ban guard re-checks the server within seconds of launch + navigates to
    // the lockout screen if it flips. (This was the main "biometric login is
    // slow" cause: a slow network stalled the splash here before the prompt.)
    if (signedIn && AuthService.isSignedIn) {
      unawaited(AuthService.isCurrentUserBanned());
    }
    if (signedIn) {
      // WhatsApp-style biometric gate. If the user opted in, we hand
      // off to the dedicated lock screen instead of prompting + bailing
      // here — that way cancelling the OS prompt KEEPS the session
      // alive and just leaves the user staring at a Try-again screen
      // (the old behaviour signed them out, which everyone hated).
      // The lock screen itself routes onward to home / profile_setup
      // after a successful unlock.
      if (await BiometricService.isEnabled()) {
        if (!mounted) return;
        await _fadeOutThen(() => context.goNamed('biometric_lock'));
        return;
      }
      // Gate the home tab behind profile completion. A user can sign
      // up, start onboarding, kill the app halfway, then re-open — the
      // session still exists but their profile is empty. Sending them
      // to home in that state lets them bypass onboarding entirely. If
      // the session is still refreshing (no currentUser yet) we can't
      // read the metadata — a returning user with a persisted session has
      // already onboarded, so default to completed and go home.
      final completed = !AuthService.isSignedIn ||
          await AuthService.hasCompletedProfileSetup();
      if (!mounted) return;
      if (!completed) {
        await _fadeOutThen(() => context.goNamed('profile_setup'));
        return;
      }
      // Warm start → home: navigate directly instead of fading the splash
      // out first (which revealed a white frame — the "white thinking"
      // gap). Home paints instantly from its cache.
      context.goNamed('home');
      return;
    }

    final hasSeenOnboarding = await SecureStorageService.read(
          OnboardingScreen.onboardingFlagKey,
        ) ==
        'true';
    if (!mounted) return;

    if (!hasSeenOnboarding) {
      // First launch ever — celebrate it with the blossom hand-off
      // instead of the plain fade used for warm starts.
      await _blossomOutThen(() => context.goNamed('onboarding'));
      return;
    }

    if (!mounted) return;
    await _fadeOutThen(() => context.goNamed('login'));
  }

  @override
  Widget build(BuildContext context) {
    // Splash background follows the theme so dark-mode users don't get a
    // white flash on cold start (the wordmark/atmosphere read fine on the
    // deep-navy canvas too).
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: AnimatedBuilder(
        animation: Listenable.merge([_exit, _blossom]),
        builder: (context, child) {
          // _exit covers the warm-start hand-off (320ms fade). _blossom
          // is only driven for the first-launch onboarding path; on
          // every other path it stays at 0 so its effects are no-ops.
          final exitOpacity = Curves.easeOut.transform(_exit.value);
          final backgroundOpacity =
              exitOpacity * (1 - _blossomBackgroundFade.value);
          return Opacity(
            opacity: backgroundOpacity,
            child: child,
          );
        },
        child: DecoratedBox(
        decoration: BoxDecoration(color: AppColors.scaffold),
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
                    child: AnimatedBuilder(
                      animation: _blossom,
                      builder: (context, child) => Opacity(
                        opacity: 1 - _blossomTaglineFade.value,
                        child: child,
                      ),
                      child: Column(
                        children: [
                          // Single refined loader — the bouncing dots were
                          // dropped (redundant alongside the progress bar
                          // and part of the "busy / AI-generated" feel).
                          _buildProgressBar(),
                          const SizedBox(height: 18),
                          Text(
                            'MYTECH STUDIOS ZW',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.text.withValues(alpha: 0.35),
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 2.0,
                            ),
                          ),
                        ],
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
      animation: Listenable.merge([_entrance, _blossom]),
      builder: (context, _) {
        // Entrance does its scale/fade in; blossom overlays an extra
        // scale-up + fade-out during the first-launch hand-off.
        final opacity = _logoOpacity.value * (1 - _blossomLogoFade.value);
        final scale = _logoScale.value * _blossomLogoScale.value;
        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
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
      animation: Listenable.merge([_entrance, _blossom]),
      builder: (context, _) {
        final blossomT = _blossom.value;
        return Opacity(
          opacity: _wordmarkOpacity.value * (1 - blossomT),
          child: Transform.translate(
            offset: Offset(
              0,
              _wordmarkSlide.value + _blossomWordmarkLift.value,
            ),
            child: Text(
              'Advent Connect ZW',
              style: AppTextStyles.displayMedium.copyWith(
                // Navy on the light canvas; white on the dark-navy canvas —
                // hard-coded darkNavy was invisible navy-on-navy in dark mode.
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.white
                    : AppColors.darkNavy,
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
      animation: Listenable.merge([_entrance, _blossom]),
      builder: (context, _) {
        return Opacity(
          opacity: _taglineOpacity.value * (1 - _blossomTaglineFade.value),
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
