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
    // Broad net-failure detection — the raw error here can be a
    // SocketException, ClientException, TimeoutException, TLS
    // handshake failure, or a dozen platform-specific phrasings.
    // Catch them all and show one friendly offline message instead of
    // leaking "ClientException with SocketException: Failed host
    // lookup 'eqby...supabase.co'" to the user.
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
  ///
  /// Recommended Supabase RPC (run once in SQL editor):
  /// ```
  /// create or replace function public.email_exists(p_email text)
  /// returns boolean
  /// language sql security definer set search_path = public, auth
  /// as $$
  ///   select exists(select 1 from auth.users where email = lower(p_email));
  /// $$;
  /// grant execute on function public.email_exists(text) to anon, authenticated;
  /// ```
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

  /// Sign in via Google. Hands the Google ID + access tokens to
  /// Supabase so it can mint a session. Returns failure if the user
  /// cancels the picker (no error message — that's a normal cancel).
  ///
  /// Requires `GoogleService-Info.plist` / `google-services.json` to
  /// reference the right OAuth client IDs — see Supabase Auth → Google
  /// provider settings.
  /// Web OAuth client ID from Google Cloud Console → APIs & Services
  /// → Credentials. Must be the **Web** client (not Android/iOS) — the
  /// google_sign_in plugin uses it as the audience for the ID token so
  /// Supabase can verify it via signInWithIdToken.
  ///
  /// Leave as the placeholder for builds where Google sign-in is not
  /// expected to work; the catch-all error in this method will surface
  /// the misconfig clearly to the user.
  static const _googleWebClientId =
      '13892017929-sn69ofm9c8bvb46qtj9m3qac4aajuk57.apps.googleusercontent.com';

  static Future<AuthResult> signInWithGoogle() async {
    try {
      final google = GoogleSignIn(serverClientId: _googleWebClientId);
      // Clear any cached Google account from a previous session so the
      // picker actually shows up. Without this, signIn() silently
      // returns the last-used account — users who signed out can't
      // switch to a different Google account on the same device.
      await google.signOut();
      final account = await google.signIn();
      if (account == null) {
        return AuthResult.failure('Sign in cancelled.');
      }
      final auth = await account.authentication;
      final idToken = auth.idToken;
      final accessToken = auth.accessToken;
      if (idToken == null) {
        // Almost always means the Web client ID is missing from the
        // GoogleSignIn configuration. Without it Google's native SDK
        // returns an access token but no ID token — Supabase needs the
        // ID token to mint a session.
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
      // Surface the underlying message rather than a generic string so
      // misconfiguration (e.g. PlatformException: sign_in_failed, code
      // 10 / DEVELOPER_ERROR) is visible to the user and to support.
      return AuthResult.failure('Google sign in failed: $e');
    }
  }

  /// Verify the current password by re-running signInWithPassword
  /// against the active user's email. Supabase doesn't expose a
  /// "reauthenticate" RPC, so we use a sign-in attempt as the
  /// authoritative check. Doesn't change the session — on success
  /// we just return AuthResult.success and the caller proceeds with
  /// the password change flow.
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
      // Supabase emits "Invalid login credentials" for wrong password;
      // re-phrase it for the change-password context so the user knows
      // exactly which field is wrong.
      if (e.message.toLowerCase().contains('credentials')) {
        return AuthResult.failure('Current password is incorrect.');
      }
      return AuthResult.failure(e.message);
    } catch (_) {
      return AuthResult.failure('Could not verify your password.');
    }
  }

  /// Change the signed-in user's password. Caller is responsible for
  /// asking the user to confirm the new value twice and (for the
  /// settings flow) for verifying the current password first via
  /// [verifyCurrentPassword].
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

  /// Custom URL scheme our app intercepts via AndroidManifest /
  /// CFBundleURLTypes. Supabase will replace the default Site URL with
  /// this in the recovery email; tapping it relaunches the app and
  /// fires AuthChangeEvent.passwordRecovery so main.dart can route to
  /// the reset screen.
  ///
  /// You must also add this URL to the Supabase dashboard at
  /// Auth → URL Configuration → Redirect URLs, otherwise the link will
  /// still resolve to the Site URL (defaults to localhost in dev).
  static const _passwordResetRedirectUrl =
      'io.supabase.adventconnect://login-callback';

  static Future<AuthResult> sendPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(
        email,
        redirectTo: _passwordResetRedirectUrl,
      );
      return AuthResult.success(null);
    } on AuthException catch (e) {
      return AuthResult.failure(e.message);
    } catch (_) {
      return AuthResult.failure('Could not send reset email.');
    }
  }

  /// Best-effort delete of the current account. Tries a server-side
  /// `delete_my_account` RPC first (which can call auth.admin.deleteUser
  /// from a SECURITY DEFINER function); if that's not provisioned yet,
  /// falls back to wiping the user's own `profiles` row. Either way the
  /// user is signed out at the end so the device no longer has a session.
  ///
  /// Recommended server-side RPC (run once in SQL editor):
  /// ```
  /// create or replace function public.delete_my_account()
  /// returns void
  /// language plpgsql security definer set search_path = public, auth
  /// as $$
  /// begin
  ///   delete from profiles where id = auth.uid();
  ///   delete from auth.users where id = auth.uid();
  /// end;
  /// $$;
  /// grant execute on function public.delete_my_account() to authenticated;
  /// ```
  static Future<AuthResult> deleteAccount() async {
    final user = currentUser;
    if (user == null) {
      return AuthResult.failure('Sign in to delete your account.');
    }
    Object? rpcError;
    try {
      await _client.rpc('delete_my_account');
    } catch (e) {
      rpcError = e;
    }
    // Even if the RPC succeeded, clear the local profile row defensively;
    // if it failed (e.g. function not yet created), this gives us at
    // least client-driven data removal.
    try {
      await _client.from('profiles').delete().eq('id', user.id);
    } catch (_) {
      // ignore — RLS may reject if RPC already removed the row
    }
    try {
      await _client.auth.signOut();
    } catch (_) {
      // ignore
    }
    // Disconnect (not just sign out) the Google session so even if the
    // RPC failed and auth.users still exists, the next Google sign-in
    // tap shows the picker — letting the user pick a different account
    // rather than silently re-linking the same Google identity to the
    // un-deleted auth user.
    try {
      await GoogleSignIn(serverClientId: _googleWebClientId).disconnect();
    } catch (_) {
      // ignore
    }
    await SecureStorageService.clearAll();
    if (rpcError != null) {
      // RPC missing — surface a soft warning so the caller can tell the
      // user that auth-level removal is still pending.
      return AuthResult.failure(
        'Your profile data has been removed. Full account removal is '
        'pending — contact support if you log back in.',
      );
    }
    return AuthResult.success(null);
  }

  static Future<void> signOut() async {
    // Clear the FCM token first so the next user on this device doesn't
    // inherit pushes addressed to the previous one. Best-effort —
    // failures here must not block the sign-out itself.
    try {
      final user = _client.auth.currentUser;
      if (user != null) {
        await _client
            .from('profiles')
            .update({'fcm_token': null})
            .eq('id', user.id);
      }
    } catch (_) {
      // ignore — user may already be offline
    }
    await _client.auth.signOut();
    // Also clear Google's native sign-in cache so next time the user
    // hits "Continue with Google" they see the account picker instead
    // of being auto-signed-in with the previous account.
    try {
      await GoogleSignIn(serverClientId: _googleWebClientId).signOut();
    } catch (_) {
      // ignore — no cached Google session is fine
    }
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
      // Empty string is the "remove" signal — callers pass '' to
      // clear a photo (or bio etc). We write null to the DB and
      // strip the metadata key so the field actually goes back to
      // unset, not "set to empty string".
      String? sentinelOrNull(String? v) =>
          (v != null && v.isEmpty) ? null : v;
      if (fullName != null) next['full_name'] = fullName.trim();
      if (bio != null) next['bio'] = bio.trim();
      if (churchId != null) next['church_id'] = churchId;
      if (username != null && username.trim().isNotEmpty) {
        next['username'] = username.trim();
      }
      if (profilePhotoUrl != null) {
        final v = sentinelOrNull(profilePhotoUrl);
        if (v == null) {
          next.remove('profile_photo_url');
        } else {
          next['profile_photo_url'] = v;
        }
      }
      if (coverPhotoUrl != null) {
        final v = sentinelOrNull(coverPhotoUrl);
        if (v == null) {
          next.remove('cover_photo_url');
        } else {
          next['cover_photo_url'] = v;
        }
      }
      final response = await _client.auth.updateUser(
        UserAttributes(data: next),
      );

      final dbUpdates = <String, dynamic>{};
      if (fullName != null) dbUpdates['full_name'] = fullName.trim();
      if (bio != null) dbUpdates['bio'] = bio.trim();
      // Persist username to the profiles table — this is the column
      // hasCompletedProfileSetup() reads to decide "has this user
      // finished onboarding". Writing it only to user_metadata (the
      // old behaviour) meant the check never saw it, so Google users
      // were re-onboarded on every sign-in.
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
        // Best-effort mirror to the profiles table. If the column doesn't
        // exist yet (e.g. before the cover_photo_url migration is run)
        // fall back to writing only the columns the table understands so
        // the metadata write isn't lost.
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

  /// Best-effort write of arbitrary key/value pairs into the auth
  /// user's metadata. Used for onboarding preferences (interests,
  /// content types, notif prefs) that don't have first-class columns
  /// on the profiles table. Failures are swallowed — callers should
  /// treat this as fire-and-forget.
  static Future<void> updateMetadataDirect(Map<String, dynamic> patch) async {
    try {
      final user = currentUser;
      if (user == null) return;
      final next = <String, dynamic>{
        ...?user.userMetadata,
        ...patch,
      };
      await _client.auth.updateUser(UserAttributes(data: next));
    } catch (_) {
      // ignore — these writes are best-effort
    }
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

  /// Returns true if the signed-in user has FINISHED the onboarding
  /// flow. We can't just check "has a row in profiles" because the
  /// `on_auth_user_created` trigger (patch_001) inserts an empty
  /// profiles row the moment auth.users gets a new entry — so every
  /// brand-new account would look "completed".
  ///
  /// We check `username` instead: the onboarding flow (step 1) requires
  /// a username before letting the user continue, so a non-empty
  /// username is the authoritative "this user has been through the
  /// onboarding setup" signal.
  static Future<bool> hasCompletedProfileSetup() async {
    final user = currentUser;
    if (user == null) return false;
    final meta = user.userMetadata ?? const {};
    // Primary signal: explicit "onboarding_completed" flag written by
    // OnboardingFlowScreen._finish() when the user taps "Enter App".
    // This is the authoritative marker — username alone wasn't enough
    // because step 1 makes the username optional, so users who
    // skipped it got re-onboarded forever.
    if (meta['onboarding_completed'] == true) return true;
    // Fallback A (for users who onboarded before the flag existed):
    // a non-empty username in metadata.
    final metaUsername = (meta['username'] as String?)?.trim() ?? '';
    if (metaUsername.isNotEmpty) return true;
    // Fallback B: username on the profiles row.
    try {
      final row = await _client
          .from('profiles')
          .select('username')
          .eq('id', user.id)
          .maybeSingle();
      if (row == null) return false;
      final username = (row['username'] as String?)?.trim();
      return username != null && username.isNotEmpty;
    } catch (_) {
      // Network error or RLS issue — fall back to assuming NOT set up
      // so the user goes through onboarding rather than being silently
      // dropped into the app with no profile.
      return false;
    }
  }

  static Future<DateTime?> getStoredBirthDate() async {
    try {
      final stored = await SecureStorageService.read(_birthDateKey);
      if (stored == null) return null;
      return DateTime.tryParse(stored);
    } catch (_) {
      // Secure storage can throw a MissingPluginException in unit /
      // widget tests where the platform channel isn't mocked. Treat
      // that the same as "no stored value" so the caller falls back
      // to the route-extra birth date.
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
