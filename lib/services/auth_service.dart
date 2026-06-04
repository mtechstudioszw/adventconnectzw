import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'connectivity_service.dart';
import 'secure_storage_service.dart';

class AuthResult {
  AuthResult.success(this.user)
      : errorMessage = null,
        isSuccess = true;
  AuthResult.failure(this.errorMessage)
      : user = null,
        isSuccess = false;

  final User? user;
  final String? errorMessage;
  final bool isSuccess;
}

class AuthService {
  AuthService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static const _ageVerifiedKey = 'age_verified';
  static const _birthDateKey = 'birth_date';

  static User? get currentUser => _client.auth.currentUser;
  static Session? get currentSession => _client.auth.currentSession;
  static bool get isSignedIn => currentSession != null;

  static Stream<AuthState> get authStateChanges =>
      _client.auth.onAuthStateChange;

  static Future<AuthResult> signUp({
    required String email,
    required String password,
    required String fullName,
    required DateTime birthDate,
  }) async {
    try {
      if (!ConnectivityService.isOnline) {
        return AuthResult.failure(
          'You appear to be offline. Check your connection and try '
          'again.',
        );
      }
      // Mirror of the signInWithGoogle pre-check: if an account
      // already exists on this email under Google, refuse the email
      // signup and tell them to use "Continue with Google" — this
      // surfaces the cross-provider collision before Supabase emits
      // its generic "user already registered" error.
      final providers = await emailAuthProviders(email);
      if (providers != null && providers.isNotEmpty) {
        if (providers.contains('google') && !providers.contains('email')) {
          return AuthResult.failure(
            'An account with this email already exists, signed in '
            'with Google. Tap "Continue with Google" to sign in.',
          );
        }
        if (providers.contains('email')) {
          return AuthResult.failure(
            'An account with this email already exists. '
            'Try logging in instead.',
          );
        }
      }
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'birth_date': birthDate.toIso8601String(),
        },
      );

      if (response.user == null) {
        return AuthResult.failure('Sign up failed. Please try again.');
      }

      // If Supabase auto-confirm is OFF, response.session is null and
      // the user must verify via OTP (handled in
      // EmailVerificationScreen). If auto-confirm is ON, Supabase
      // hands us a session immediately — that's the bug the user
      // reported (any email gets in), so sign out to force the OTP
      // flow regardless of dashboard config.
      if (response.session != null) {
        try {
          await _client.auth.signOut();
        } catch (_) {
          // ignore — best-effort
        }
      }

      // Age verification persists regardless of email verification,
      // because the age gate happens BEFORE signUp and the value is
      // about the device, not the auth user.
      await SecureStorageService.write(
        _birthDateKey,
        birthDate.toIso8601String(),
      );
      await SecureStorageService.write(_ageVerifiedKey, 'true');

