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

  /// True once [startSupabaseInit] has actually completed.
  ///
  /// Callers that time out waiting for [awaitSupabaseReady] MUST check
  /// this before touching `Supabase.instance.client`. That getter throws
  /// when init has not finished, and the splash's wait has an
  /// `onTimeout` that swallows — so on a device with a slow keystore the
  /// next line threw into an unawaited future and the splash simply never
  /// navigated. An infinite splash, not a slow one.
  static bool _isReady = false;
  static bool get isReady => _isReady;

  /// Starts Supabase.initialize. Idempotent — repeat calls return
  /// the same in-flight future. Call once from main() before runApp.
  ///
  /// [autoRefreshToken] MUST be false anywhere that is not the app's own UI
  /// isolate. See [startSupabaseInitForBackgroundIsolate] for why — it is
  /// the difference between a delivery tick being late and the member being
  /// signed out.
  static Future<void> startSupabaseInit({bool autoRefreshToken = true}) {
    return _supabaseReady ??= Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
      authOptions: FlutterAuthClientOptions(
        localStorage: SecureLocalStorage(),
        autoRefreshToken: autoRefreshToken,
      ),
    ).then((_) => _isReady = true);
  }

  /// Supabase for the FCM background isolate — **read-only auth**.
  ///
  /// ## The bug this exists to prevent
  ///
  /// The FCM background handler runs in its OWN isolate with its own Dart
  /// globals, so it built its own Supabase client via [startSupabaseInit] —
  /// which meant a second GoTrue client, pointed at the same persisted
  /// session, with `autoRefreshToken: true`.
  ///
  /// Supabase ROTATES refresh tokens: every refresh issues a new token and
  /// **revokes the old one**. Two clients refreshing the same session is
  /// therefore not merely wasteful, it is destructive —
  ///
  ///   1. a chat push arrives while the app is backgrounded or killed;
  ///   2. this isolate spins up, refreshes, and revokes the token the
  ///      foreground app still holds in memory and on disk;
  ///   3. the app's next refresh presents a revoked token, GoTrue rejects
  ///      it, and supabase_flutter emits `AuthChangeEvent.signedOut`;
  ///   4. the member opens the app and is on the login screen, while their
  ///      session is alive and healthy on the server.
  ///
  /// That last detail is the signature: `auth.sessions` shows the session
  /// present and recently refreshed, `auth.refresh_tokens` shows a token
  /// issued and never used, and there is no logout in the audit log —
  /// because nobody logged out.
  ///
  /// `EncryptedSharedPreferences` is also explicitly NOT multi-process
  /// safe, so two engines writing the session blob risks losing it outright.
  /// With refresh disabled this isolate only ever READS.
  ///
  /// The cost of this is that a background call made with an already-expired
  /// access token fails with 401. That is fine and deliberate: the caller
  /// falls back to marking on next foreground. A late delivery tick is worth
  /// far less than a session.
  static Future<void> startSupabaseInitForBackgroundIsolate() =>
      startSupabaseInit(autoRefreshToken: false);

  /// Resolves once Supabase is fully initialized. Splash awaits this
  /// before AuthService.isSignedIn / currentUser reads.
  ///
  /// The defensive fallback deliberately starts a NON-refreshing client.
  /// Only `main()` may own token refresh, and it always calls
  /// [startSupabaseInit] explicitly before anything can reach here. So if
  /// this fallback ever fires we are, by definition, somewhere that is not
  /// the UI isolate's startup path — and the safe assumption there is "read
  /// the session, do not rotate it". Defaulting the other way is what let a
  /// background isolate revoke the app's own token.
  static Future<void> awaitSupabaseReady() async {
    final ready = _supabaseReady;
    if (ready == null) {
      await startSupabaseInit(autoRefreshToken: false);
      return;
    }
    await ready;
  }
}
