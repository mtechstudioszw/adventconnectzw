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

      await _persistSession(response.session);
      await SecureStorageService.write(
        _birthDateKey,
        birthDate.toIso8601String(),
      );
      await SecureStorageService.write(_ageVerifiedKey, 'true');

      return AuthResult.success(response.user);
    } on AuthException catch (e) {
      return AuthResult.failure(e.message);
    } catch (_) {
      return AuthResult.failure('An unexpected error occurred.');
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
      return AuthResult.failure(e.message);
    } catch (_) {
      return AuthResult.failure('An unexpected error occurred.');
    }
  }

  static Future<AuthResult> sendPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email);
      return AuthResult.success(null);
    } on AuthException catch (e) {
      return AuthResult.failure(e.message);
    } catch (_) {
      return AuthResult.failure('Could not send reset email.');
    }
  }

  static Future<void> signOut() async {
    await _client.auth.signOut();
    await SecureStorageService.clearAll();
  }

  static Future<AuthResult> updateProfile({
    String? fullName,
    String? bio,
    String? churchId,
    String? profilePhotoUrl,
  }) async {
    try {
      final user = currentUser;
      if (user == null) {
        return AuthResult.failure('Sign in to update your profile.');
      }

      final current = user.userMetadata ?? const {};
      final next = <String, dynamic>{...current};
      if (fullName != null) next['full_name'] = fullName.trim();
      if (bio != null) next['bio'] = bio.trim();
      if (churchId != null) next['church_id'] = churchId;
      if (profilePhotoUrl != null) {
        next['profile_photo_url'] = profilePhotoUrl;
      }
      final response = await _client.auth.updateUser(
        UserAttributes(data: next),
      );

      final dbUpdates = <String, dynamic>{};
      if (fullName != null) dbUpdates['full_name'] = fullName.trim();
      if (bio != null) dbUpdates['bio'] = bio.trim();
      if (churchId != null) {
        dbUpdates['church_id'] =
            churchId.isEmpty ? null : int.tryParse(churchId);
      }
      if (profilePhotoUrl != null) {
        dbUpdates['profile_photo_url'] = profilePhotoUrl;
      }
      if (dbUpdates.isNotEmpty) {
        await _client
            .from('profiles')
            .upsert({'id': user.id, ...dbUpdates}, onConflict: 'id');
      }

      return AuthResult.success(response.user);
    } on AuthException catch (e) {
      return AuthResult.failure(e.message);
    } catch (_) {
      return AuthResult.failure('Could not update profile.');
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

  static Future<DateTime?> getStoredBirthDate() async {
    final stored = await SecureStorageService.read(_birthDateKey);
    if (stored == null) return null;
    return DateTime.tryParse(stored);
  }

  static bool meetsMinimumAge(DateTime birthDate, {int minimumAge = 13}) {
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
