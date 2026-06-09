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
import 'services/connectivity_service.dart';
import 'services/messaging_service.dart';
import 'services/presence_service.dart';
import 'services/push_service.dart';
import 'services/theme_service.dart';
import 'theme/app_theme.dart';
import 'widgets/offline_banner.dart';
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

  // Cheap disk reads several services consume synchronously on first
  // build. Parallelised so the slowest one bounds total latency
  // instead of summing them. None of these depend on Supabase.
  await Future.wait([
    CacheService.initialize(),
    ConnectivityService.initialize(),
    AccountModeService.init(),
    ThemeService.init(),
  ]);

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

  // Mirror sign-in / sign-out into presence + analytics. Wired up here
  // (not inline in main) so it doesn't add to first-frame latency.
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    if (data.event == AuthChangeEvent.passwordRecovery) {
      appRouter.goNamed('reset_password');
    }
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

    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _backgroundedAt = DateTime.now();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _maybeRequireBiometric();
    }
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
  Widget build(BuildContext context) {
    // v1 launch: force light mode at the MaterialApp level. The
    // ThemeService toggle is still in place under the hood so the
    // v1.1 dark-mode update is a one-line revert here + un-hiding
    // the Settings row, but for now we hard-pin light so users can't
    // land on the ~45 unmigrated screens that still hard-code white
    // surfaces.
    return MaterialApp.router(
      title: 'Advent Connect ZW',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.light,
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
        ],
      ),
    );
  }
}
