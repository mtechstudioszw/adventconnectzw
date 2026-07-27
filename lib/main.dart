import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/app_bootstrap.dart';
import 'config/router_config.dart';
import 'services/account_mode_service.dart';
import 'services/analytics_service.dart';
import 'services/auth_service.dart';
import 'services/biometric_service.dart';
import 'services/cache_service.dart';
import 'services/ads/ads_service.dart';
import 'services/ads/app_open_ad_manager.dart';
import 'services/connectivity_service.dart';
import 'services/deep_link_service.dart';
import 'services/messaging_service.dart';
import 'services/music_player_service.dart';
import 'services/presence_service.dart';
import 'services/push_service.dart';
import 'services/theme_service.dart';
import 'theme/app_text_styles.dart';
import 'theme/app_theme.dart';
import 'widgets/offline_banner.dart';
import 'widgets/global_media_bars.dart';
import 'widgets/voice_mini_bar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Tap-to-splash latency is dominated by what runs BEFORE runApp.
  // Supabase.initialize() reads + decrypts the persisted session via
  // flutter_secure_storage; on Android cold start that keychain hop
  // is 300–700ms. We kick it off here without awaiting so the
  // Flutter splash paints immediately. The splash awaits this same
  // future inside _navigate() before any auth.currentUser read.
  unawaited(AppBootstrap.startSupabaseInit());

  // Cheap LOCAL reads the MaterialApp/theme need before the first frame.
  // Kept tiny so the splash paints almost immediately.
  await Future.wait([
    ConnectivityService.initialize(),
    AccountModeService.init(),
    ThemeService.init(),
    // Media session for the Library music player + Audio Bible. MUST finish
    // before the first AudioPlayer is constructed, otherwise just_audio
    // throws "_audioHandler has not been initialized" and music won't play —
    // the exact failure that got background playback removed last time.
    // MusicPlayerService builds its player lazily so nothing can touch it
    // before this resolves, and ensureInitialized is timeboxed + never
    // throws, so a failure here degrades to plain in-app playback instead of
    // blocking startup.
    MusicPlayerService.ensureInitialized(),
  ]);

  // CacheService opens a Hive box (reads the WHOLE box into memory). If it
  // ever grew large that openBox blocked the first frame for many seconds
  // (the "navy screen for ~13s" symptom). Move it OFF the critical path —
  // the splash awaits it (timeboxed) before routing home, and every cache
  // read already tolerates a not-yet-open box.
  unawaited(CacheService.initialize());

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.white,
    ),
  );

  // Don't block the first frame on the orientation lock — it has no
  // effect on the splash render either way and just adds a hop to
  // the platform channel.
  unawaited(SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]));

  runApp(const AdventConnectApp());

  // Anything that doesn't gate the splash's routing decision happens
  // here. The splash sits on a ~1100ms brand animation; by the time it
  // pops these are usually done, but if not the app still works (push
  // just registers a few seconds later, outbox flushes when the user
  // hits home).
  unawaited(_initBackgroundServices());
}

