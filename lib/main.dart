import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'config/router_config.dart';
import 'services/ads_service.dart';
import 'services/analytics_service.dart';
import 'services/cache_service.dart';
import 'services/connectivity_service.dart';
import 'services/push_service.dart';
import 'theme/app_theme.dart';
import 'widgets/offline_banner.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Offline cache + connectivity stream — must come up before any
  // service that wants to read cached payloads on cold start.
  await CacheService.initialize();
  await ConnectivityService.initialize();

  // AdMob — load the SDK early so the first banner request on the
  // home screen has the SDK ready when the screen mounts.
  await AdsService.initialize();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
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
  });

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

class AdventConnectApp extends StatelessWidget {
  const AdventConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Advent Connect ZW',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: appRouter,
      builder: (context, child) =>
          OfflineBanner(child: child ?? const SizedBox.shrink()),
    );
  }
}
