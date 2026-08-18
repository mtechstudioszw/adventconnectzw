import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_bootstrap.dart';
import '../../services/auth_service.dart';
import '../../services/cache_service.dart';
import '../../services/secure_supabase_storage.dart';
import '../../services/biometric_service.dart';
import '../../services/force_update_service.dart';
import '../../services/maintenance_service.dart';
import '../../services/secure_storage_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../onboarding/onboarding_screen.dart';
import '../onboarding/widgets/film_scenes.dart'
    show AmbientPainter, GoldRingPainter;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.autoNavigate = true});

  /// Whether to run the boot + routing sequence on mount. True in the
  /// app. False lets a widget test exercise the brand panel's layout
  /// without a Supabase client, a cache box or a router behind it —
  /// _navigate()'s timeboxes otherwise leave pending timers. Same seam as
  /// [BiometricLockScreen.autoPrompt].
  final bool autoNavigate;

  /// The brand entrance / gold-ring duration. Exposed so a test can pin the
  /// rule that the boot wait never outlasts the animation the user is
  /// watching — that regression is invisible at runtime and only surfaces as
  /// "launch feels slow" weeks later.
  @visibleForTesting
  static Duration get brandDuration => _SplashScreenState._brandDuration;

  /// The longest the splash can hold the screen once the engine is up: the
  /// brand window, plus the update/maintenance gate cap, plus the exit fade.
  /// Excludes native launch and Flutter engine init, which this screen does
  /// not control.
  @visibleForTesting
  static Duration get worstCaseHoldMs =>
      _SplashScreenState._brandDuration +
      const Duration(milliseconds: 400) +
      _SplashScreenState._exitDuration;

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
  // Minimum brand dwell. 450ms is enough for the logo + ring entrance to
  // register (was 700ms) — on fast starts this is pure saved time, on
  // slow starts the Supabase/cache waits dominate anyway.
  static const Duration _minLoaderDuration = Duration(milliseconds: 450);

  /// How long the brand entrance runs — and, deliberately, the splash's
  /// whole boot budget.
  ///
  /// The gold ring sweeps on `_entrance` over the interval 0.30→1.0, so it
  /// closes around the emblem exactly at the end of this. Founder rule
  /// (16 Aug 2026): **when the ring finishes circling the logo, the splash
  /// goes into the app.** The ring is the visible promise about how long
  /// this screen lasts, so nothing behind it may outlast it.
  ///
  /// It is a CEILING, not a floor. A warm start still leaves at
  /// [_minLoaderDuration] — see the note there, and the standing rule that
  /// motion must never cost the user time. Cutting the ring short on a fast
  /// launch is the correct trade; making someone watch it finish is not.
  static const Duration _brandDuration = Duration(milliseconds: 1800);

  static const Duration _exitDuration = Duration(milliseconds: 320);

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

  /// The intro film's own light field, started here. Cold start → intro →
  /// auth is one continuous piece of motion: this screen holds the field
  /// at `film: 0` (its opening position), the onboarding film pans it
  /// across as the story runs, and AuthShell picks it up at `film: 1`.
  /// The old backdrop was a static radial blue wash that belonged to
  /// nothing else in the app.
  late final AnimationController _ambient;

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
      duration: _brandDuration,
    )..forward();

    // Not started here — didChangeDependencies owns that, because whether
    // a never-ending loop may run at all depends on MediaQuery's
    // "remove animations".
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );

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

    // The loader fills toward ~85% while the app actually boots (Supabase
    // session restore + cache open), then snaps to 100% the moment
    // _navigate() has everything it needs — so the bar reflects real
    // readiness instead of running on a fixed timer.
    _progress = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..animateTo(0.85, curve: Curves.easeOut);

    _exit = AnimationController(
      vsync: this,
      value: 1.0,
      duration: _exitDuration,
    );

    _blossom = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _blossomLogoScale = Tween<double>(
      begin: 1.0,
      end: 1.45,
    ).animate(CurvedAnimation(parent: _blossom, curve: Curves.easeInOutCubic));
    _blossomLogoFade = CurvedAnimation(
      parent: _blossom,
      curve: const Interval(0.45, 1.0, curve: Curves.easeOut),
      reverseCurve: Curves.easeIn,
    );
    _blossomWordmarkLift = Tween<double>(
      begin: 0,
      end: -28,
    ).animate(CurvedAnimation(parent: _blossom, curve: Curves.easeOut));
    _blossomTaglineFade = CurvedAnimation(
      parent: _blossom,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
    );
    _blossomBackgroundFade = CurvedAnimation(
      parent: _blossom,
      curve: const Interval(0.55, 1.0, curve: Curves.easeIn),
    );

    if (widget.autoNavigate) _navigate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.enabled(context)) {
      if (!_ambient.isAnimating) _ambient.repeat();
    } else {
      // "Remove animations": hold the light field on its opening frame
      // and land the brand entrance whole. The loader still runs — it
      // reports real boot progress, so it is information, not decoration.
      _ambient.stop();
      _entrance.value = 1;
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    _progress.dispose();
    _exit.dispose();
    _blossom.dispose();
    _ambient.dispose();
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

    // Maintenance mode, overlapped the same way and for the same reason —
    // it is one indexed app_config read, so running it beside the update
    // check costs nothing rather than adding a second round-trip to the
    // splash tail. Fails open (#22).
    // Budget is adaptive, not fixed — see [MaintenanceService.splashTimeout].
    // A device that was blocked the last time we got a real answer waits
    // longer for a definitive one, because letting it in and then locking it
    // 15 s later (the founder's "loads normally then locks") is worse than a
    // slightly slower splash for the few people already in an outage.
    // Everyone else keeps the original fast path, and it still fails open.
    final maintenanceFuture = AppBootstrap.awaitSupabaseReady()
        .then((_) =>
            MaintenanceService.check(timeout: MaintenanceService.splashTimeout))
        .catchError((_) => MaintenanceState.off);

    // Open the biometric platform channel NOW, while we are waiting on
    // Supabase and the cache box anyway. Without this the first
    // authenticate() call also pays for channel setup + hardware
    // enumeration, right at the moment the user is staring at the screen
    // waiting for a prompt. Fire-and-forget: it never gates anything.
    unawaited(BiometricService.prewarm());

    await Future.wait([
      Future.delayed(_minLoaderDuration),
      // Capped at the brand duration, NOT at some unrelated network budget.
      //
      // This was 2500ms, which is 700ms longer than the gold ring takes to
      // close. Add the gates and the exit fade and a slow-network launch sat
      // on the splash for ~3.2s — well past the point the animation had
      // visibly finished, which is precisely the "launch is slow" report.
      //
      // Waiting less here is safe, and the code below was already written
      // for it: `AppBootstrap.isReady` guards the Supabase-dependent read,
      // and the routing decision falls back to a persisted-token read that
      // needs no Supabase at all. Session restore from secure storage is the
      // fast part; the slow part is a NETWORK token refresh we explicitly do
      // not want to block on, and which finishes in the background while
      // home paints from cache.
      AppBootstrap.awaitSupabaseReady().timeout(
        _brandDuration,
        onTimeout: () {},
      ),
      // Cache box open (moved off the pre-runApp path). Timeboxed so a
      // large/slow box can't stall the splash — home tolerates no cache.
      CacheService.initialize().timeout(
        const Duration(milliseconds: 1500),
        onTimeout: () {},
      ),
    ]);
    if (!mounted) return;
    // Bootstrap is ready — complete the loader so it reads as "done" instead
    // of resting at a partial fill while we finish routing.
    _progress.animateTo(1.0, duration: const Duration(milliseconds: 220));

    // Both gates are waited for TOGETHER.
    //
    // They used to be awaited one after the other, 400ms each, so a device
    // that could not reach Supabase paid 800ms of pure tail — twice, for
    // two queries that were already running in parallel above. Waiting on
    // them at once caps the whole thing at 400ms. They are still CHECKED in
    // order below, because that order is a deliberate decision.
    final gates = await Future.wait([
      updateFuture.timeout(
        const Duration(milliseconds: 400),
        onTimeout: () => UpdateCheck.none,
      ),
      // 400 ms as before for everyone whose last answer was "not blocked" —
      // the splash stays exactly as fast. A device that WAS blocked last
      // time waits longer for a real answer, because for that device the
      // 400 ms cap is what produced "loads normally, then locks": it gave
      // up, failed open, and main.dart's 15 s poll locked it afterwards.
      maintenanceFuture.timeout(
        MaintenanceService.splashGateTimeout,
        onTimeout: () => MaintenanceState.off,
      ),
    ]);
    if (!mounted) return;

    // Force-update gate (patch_091): below the hard floor — or past the
    // grace window for a newer build — block here before anything else.
    // A `recommended` result is stashed on ForceUpdateService.last so the
    // home screen can surface a dismissible "update available" nudge.
    final update = gates[0] as UpdateCheck;
    if (update.level == UpdateLevel.required) {
      context.goNamed('update_required');
      return;
    }

    // Maintenance gate. AFTER the update gate on purpose: if a member is on
    // a build that must be replaced, telling them that is more useful than
    // telling them to come back later.
    final maintenance = gates[1] as MaintenanceState;
    // `blocked`, not `active`: super admins are exempt server-side so they can
    // fix whatever the maintenance is for, and gating them out of their own
    // app would defeat that.
    if (maintenance.blocked) {
      if (!mounted) return;
      context.goNamed('maintenance');
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
    //
    // `AppBootstrap.isReady` guards the first half. The wait above has an
    // `onTimeout` that swallows, so on a slow device we can arrive here
    // with Supabase still initialising — and `AuthService.isSignedIn`
    // resolves `Supabase.instance.client`, which THROWS in that state.
    // `_navigate` is unawaited, so the throw vanished into an unhandled
    // future and the splash never navigated at all. The persisted-token
    // read below answers the question on its own.
    final signedIn =
        (AppBootstrap.isReady && AuthService.isSignedIn) ||
        await SecureLocalStorage().hasAccessToken();
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
    if (signedIn && AppBootstrap.isReady && AuthService.isSignedIn) {
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
        // Navigate DIRECTLY — no 320ms fade first. The unlock path is the
        // one a returning user walks every single launch, and the founder's
        // note was that it feels slow next to WhatsApp. A fade here is
        // 320ms of nothing standing between the user and the OS prompt,
        // and the lock screen paints on the same ambient backdrop the
        // splash is already showing, so there is no visual cut to soften.
        // (The warm-start → home path already skips the fade for the same
        // reason.)
        context.goNamed('biometric_lock');
        return;
      }
      // Gate the home tab behind profile completion. A user can sign
      // up, start onboarding, kill the app halfway, then re-open — the
      // session still exists but their profile is empty. Sending them
      // to home in that state lets them bypass onboarding entirely. If
      // the session is still refreshing (no currentUser yet) we can't
      // read the metadata — a returning user with a persisted session has
      // already onboarded, so default to completed and go home.
      final completed =
          !AppBootstrap.isReady ||
          !AuthService.isSignedIn ||
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

    final hasSeenOnboarding =
        await SecureStorageService.read(OnboardingScreen.onboardingFlagKey) ==
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
    // deep-navy canvas too). Read from the palette, which is the same
    // value AuthShell and the onboarding film use — the hand-off between
    // them must not show a seam.
    final scaffoldBg = context.palette.scaffoldBg;
    return Scaffold(
      backgroundColor: scaffoldBg,
      body: AnimatedBuilder(
        animation: Listenable.merge([_exit, _blossom]),
        builder: (context, child) {
          // _exit covers the warm-start hand-off (320ms fade). _blossom
          // is only driven for the first-launch onboarding path; on
          // every other path it stays at 0 so its effects are no-ops.
          final exitOpacity = Curves.easeOut.transform(_exit.value);
          final backgroundOpacity =
              exitOpacity * (1 - _blossomBackgroundFade.value);
          return Opacity(opacity: backgroundOpacity, child: child);
        },
        child: DecoratedBox(
          decoration: BoxDecoration(color: scaffoldBg),
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
                            // The mission, not the maker. This line is the
                            // last thing read before the app opens, and a
                            // personal name there tells a new member
                            // nothing about what they just installed.
                            // Founder's call, 18 Aug 2026.
                            Text(
                              'Connecting Adventists all over the world',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.labelSmall.copyWith(
                                color: AppColors.text.withValues(alpha: 0.45),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.3,
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
    // The intro film's ambient field rather than a bespoke radial wash.
    // `film: 0` is its opening position — the onboarding film pans it
    // across as the story runs and AuthShell resumes it at `film: 1`, so
    // the light the user sees on the very first frame of a cold start is
    // literally the same light that is still behind the sign-in form.
    // Own repaint layer so the brand mark above never re-rasterises with
    // it.
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _ambient,
          builder: (context, _) => CustomPaint(
            painter: AmbientPainter(
              loop: _ambient.value,
              film: 0,
              dark: Theme.of(context).brightness == Brightness.dark,
            ),
            child: const SizedBox.expand(),
          ),
        ),
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
        // The gold ring draws itself around the emblem as it lands —
        // the same ring motif that runs through the intro film, the
        // unlock screen and the Sabbath timer.
        final ringSweep = const Interval(
          0.30,
          1.0,
          curve: Curves.easeInOutCubic,
        ).transform(_entrance.value);
        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            // The actual brand logo (assets/icon/logo.png) — same
            // image as the launcher icon so the splash → app handoff
            // feels continuous. The disc / ring / glow framing keeps
            // the premium feel on the white splash canvas.
            child: SizedBox(
              width: 148,
              height: 148,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(148, 148),
                    painter: GoldRingPainter(sweep: ringSweep, strokeWidth: 3),
                  ),
                  Container(
                    width: 116,
                    height: 116,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.primaryGradient,
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
                      // cacheWidth, and it matters more here than anywhere.
                      //
                      // logo.png is 3264×3264 — about 42MB once decoded to
                      // RGBA — and it is drawn into 88 logical pixels. Every
                      // launch decoded the full bitmap on the UI isolate
                      // before the splash could show its own logo, and on a
                      // low-RAM phone that allocation is a stall of its own.
                      // 3× the largest drawn size is plenty for any density.
                      child: Image.asset(
                        'assets/icon/logo.png',
                        fit: BoxFit.contain,
                        cacheWidth: 264,
                      ),
                    ),
                  ),
                ],
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
              // Two deliberate lines. At 32px w700 the name measures ~370px,
              // wider than a 360dp screen, so a single Text auto-wraps to a
              // broken "Adventist Super / App". Stacked, it reads as a
              // proper wordmark lockup under the emblem.
              'Adventist\nSuper App',
              textAlign: TextAlign.center,
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
            'COMMUNITY  •  FAITH  •  WORLDWIDE',
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
                      colors: [AppColors.primaryBlue, AppColors.goldAccent],
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
