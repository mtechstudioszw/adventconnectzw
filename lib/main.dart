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

  // Cold-start path is split into "must finish before first paint"
  // vs "do in background after runApp". Sequential awaits add up —
  // splash used to drag because we serialised every disk read + the
  // Firebase native init even though most of them don't depend on
  // each other.

  // Phase 1: cheap disk reads that several services read SYNCHRONOUSLY
  // on first build. Parallelised so the slowest one bounds total
  // latency instead of summing them.
  await Future.wait([
    CacheService.initialize(),
    ConnectivityService.initialize(),
    AccountModeService.init(),
    ThemeService.init(),
  ]);

  // Phase 2: Supabase MUST be ready before the splash routes anywhere
  // (it reads currentUser to decide home vs login). Kept on the
  // critical path; everything else moves to the background.
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

class AdventConnectApp extends StatelessWidget {
  const AdventConnectApp({super.key});

  // Biometric resume re-prompt was wired here but is intentionally
  // disabled in this build per user direction (revisit ~2 months
  // post-launch). When re-enabling, restore the WidgetsBindingObserver
  // pattern from git history (commit 606a714) — it stamped a paused
  // timestamp and re-prompted on resume past a 2-minute threshold.

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
