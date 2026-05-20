import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// supabase_flutter's session-persistence adapter, backed by
/// [FlutterSecureStorage] instead of SharedPreferences.
///
/// CLAUDE.md mandates secure storage for auth tokens (never
/// SharedPreferences). The default [SharedPreferencesLocalStorage]
/// would have:
///   - left tokens in unencrypted SharedPreferences on Android
///   - failed silently on some OEMs / fresh installs, which is the
///     root cause of "the app asks me to log in every time I reopen
///     it" — the SP write succeeds but the read returns null on the
///     next cold start.
///
/// Storing the session under a single key (`supabase_session`) on the
/// Android EncryptedSharedPreferences / iOS Keychain is both compliant
/// and reliable across restarts.
class SecureLocalStorage extends LocalStorage {
  SecureLocalStorage();

  static const _sessionKey = 'supabase_session';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  @override
  Future<void> initialize() async {
    // Nothing to do — secure storage is lazy.
  }

  @override
  Future<String?> accessToken() async {
    return _storage.read(key: _sessionKey);
  }

  @override
  Future<bool> hasAccessToken() async {
    final value = await _storage.read(key: _sessionKey);
    return value != null && value.isNotEmpty;
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    await _storage.write(key: _sessionKey, value: persistSessionString);
  }

  @override
  Future<void> removePersistedSession() async {
    await _storage.delete(key: _sessionKey);
  }
}