      return AuthResult.success(response.user);
    } on AuthException catch (e) {
      return AuthResult.failure(_friendlyAuthError(e.message));
    } catch (e) {
      return AuthResult.failure(_friendlyAuthError(e.toString()));
    }
  }

  /// Translate Supabase's raw auth errors into something a user can
  /// act on. Anything we don't recognise falls through untouched.
  static String _friendlyAuthError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('error sending confirmation') ||
        lower.contains('error sending email') ||
        lower.contains('unable to send') ||
        (lower.contains('unexpected') && lower.contains('email'))) {
      return 'We couldn\'t send the confirmation email right now. '
          'Please try again in a moment, or contact support if this '
          'keeps happening.';
    }
    if (lower.contains('rate limit') || lower.contains('too many')) {
      return 'Too many attempts — please wait a minute and try again.';
    }
    if (lower.contains('already registered') ||
        lower.contains('user already') ||
        lower.contains('already exists')) {
      return 'An account with that email already exists. Try logging in instead.';
    }
    if (lower.contains('invalid login') ||
        lower.contains('invalid credentials')) {
      return 'Email or password is incorrect.';
    }
    if (lower.contains('weak password') || lower.contains('password should')) {
      return 'Choose a stronger password — at least 8 characters.';
    }
    if (lower.contains('network') ||
        lower.contains('failed host lookup') ||
        lower.contains('socketexception') ||
        lower.contains('clientexception') ||
        lower.contains('connection refused') ||
        lower.contains('connection closed') ||
        lower.contains('connection reset') ||
        lower.contains('connection timed out') ||
        lower.contains('connection attempt failed') ||
        lower.contains('unreachable') ||
        lower.contains('handshake') ||
        lower.contains('timeout') ||
        lower.contains('timed out') ||
        lower.contains('xmlhttprequest')) {
      return 'You appear to be offline. Check your connection and try again.';
    }
    return raw;
  }

  /// Best-effort check whether an account exists for `email`. Used by
  /// the unified auth screen to decide whether to reveal the password
  /// field (login) or the full signup form. Returns null if we couldn't
  /// tell (network error, RPC not provisioned, etc.) — the caller
  /// should then default to attempting a sign-in and reacting to the
  /// error.
  static Future<bool?> emailExists(String email) async {
    final trimmed = email.trim().toLowerCase();
    if (trimmed.isEmpty) return null;
    try {
      final result = await _client.rpc(
        'email_exists',
        params: {'p_email': trimmed},
      );
      if (result is bool) return result;
      if (result is List && result.isNotEmpty) {
        final first = result.first;
        if (first is bool) return first;
        if (first is Map && first.values.isNotEmpty) {
          final v = first.values.first;
          if (v is bool) return v;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// What auth providers is [email] bound to? Returns one of:
  ///   - []                      → no account
  ///   - ['email']               → email/password only
  ///   - ['google']              → Google OAuth only
  ///   - ['email','google']      → already linked, either works
  ///   - null                    → RPC missing / network error
  static Future<List<String>?> emailAuthProviders(String email) async {
    final trimmed = email.trim().toLowerCase();
    if (trimmed.isEmpty) return null;
    try {
      final result = await _client.rpc(
        'email_auth_providers',
        params: {'p_email': trimmed},
      );
      if (result is List) {
        return result.map((e) => e.toString()).toList();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Verify a signup using the 6-digit code Supabase emails to the
  /// user. On success, mints a real session and returns it. Caller
  /// should then route the user into profile setup.
  static Future<AuthResult> verifySignupOtp({
    required String email,
    required String token,
  }) async {
    try {
      final response = await _client.auth.verifyOTP(
        type: OtpType.signup,
        email: email,
        token: token.trim(),
      );
      final user = response.user;
      if (user == null) {
        return AuthResult.failure('Verification failed. Try again.');
      }
      await _persistSession(response.session);
      return AuthResult.success(user);
    } on AuthException catch (e) {
      return AuthResult.failure(e.message);
    } catch (_) {
      return AuthResult.failure('Could not verify the code.');
    }
  }

  /// Send a 6-digit code to [email] so the user can prove inbox
  /// control without typing a password. Used by the "verify with
  /// email code" path on the auth screen — Claude-style escape hatch
  /// for users whose email is bound to Google but who don't want to
  /// (or can't) sign in with Google right now.
  ///
  /// `shouldCreateUser: false` because this is only used on emails we
  /// already know exist (the collision-detection branch in
  /// _onContinue). Lets Supabase return a clean "user not found"
  /// instead of silently creating a fresh row.
  static Future<AuthResult> sendEmailLoginOtp(String email) async {
    final trimmed = email.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return AuthResult.failure('Enter your email first.');
    }
    if (!ConnectivityService.isOnline) {
      return AuthResult.failure(
        'You appear to be offline. Check your connection and try again.',
      );
    }
    try {
      await _client.auth.signInWithOtp(
        email: trimmed,
        shouldCreateUser: false,
      );
      return AuthResult.success(null);
    } on AuthException catch (e) {
      final lower = e.message.toLowerCase();
      if (lower.contains('rate limit') || lower.contains('too many')) {
        return AuthResult.failure(
          'Couldn\'t send the code right now — try Continue with Google '
          'instead, or try again in a few minutes.',
        );
      }
      return AuthResult.failure(_friendlyAuthError(e.message));
    } catch (e) {
      return AuthResult.failure(
        'Couldn\'t send the code right now — try Continue with Google '
        'instead, or check your connection and try again.',
      );
    }
  }

  /// Verify the 6-digit OTP sent by [sendEmailLoginOtp] and sign the
  /// user in. After success the caller may invite the user to set a
  /// password (`setPasswordForOtpUser`) so they can sign in directly
  /// next time without another email round-trip.
  static Future<AuthResult> verifyEmailLoginOtp({
    required String email,
    required String token,
  }) async {
    try {
      final response = await _client.auth.verifyOTP(
        type: OtpType.email,
        email: email.trim().toLowerCase(),
        token: token.trim(),
      );
      final user = response.user;
      if (user == null) {
        return AuthResult.failure(
          'Verification failed. Check the code and try again.',
        );
      }
      await _persistSession(response.session);
      return AuthResult.success(user);
    } on AuthException catch (e) {
      final lower = e.message.toLowerCase();
      if (lower.contains('expired') || lower.contains('invalid')) {
        return AuthResult.failure(
          'That code didn\'t match. Request a new one and try again.',
        );
      }
      return AuthResult.failure(_friendlyAuthError(e.message));
    } catch (_) {
      return AuthResult.failure('Could not verify the code.');
    }
  }

  /// Attach an email/password identity to the currently-signed-in
  /// user. Used after a successful OTP verification so the user can
  /// sign in with password next time instead of waiting for another
  /// email. Failure is swallowed — they're already signed in via
  /// OTP, so they can keep going without setting a password.
  static Future<AuthResult> setPasswordForOtpUser(String password) async {
    if (password.length < 8) {
      return AuthResult.failure(
        'Choose a stronger password — at least 8 characters.',
      );
    }
    try {
      await _client.auth.updateUser(UserAttributes(password: password));
      return AuthResult.success(currentUser);
    } on AuthException catch (e) {
      return AuthResult.failure(_friendlyAuthError(e.message));
    } catch (_) {
      return AuthResult.failure('Could not save the password.');
    }
  }

  static Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        return AuthResult.failure('Invalid email or password.');
      }

      await _persistSession(response.session);
      return AuthResult.success(response.user);
    } on AuthException catch (e) {
      return AuthResult.failure(_friendlyAuthError(e.message));
    } catch (e) {
      return AuthResult.failure(_friendlyAuthError(e.toString()));
    }
  }

  static const _googleWebClientId =
      '13892017929-sn69ofm9c8bvb46qtj9m3qac4aajuk57.apps.googleusercontent.com';

  /// Sign in via Google.
  ///
  /// BUG 2 FIX — before signing in, we check whether this Google
  /// email is already registered as an email/password account. If it
  /// is, we block the sign-in and tell the user to log in with their
  /// password first, then link Google from Settings. This prevents
  /// Supabase from silently creating a second parallel account for the
  /// same email address.
  static Future<AuthResult> signInWithGoogle() async {
    try {
      // Catch offline up-front so users see the same "you appear to
      // be offline" copy as the email path, instead of the raw
      // "PlatformException(sign_in_failed, ...network…)" Google emits.
      // The provider picker, the ID-token exchange, AND the
      // emailAuthProviders pre-check all need network — bailing here
      // is the cleanest place.
      if (!ConnectivityService.isOnline) {
        return AuthResult.failure(
          'You appear to be offline. Check your connection and try '
          'again.',
        );
      }
      final google = GoogleSignIn(serverClientId: _googleWebClientId);
      // Clear any cached Google account so the picker always shows up.
      await google.signOut();
      final account = await google.signIn();
      if (account == null) {
        return AuthResult.failure('Sign in cancelled.');
      }

      // Duplicate-account guard. Check what providers are already
      // attached to this email before handing the ID token to
      // Supabase — if the email exists as email-only, Supabase would
      // create a NEW separate auth.users row instead of merging,
      // which leaves the user with two accounts that look identical.
      // We refuse the Google flow in that case and tell the user to
      // sign in with email/password instead. Account linking via
      // Settings was intentionally not exposed — one auth method per
      // email is simpler than the merge headache later.
      final googleEmail = account.email.trim().toLowerCase();
      final providers = await emailAuthProviders(googleEmail);
      if (providers != null &&
          providers.isNotEmpty &&
          providers.contains('email') &&
          !providers.contains('google')) {
        try {
          await google.signOut();
        } catch (_) {}
        return AuthResult.failure(
          'An account with this email already exists. '
          'Sign in with your email and password instead.',
        );
      }

      final auth = await account.authentication;
      final idToken = auth.idToken;
      final accessToken = auth.accessToken;
      if (idToken == null) {
        return AuthResult.failure(
          'Google didn\'t return an ID token. The app may be missing a '
          'Web OAuth client ID — contact support.',
        );
      }
      final response = await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      if (response.user == null) {
        return AuthResult.failure('Could not sign in with Google.');
      }
      await _persistSession(response.session);
      return AuthResult.success(response.user);
    } on AuthException catch (e) {
      return AuthResult.failure(_friendlyAuthError(e.message));
    } catch (e) {
      // Run through the friendly mapper so offline / DNS / handshake
      // failures from the Google SDK get the same human-readable
      // copy as the email path instead of the raw exception toString.
      return AuthResult.failure(_friendlyAuthError(e.toString()));
    }
  }

  // ────────────────────────────────────────────────────────────────
  // Sign in with Apple (iOS only — App Store Guideline 4.8)
  //
  // Mirrors signInWithGoogle: get a native Apple credential, hand the
  // identity token to Supabase via signInWithIdToken(provider: apple).
  // A nonce (raw → Supabase, SHA-256 → Apple) gives replay protection.
  //
  // NOT functional until the Apple provider is configured in Supabase
  // Auth (Service ID + key from the Apple Developer account) — see
  // docs/APPLE_SIGN_IN_SETUP.md. Until then this returns a friendly
  // failure rather than crashing. The button is shown on iOS only.
  // ────────────────────────────────────────────────────────────────
  static String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  static String _sha256(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  static Future<AuthResult> signInWithApple() async {
    try {
      if (!ConnectivityService.isOnline) {
        return AuthResult.failure(
          'You appear to be offline. Check your connection and try '
          'again.',
        );
      }

      final rawNonce = _generateNonce();
      final hashedNonce = _sha256(rawNonce);

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        return AuthResult.failure(
          'Apple didn\'t return an identity token. Try again.',
        );
      }

      final response = await _client.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );
      if (response.user == null) {
        return AuthResult.failure('Could not sign in with Apple.');
      }

      // Apple only returns the user's name on the VERY FIRST
      // authorization — capture it into metadata while we have it so
      // the profile isn't left nameless.
      final given = credential.givenName ?? '';
      final family = credential.familyName ?? '';
      final full = [given, family].where((s) => s.isNotEmpty).join(' ').trim();
      if (full.isNotEmpty &&
          (response.user!.userMetadata?['full_name'] == null)) {
        try {
          await updateMetadataDirect({'full_name': full});
        } catch (_) {}
      }

      await _persistSession(response.session);
      return AuthResult.success(response.user);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return AuthResult.failure('Sign in cancelled.');
      }
      return AuthResult.failure(_friendlyAuthError(e.message));
    } on AuthException catch (e) {
      return AuthResult.failure(_friendlyAuthError(e.message));
    } catch (e) {
      return AuthResult.failure(_friendlyAuthError(e.toString()));
    }
  }

  static Future<AuthResult> verifyCurrentPassword(String password) async {
    final user = currentUser;
    final email = user?.email;
    if (user == null || email == null || email.isEmpty) {
      return AuthResult.failure('Sign in to change your password.');
    }
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (response.user == null) {
        return AuthResult.failure('Current password is incorrect.');
      }
      return AuthResult.success(response.user);
    } on AuthException catch (e) {
      if (e.message.toLowerCase().contains('credentials')) {
        return AuthResult.failure('Current password is incorrect.');
      }
      return AuthResult.failure(e.message);
    } catch (_) {
      return AuthResult.failure('Could not verify your password.');
    }
  }

  static Future<AuthResult> changePassword(String newPassword) async {
    try {
      if (newPassword.length < 8) {
        return AuthResult.failure('Password must be at least 8 characters.');
      }
      final response = await _client.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      if (response.user == null) {
        return AuthResult.failure('Could not change password.');
      }
      return AuthResult.success(response.user);
    } on AuthException catch (e) {
      return AuthResult.failure(e.message);
    } catch (_) {
      return AuthResult.failure('Could not change password.');
    }
  }

  static const _passwordResetRedirectUrl =
      'io.supabase.adventconnect://login-callback';

  static const _resetLimitWindow = Duration(hours: 1);
  static const _resetLimitMax = 3;

  static Future<AuthResult> sendPasswordReset(String email) async {
    final normalised = email.trim().toLowerCase();
    if (normalised.isEmpty) {
      return AuthResult.failure('Enter your email to reset.');
    }
    final serverOk = await _checkServerRateLimit(
      identity: normalised,
      action: 'password_reset',
      max: 3,
      windowSeconds: 3600,
    );
    if (serverOk == false) {
      return AuthResult.failure(
        'Too many reset attempts for this email in the last hour. '
        'Wait a bit before trying again.',
      );
    }
    if (serverOk == null) {
      final clientOk = await _checkResetThrottle(normalised);
      if (!clientOk) {
        return AuthResult.failure(
          'Too many reset attempts for this email in the last hour. '
          'Wait a bit before trying again.',
        );
      }
    }
    try {
      await _client.auth.resetPasswordForEmail(
        normalised,
        redirectTo: _passwordResetRedirectUrl,
      );
      await _recordResetAttempt(normalised);
      return AuthResult.success(null);
    } on AuthException catch (e) {
      return AuthResult.failure(_friendlyAuthError(e.message));
    } catch (e) {
      return AuthResult.failure(_friendlyAuthError(e.toString()));
    }
  }

  static Future<bool?> _checkServerRateLimit({
    required String identity,
    required String action,
    int max = 3,
    int windowSeconds = 3600,
  }) async {
    try {
      final result = await _client.rpc(
        'check_and_consume_rate_limit',
        params: {
          'p_identity_key': identity,
          'p_action_key': action,
          'p_max': max,
          'p_window_seconds': windowSeconds,
        },
      );
      if (result is bool) return result;
      if (result is List && result.isNotEmpty && result.first is bool) {
        return result.first as bool;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _recordResetAttempt(String email) async {
    try {
      final key = 'pwreset_log_$email';
      final existing = (await SecureStorageService.read(key)) ?? '';
      final now = DateTime.now().millisecondsSinceEpoch;
      final cutoff = now - _resetLimitWindow.inMilliseconds;
      final kept = existing
          .split(',')
          .map(int.tryParse)
          .whereType<int>()
          .where((t) => t >= cutoff)
          .toList()
        ..add(now);
      await SecureStorageService.write(key, kept.join(','));
    } catch (_) {}
  }

  static Future<bool> _checkResetThrottle(String email) async {
    try {
      final key = 'pwreset_log_$email';
      final existing = await SecureStorageService.read(key);
      if (existing == null || existing.isEmpty) return true;
      final now = DateTime.now().millisecondsSinceEpoch;
      final cutoff = now - _resetLimitWindow.inMilliseconds;
      final recent = existing
          .split(',')
          .map(int.tryParse)
          .whereType<int>()
          .where((t) => t >= cutoff)
          .length;
      return recent < _resetLimitMax;
    } catch (_) {
      return true;
    }
  }

  /// Delete the current account completely.
  ///
  /// BUG 1 FIX — the old implementation deleted the profiles row and
  /// called GoogleSignIn.disconnect(), but it never deleted the
  /// auth.users row. Supabase kept the auth.users entry alive, so
  /// tapping "Continue with Google" again found the existing row and
  /// restored the full session — making account deletion appear broken.
  ///
  /// This version calls a Supabase Edge Function (`delete-account`)
  /// that runs under the service_role key and calls
  /// auth.admin.deleteUser(), which is the only way to remove an
  /// auth.users row from application code. See the Edge Function
  /// source in supabase/functions/delete-account/index.ts.
  ///
  /// If the Edge Function is not yet deployed, the method falls back
  /// to the old profile-only deletion and returns a soft-warning
  /// failure so the UI can tell the user to contact support.
  static Future<AuthResult> deleteAccount() async {
    final user = currentUser;
    if (user == null) {
      return AuthResult.failure('Sign in to delete your account.');
    }

    Object? edgeFunctionError;

    // ── BUG 1 FIX: call Edge Function to delete auth.users row ───────
    try {
      final response = await _client.functions.invoke(
        'delete-account',
        method: HttpMethod.post,
      );
      // functions.invoke throws on non-2xx, but guard anyway.
      if (response.status >= 300) {
        edgeFunctionError =
            'Edge Function returned status ${response.status}';
      }
    } catch (e) {
      edgeFunctionError = e;
    }
    // ── END BUG 1 FIX ─────────────────────────────────────────────────

    // Belt-and-braces: delete the profiles row too in case the Edge
    // Function failed after writing but before cascading, or the RLS
    // lets us clean up what we can client-side.
    try {
      await _client.from('profiles').delete().eq('id', user.id);
    } catch (_) {
      // Ignore — RLS may reject if Edge Function already removed the row.
    }

    // Sign out of Supabase session.
    try {
      await _client.auth.signOut();
    } catch (_) {}

    // Revoke the Google token so the next "Continue with Google" tap
    // shows the account picker rather than silently signing back in.
    // disconnect() removes the OAuth grant entirely, not just the
    // local cache — this is what prevents the "deleted but came back"
    // symptom on the Google side.
    try {
      await GoogleSignIn(serverClientId: _googleWebClientId).disconnect();
    } catch (_) {}

    await SecureStorageService.clearAll();

    if (edgeFunctionError != null) {
      // Edge Function not deployed yet, or a transient error.
      // Profile data is gone but the auth.users row may still exist.
      return AuthResult.failure(
        'Your profile data has been removed, but full account deletion '
        'requires the delete-account Edge Function to be deployed. '
        'Contact support if you can still sign back in.',
      );
    }

    return AuthResult.success(null);
  }

  static Future<void> signOut() async {
    try {
      final user = _client.auth.currentUser;
      if (user != null) {
        await _client
            .from('profiles')
            .update({'fcm_token': null}).eq('id', user.id);
      }
    } catch (_) {}
    await _client.auth.signOut();
    try {
      await GoogleSignIn(serverClientId: _googleWebClientId).signOut();
    } catch (_) {}
    await SecureStorageService.clearAll();
  }

  static Future<AuthResult> updateProfile({
    String? fullName,
    String? bio,
    String? churchId,
    String? username,
    String? profilePhotoUrl,
    String? coverPhotoUrl,
  }) async {
    try {
      final user = currentUser;
      if (user == null) {
        return AuthResult.failure('Sign in to update your profile.');
      }

      final current = user.userMetadata ?? const {};
      final next = <String, dynamic>{...current};
      String? sentinelOrNull(String? v) =>
          (v != null && v.isEmpty) ? null : v;
      if (fullName != null) next['full_name'] = fullName.trim();
      if (bio != null) next['bio'] = bio.trim();
      if (churchId != null) next['church_id'] = churchId;
      if (username != null && username.trim().isNotEmpty) {
        next['username'] = username.trim();
      }
      if (profilePhotoUrl != null) {
        next['profile_photo_url'] = sentinelOrNull(profilePhotoUrl);
      }
      if (coverPhotoUrl != null) {
        next['cover_photo_url'] = sentinelOrNull(coverPhotoUrl);
      }
      final response = await _client.auth.updateUser(
        UserAttributes(data: next),
      );

      final dbUpdates = <String, dynamic>{};
      if (fullName != null) dbUpdates['full_name'] = fullName.trim();
      if (bio != null) dbUpdates['bio'] = bio.trim();
      if (username != null && username.trim().isNotEmpty) {
        dbUpdates['username'] = username.trim();
      }
      if (churchId != null) {
        dbUpdates['church_id'] =
            churchId.isEmpty ? null : int.tryParse(churchId);
      }
      if (profilePhotoUrl != null) {
        dbUpdates['profile_photo_url'] = sentinelOrNull(profilePhotoUrl);
      }
      if (coverPhotoUrl != null) {
        dbUpdates['cover_photo_url'] = sentinelOrNull(coverPhotoUrl);
      }
      if (dbUpdates.isNotEmpty) {
        try {
          await _client
              .from('profiles')
              .upsert({'id': user.id, ...dbUpdates}, onConflict: 'id');
        } catch (_) {
          final safe = Map<String, dynamic>.from(dbUpdates)
            ..remove('cover_photo_url');
          if (safe.isNotEmpty) {
            await _client
                .from('profiles')
                .upsert({'id': user.id, ...safe}, onConflict: 'id');
          }
        }
      }

      return AuthResult.success(response.user);
    } on AuthException catch (e) {
      return AuthResult.failure(e.message);
    } catch (_) {
      return AuthResult.failure('Could not update profile.');
    }
  }

  static Future<void> updateMetadataDirect(Map<String, dynamic> patch) async {
    try {
      final user = currentUser;
      if (user == null) return;
      final next = <String, dynamic>{
        ...?user.userMetadata,
        ...patch,
      };
      await _client.auth.updateUser(UserAttributes(data: next));
    } catch (_) {}
  }

  static Future<void> markAgeVerified(DateTime birthDate) async {
    await SecureStorageService.write(
      _birthDateKey,
      birthDate.toIso8601String(),
    );
    await SecureStorageService.write(_ageVerifiedKey, 'true');
  }

  static Future<bool> isAgeVerified() async {
    final value = await SecureStorageService.read(_ageVerifiedKey);
    return value == 'true';
  }

  /// True when the user has either finished the in-app onboarding flow
  /// OR already has onboarding-derived metadata from an earlier session.
  ///
  /// History:
  ///  - v1 read only `userMetadata['onboarding_completed']`. Users who
  ///    signed up before that flag was added got re-asked for date of
  ///    birth on every Google sign-in.
  ///  - v2 fell back to `profiles.full_name`. WRONG — the
  ///    `handle_new_user` trigger (patch_001) auto-fills full_name from
  ///    Google's raw_user_meta_data for brand-new Google users, so the
  ///    fallback fired immediately and bypassed both age verification
  ///    AND profile setup.
  ///  - v3 (current): the fallback is `userMetadata['interests']` — set
  ///    only on step 3 (Personalization) of onboarding_flow_screen, and
  ///    not auto-populated by Google OR by the signup trigger. Safe
  ///    signal that the user actually reached the onboarding flow.
  static Future<bool> hasCompletedProfileSetup() async {
    final user = currentUser;
    if (user == null) return false;
    final meta = user.userMetadata ?? const {};
    if (meta['onboarding_completed'] == true) return true;

    // Fallback for users who pre-date the onboarding_completed flag.
    // `interests` is written only by onboarding_flow_screen step 3,
    // and Google's raw metadata never includes it — so a non-empty
    // interests list is a reliable signal that this account
    // completed onboarding before. Heal the metadata flag.
    final interests = meta['interests'];
    final hasInterests = interests is List && interests.isNotEmpty;
    if (hasInterests) {
      unawaited(updateMetadataDirect({'onboarding_completed': true}));
      return true;
    }
    return false;
  }

  static Future<DateTime?> getStoredBirthDate() async {
    try {
      final stored = await SecureStorageService.read(_birthDateKey);
      if (stored == null) return null;
      return DateTime.tryParse(stored);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> isAgeVerifiedSafe() async {
    try {
      final value = await SecureStorageService.read(_ageVerifiedKey);
      return value == 'true';
    } catch (_) {
      return false;
    }
  }

  static bool meetsMinimumAge(DateTime birthDate, {int minimumAge = 16}) {
    final now = DateTime.now();
    int age = now.year - birthDate.year;
    final hasHadBirthday = now.month > birthDate.month ||
        (now.month == birthDate.month && now.day >= birthDate.day);
    if (!hasHadBirthday) age -= 1;
    return age >= minimumAge;
  }

  static Future<void> _persistSession(Session? session) async {
    if (session == null) return;
    await SecureStorageService.saveAuthToken(session.accessToken);
    final refresh = session.refreshToken;
    if (refresh != null) {
      await SecureStorageService.saveRefreshToken(refresh);
    }
    await SecureStorageService.saveUserId(session.user.id);
  }
}
