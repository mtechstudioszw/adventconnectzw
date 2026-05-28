import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
      final google = GoogleSignIn(serverClientId: _googleWebClientId);
      // Clear any cached Google account so the picker always shows up.
      await google.signOut();
      final account = await google.signIn();
      if (account == null) {
        return AuthResult.failure('Sign in cancelled.');
      }

      // ── BUG 2 FIX ──────────────────────────────────────────────────
      // Check what providers are already attached to this email before
      // we hand the ID token to Supabase. If the email exists as
      // email-only, Supabase would create a NEW separate auth.users row
      // (a second account) instead of merging — which is the duplicate-
      // account bug. Block it here and guide the user to link instead.
      final googleEmail = account.email.trim().toLowerCase();
      final providers = await emailAuthProviders(googleEmail);
      if (providers != null &&
          providers.isNotEmpty &&
          providers.contains('email') &&
          !providers.contains('google')) {
        // Account exists as email/password only. We cannot auto-link
        // without the user being signed in first. Tell them to log in
        // with their password, then link Google from Settings.
        try {
          await google.signOut();
        } catch (_) {}
        return AuthResult.failure(
          'An account with this email already exists. '
          'Sign in with your email and password instead. '
          'You can then link Google in Settings → Account.',
        );
      }
      // ── END BUG 2 FIX ───────────────────────────────────────────────

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
      return AuthResult.failure(e.message);
    } catch (e) {
      return AuthResult.failure('Google sign in failed: $e');
    }
  }

  /// Link a Google identity to the currently signed-in account.
  ///
  /// BUG 2 FIX — call this from Settings after the user is already
  /// signed in with email/password. Once linked, both Google and
  /// email+password work for the same account going forward.
  static Future<AuthResult> linkGoogleAccount() async {
    final user = currentUser;
    if (user == null) {
      return AuthResult.failure('Sign in to link Google.');
    }
    try {
      final google = GoogleSignIn(serverClientId: _googleWebClientId);
      await google.signOut();
      final account = await google.signIn();
      if (account == null) {
        return AuthResult.failure('Sign in cancelled.');
      }
      // Verify the Google email matches the signed-in account's email
      // so we don't accidentally link a different Google account.
      final googleEmail = account.email.trim().toLowerCase();
      final userEmail = (user.email ?? '').trim().toLowerCase();
      if (googleEmail.isNotEmpty &&
          userEmail.isNotEmpty &&
          googleEmail != userEmail) {
        try {
          await google.signOut();
        } catch (_) {}
        return AuthResult.failure(
          'That Google account uses a different email ($googleEmail). '
          'Sign in with the Google account that matches $userEmail.',
        );
      }
      // supabase_flutter's linkIdentity opens a browser OAuth flow.
      // The result comes back via the deep-link handler the same way
      // a normal OAuth sign-in does. The caller should listen to
      // authStateChanges for the identityLinked event to confirm.
      await _client.auth.linkIdentity(OAuthProvider.google);
      return AuthResult.success(_client.auth.currentUser);
    } on AuthException catch (e) {
      return AuthResult.failure(e.message);
    } catch (e) {
      return AuthResult.failure('Could not link Google: $e');
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
      if (response.status != null && response.status! >= 300) {
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

  static Future<bool> hasCompletedProfileSetup() async {
    final user = currentUser;
    if (user == null) return false;
    final meta = user.userMetadata ?? const {};
    if (meta['onboarding_completed'] == true) return true;
    final metaUsername = (meta['username'] as String?)?.trim() ?? '';
    if (metaUsername.isNotEmpty) return true;
    try {
      final row = await _client
          .from('profiles')
          .select('username')
          .eq('id', user.id)
          .maybeSingle();
      final username = (row?['username'] as String?)?.trim() ?? '';
      return username.isNotEmpty;
    } catch (_) {
      return true;
    }
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
