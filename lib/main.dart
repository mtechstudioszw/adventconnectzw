import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
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
import 'services/secure_supabase_storage.dart';
import 'services/theme_service.dart';
import 'theme/app_theme.dart';
import 'widgets/offline_banner.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Offline cache + connectivity stream — must come up before any
  // service that wants to read cached payloads on cold start.
  await CacheService.initialize();
  await ConnectivityService.initialize();
  // Drain any messages queued from the previous session and watch for
  // online transitions to retry. Outbox uses Hive, so this must come
  // after CacheService.initialize() (which runs Hive.initFlutter()).
  await MessagingService.startOutboxFlusher();

  // AdMob removed for v1 launch — re-add when monetization is wired up.

  // Read the user's last chosen view mode (personal / business). Cheap
  // disk read, must finish before the first widget builds because the
  // profile screen reads it synchronously.
  await AccountModeService.init();

  // Same — load the chosen ThemeMode (system/light/dark) before the
  // first build so we don't flash the wrong theme.
  await ThemeService.init();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
    // Persist sessions in flutter_secure_storage (per CLAUDE.md) so a
    // cold-start restores the user's session instead of bouncing them
    // back to the login screen every time they reopen the app.
    authOptions: FlutterAuthClientOptions(
      localStorage: SecureLocalStorage(),
      autoRefreshToken: true,
    ),
  );

  // Firebase initialise. Wrapped in a try so a missing/broken
  // google-services.json (e.g. before the developer has finished setup)
  // doesn't blow up the whole app — Supabase still works and the user
  // just doesn't get push.
  try {
    await Firebase.initializeApp();

    // Crashlytics — route Flutter framework + async errors here so a
    // null check or RenderFlex overflow in the field shows up in the
    // console instead of dying silently on a user's device.
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    AnalyticsService.markReady();
    await PushService.initialize();
    // Push taps deep-link into the source content. The mapping mirrors
    // notification_centre_screen._routeFor.
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
              appRouter.pushNamed('chat', pathParameters: {'id': id});
            }
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
    // Stay alive so the rest of the app still launches.
    debugPrint('Firebase init failed (push disabled): $e\n$st');
  }

  // Route password-recovery deep links straight to the reset screen.
  // Supabase fires this event when the user opens the link from their
  // recovery email, regardless of whether the app was already running.
  // Also keeps Analytics + Crashlytics user identity in sync.
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    if (data.event == AuthChangeEvent.passwordRecovery) {
      appRouter.goNamed('reset_password');
    }
    AnalyticsService.setUserId(data.session?.user.id);
    // Mirror sign-in / sign-out into the presence channel so other
    // users see "online" green dots and accurate last-seen times.
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

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.white,
    ),
  );

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const AdventConnectApp());
}

class AdventConnectApp extends StatefulWidget {
  const AdventConnectApp({super.key});

  @override
  State<AdventConnectApp> createState() => _AdventConnectAppState();
}

class _AdventConnectAppState extends State<AdventConnectApp>
    with WidgetsBindingObserver {
  /// Anything shorter than this is treated as "the user just glanced
  /// at something" and doesn't re-prompt for biometric unlock. The
  /// previous "fail if app left for 1 second" behaviour was caused
  /// by the absence of any threshold at all — we now require at
  /// least this long in the background before re-locking.
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
      // Stamp the moment the app went background. We compute the
      // away-time on resume and compare against _biometricThreshold.
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
    final awayFor = DateTime.now().difference(at);
    if (awayFor < _biometricThreshold) return;
    if (!AuthService.isSignedIn) return;
    final enabled = await BiometricService.isEnabled();
    if (!enabled) return;
    _biometricPromptInFlight = true;
    try {
      final ok = await BiometricService.authenticate(
        reason: 'Unlock Advent Connect ZW',
      );
      if (!ok) {
        // Failed (or cancelled) biometric → sign out + bounce to
        // login, same security model as the splash on cold start.
        await AuthService.signOut();
        if (!mounted) return;
        appRouter.goNamed('login');
      }
    } finally {
      _biometricPromptInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.notifier,
      builder: (context, mode, _) => MaterialApp.router(
        title: 'Advent Connect ZW',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode,
        routerConfig: appRouter,
        builder: (context, child) =>
            OfflineBanner(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