Future<void> _initBackgroundServices() async {
  // Auth-listener setup + outbox flusher both touch Supabase, so wait
  // until init finishes before wiring them up.
  await AppBootstrap.awaitSupabaseReady();

  // Outbox flusher needs Hive from Phase 1 above. Fire and forget.
  unawaited(MessagingService.startOutboxFlusher());

  // AdMob: gather EU consent + initialise the SDK off the critical path
  // so the first frame isn't blocked. Ad widgets check AdsService.isReady.
  // Once ready, warm an App-Open ad for the next resume.
  unawaited(AdsService.init().then((_) => AppOpenAdManager.loadAd()));

  // Inbound deep links (shared event / product / job / seller links from
  // the *-share Edge Functions). Routes via the same appRouter the push
  // handler below uses. Fire and forget — it handles the cold-start link
  // internally once the splash has routed.
  unawaited(DeepLinkService.initialize());

  // Mirror sign-in / sign-out into presence + analytics. Wired up here
  // (not inline in main) so it doesn't add to first-frame latency.
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    // NOTE: we deliberately do NOT navigate on AuthChangeEvent.passwordRecovery.
    // Password reset is now an in-app 6-digit-code flow (ResetPasswordScreen in
    // OTP mode) that verifies the code + sets the new password itself. The
    // recovery event fires as a side effect of verifyOTP — auto-routing to the
    // reset screen here pushed the user to a SECOND (legacy) "new password"
    // screen that then errored because we'd already updated + signed out.
    AnalyticsService.setUserId(data.session?.user.id);
    switch (data.event) {
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.initialSession:
      case AuthChangeEvent.tokenRefreshed:
        if (data.session?.user != null) {
          unawaited(PresenceService.start());
        }
        break;
      case AuthChangeEvent.signedOut:
        unawaited(PresenceService.stop());
        break;
      default:
        break;
    }
  });

  // Kick off presence immediately if we already have a session (warm
  // start). The auth-state listener above also covers later sign-ins.
  if (Supabase.instance.client.auth.currentUser != null) {
    unawaited(PresenceService.start());
  }

  // Firebase + Crashlytics + Push. Wrapped in a try so a missing /
  // broken google-services.json doesn't kill the whole app — Supabase
  // still works and the user just doesn't get push.
  try {
    await Firebase.initializeApp();

    // Transient network / auth-retry failures (no connection, DNS blip,
    // Supabase token-refresh retry) are NOT real crashes — record them as
    // non-fatal so they don't dominate Crashlytics' "trending crashes" or
    // trigger false stability alerts (e.g. the GotrueFetch AuthRetryable
    // reports). Everything else stays fatal.
    bool isTransientNetwork(Object error) {
      final t = error.runtimeType.toString();
      final s = error.toString();
      return t.contains('AuthRetryableFetchException') ||
          t.contains('SocketException') ||
          t.contains('TimeoutException') ||
          t.contains('ClientException') ||
          t.contains('HandshakeException') ||
          s.contains('Failed host lookup') ||
          s.contains('Connection closed') ||
          s.contains('Connection reset') ||
          s.contains('Software caused connection abort');
    }

    FlutterError.onError = (details) {
      FirebaseCrashlytics.instance.recordFlutterError(
        details,
        fatal: !isTransientNetwork(details.exception),
      );
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        fatal: !isTransientNetwork(error),
      );
      return true;
    };

    AnalyticsService.markReady();
    await PushService.initialize();
    PushService.onMessageTap.listen((msg) {
      final type = (msg.data['reference_type'] ?? '').toString();
      final id = (msg.data['reference_id'] ?? '').toString();
      try {
        switch (type) {
          case 'event':
            if (id.isNotEmpty) {
              appRouter.pushNamed('event_details', pathParameters: {'id': id});
            }
            break;
          case 'prayer':
            if (id.isNotEmpty) {
              appRouter.pushNamed('prayer_details', pathParameters: {'id': id});
            }
            break;
          case 'conversation':
            if (id.isNotEmpty) {
              // Tap-to-open flow: mark every undelivered incoming
              // message in this conversation as delivered before
              // navigating, so the sender's tick goes double at the
              // moment of tap (not after the chat screen mounts +
              // runs its own per-message mark-delivered pass). The
              // foreground handler already runs this for pushes that
              // land while the app is open; this branch covers
              // taps from system tray / killed state.
              unawaited(MessagingService.markConversationDelivered(id));
              appRouter.pushNamed('chat', pathParameters: {'id': id});
            }
            break;
          case 'friend_request':
            appRouter.pushNamed(
              'messages',
              queryParameters: {'tab': 'requests'},
            );
            break;
          case 'seller':
            appRouter.pushNamed('seller_dashboard');
            break;
          case 'church_admin':
            appRouter.pushNamed('admin_login');
            break;
          case 'video':
            // YouTube live / new-upload push → open the in-app player.
            if (id.isNotEmpty) {
              appRouter.pushNamed('watch_video', pathParameters: {'id': id});
            }
            break;
          default:
            appRouter.pushNamed('notification_centre');
        }
      } catch (e, st) {
        debugPrint('Push deep-link failed for $type/$id: $e\n$st');
      }
    });
  } catch (e, st) {
    debugPrint('Firebase init failed (push disabled): $e\n$st');
  }
}

