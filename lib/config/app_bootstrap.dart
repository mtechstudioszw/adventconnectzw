import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/secure_supabase_storage.dart';
import 'supabase_config.dart';

/// Cold-start bootstrap for Supabase.
///
/// The Supabase SDK reads + decrypts the persisted session from
/// `flutter_secure_storage` during `initialize()`. On Android the
/// keychain hop adds 300–700ms to the first frame because main()
/// used to `await` it before runApp. We now kick it off here
/// without awaiting so the splash paints immediately, then the
/// splash awaits this future before reading `auth.currentUser`.
class AppBootstrap {
  AppBootstrap._();

  static Future<void>? _supabaseReady;

  /// Starts Supabase.initialize. Idempotent — repeat calls return
  /// the same in-flight future. Call once from main() before runApp.
  static Future<void> startSupabaseInit() {
    return _supabaseReady ??= Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
      authOptions: FlutterAuthClientOptions(
        localStorage: SecureLocalStorage(),
        autoRefreshToken: true,
      ),
    );
  }

  /// Resolves once Supabase is fully initialized. Splash awaits this
  /// before AuthService.isSignedIn / currentUser reads.
  static Future<void> awaitSupabaseReady() async {
    final ready = _supabaseReady;
    if (ready == null) {
      // Defensive fallback — kicks it off if main() somehow didn't.
      await startSupabaseInit();
      return;
    }
    await ready;
  }
}
