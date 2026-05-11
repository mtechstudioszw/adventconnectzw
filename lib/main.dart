import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'config/router_config.dart';
import 'services/push_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    if (data.event == AuthChangeEvent.passwordRecovery) {
      appRouter.goNamed('reset_password');
    }
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
    );
  }
}