class AdventConnectApp extends StatefulWidget {
  const AdventConnectApp({super.key});

  @override
  State<AdventConnectApp> createState() => _AdventConnectAppState();
}

class _AdventConnectAppState extends State<AdventConnectApp>
    with WidgetsBindingObserver {
  // Anything shorter than this is treated as the user glancing at
  // another app (e.g. tapping a notification or copying a 2FA code)
  // and doesn't re-prompt biometric. Without a threshold every brief
  // backgrounding would lock the user out, which they reported as
  // unusable in a previous build.
  static const _biometricThreshold = Duration(minutes: 2);

  DateTime? _backgroundedAt;
  bool _biometricPromptInFlight = false;

  // Reactive ban guard. The cold-start check in Splash only fires once, so a
  // user banned WHILE the app is open saw nothing until they killed + relaunched
  // (the tester report: "the block screen doesn't appear when banned"). We poll
  // the account's ban flag on a short interval + immediately on resume and slam
  // the lockout screen the moment it flips. Fails open, so a network blip never
  // locks out a good user.
  static const _banPollInterval = Duration(seconds: 30);
  Timer? _banPollTimer;
  bool _banCheckInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startBanGuard();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _banPollTimer?.cancel();
    super.dispose();
  }

  void _startBanGuard() {
    _banPollTimer?.cancel();
    _banPollTimer =
        Timer.periodic(_banPollInterval, (_) => unawaited(_checkBanNow()));
    // First sweep shortly after launch, once the session has had a moment to
    // restore on a slow network.
    Future.delayed(const Duration(seconds: 4), () => unawaited(_checkBanNow()));
  }

  Future<void> _checkBanNow() async {
    if (_banCheckInFlight) return;
    if (!AuthService.isSignedIn) return;
    // Already locked out — nothing to do.
    final loc = appRouter.routerDelegate.currentConfiguration.uri.path;
    if (loc == '/account-banned' || loc == '/splash') return;
    _banCheckInFlight = true;
    try {
      if (await AuthService.isCurrentUserBanned()) {
        final now = appRouter.routerDelegate.currentConfiguration.uri.path;
        if (now != '/account-banned') appRouter.goNamed('account_banned');
      }
    } finally {
      _banCheckInFlight = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _backgroundedAt = DateTime.now();
      // Go offline + stop the heartbeat when truly backgrounded, so the
      // green dot and "last seen" stop lying (the user shows online and
      // their last-seen kept advancing while the app was actually closed).
      if (state == AppLifecycleState.paused) {
        unawaited(PresenceService.stop(clearRoster: false));
        _banPollTimer?.cancel();
      }
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _maybeRequireBiometric();
      // Re-arm the ban guard + check immediately — the admin may have banned
      // this account while the app was backgrounded.
      _startBanGuard();
      // Returning to the app — flip any messages that arrived while we
      // were away to delivered, so senders' ticks update even if we don't
      // open Chats (patch_062).
      unawaited(MessagingService.markAllIncomingDelivered());
      // Rejoin presence (online again + heartbeat resumes).
      if (AuthService.isSignedIn) unawaited(PresenceService.start());
      // App-Open ad on return-to-foreground (capped once / 3h), but never
      // over a sensitive flow — Advent Chat, prayer, auth/onboarding,
      // splash/lock, banned/update, admin.
      _maybeShowAppOpenAd();
    }
  }

  // Routes where a full-screen App-Open ad must NOT appear.
  static const _appOpenBlockedPrefixes = <String>[
    '/messages', // Advent Chat (inbox + conversations)
    '/prayer',
    '/splash',
    '/biometric-lock',
    '/onboarding',
    '/login',
    '/signup',
    '/email-verification',
    '/profile-setup',
    '/forgot-password',
    '/reset-password',
    '/account-banned',
    '/update-required',
    '/admin',
    // Browsing/opening a church, event or product must not trigger a
    // full-screen App-Open ad on resume — the tester hit an unskippable ad
    // every time they tapped one of these. Revenue stays on the home feed +
    // stories.
    '/marketplace',
    '/events',
    '/churches',
    '/library',
    '/news',
  ];

  void _maybeShowAppOpenAd() {
    if (!AuthService.isSignedIn) return;
    final loc = appRouter.routerDelegate.currentConfiguration.uri.path;
    final blocked =
        _appOpenBlockedPrefixes.any((prefix) => loc.startsWith(prefix));
    if (blocked) {
      // Still keep one warm for when they land somewhere it's allowed.
      AppOpenAdManager.loadAd();
      return;
    }
    unawaited(AppOpenAdManager.showIfReady());
  }

  Future<void> _maybeRequireBiometric() async {
    if (_biometricPromptInFlight) return;
    final at = _backgroundedAt;
    _backgroundedAt = null;
    if (at == null) return;
    if (DateTime.now().difference(at) < _biometricThreshold) return;
    if (!AuthService.isSignedIn) return;
    if (!await BiometricService.isEnabled()) return;
    // Don't double-prompt if the lock screen is already on top — that
    // would chain two OS dialogs and confuse the user.
    final loc = appRouter.routerDelegate.currentConfiguration.uri.path;
    if (loc.startsWith('/biometric-lock') || loc == '/splash') return;
    _biometricPromptInFlight = true;
    try {
      // WhatsApp-style: navigate to the dedicated lock screen and let
      // IT drive the prompt + Try-again loop. The session stays alive
      // on cancel — no more accidental sign-outs.
      appRouter.goNamed('biometric_lock');
    } finally {
      _biometricPromptInFlight = false;
    }
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    // If we're following the system theme, rebuild so AppTextStyles /
    // AppColors re-resolve when the user flips their device dark mode.
    if (ThemeService.current == ThemeMode.system && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Theme follows the user's saved choice (Settings → Appearance).
    // ThemeService.init() ran before runApp so the first frame is already
    // correct; the ValueListenableBuilder repaints the whole app the instant
    // the toggle changes, with AppPalette lerping the surfaces.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.notifier,
      builder: (context, mode, _) {
        // Resolve the active brightness and point AppTextStyles at it BEFORE
        // MaterialApp builds its routes, so the hundreds of direct
        // `AppTextStyles.*` usages render light text in dark mode.
        final brightness = mode == ThemeMode.dark
            ? Brightness.dark
            : mode == ThemeMode.light
                ? Brightness.light
                : PlatformDispatcher.instance.platformBrightness;
        AppTextStyles.applyBrightness(brightness);
        return MaterialApp.router(
          title: 'Advent Connect ZW',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          // Smooth crossfade when the user flips Light/Dark instead of an
          // abrupt 1-frame snap (the "glitch"). MaterialApp's built-in
          // AnimatedTheme lerps every themed colour over this window.
          themeAnimationDuration: const Duration(milliseconds: 400),
          themeAnimationCurve: Curves.easeInOut,
          routerConfig: appRouter,
          builder: (context, child) => Stack(
            children: [
              OfflineBanner(child: child ?? const SizedBox.shrink()),
              // Global voice-note bar — shows at the top whenever a note plays
              // outside its own chat (WhatsApp parity).
              const Align(
                alignment: Alignment.topCenter,
                child: VoiceMiniBar(),
              ),
              // Docked video + music bars — whatever is still playing stays
              // reachable from anywhere, above the navigation island.
              const Align(
                alignment: Alignment.bottomCenter,
                child: GlobalMediaBars(),
              ),
            ],
          ),
        );
      },
    );
  }
}
