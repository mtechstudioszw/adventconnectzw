import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  SecureStorageService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _tokenKey = 'auth_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _userIdKey = 'user_id';

  static Future<void> saveAuthToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  static Future<String?> getAuthToken() =>
      _storage.read(key: _tokenKey);

  static Future<void> saveRefreshToken(String token) =>
      _storage.write(key: _refreshTokenKey, value: token);

  static Future<String?> getRefreshToken() =>
      _storage.read(key: _refreshTokenKey);

  static Future<void> saveUserId(String userId) =>
      _storage.write(key: _userIdKey, value: userId);

  static Future<String?> getUserId() =>
      _storage.read(key: _userIdKey);

  static Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  static Future<String?> read(String key) =>
      _storage.read(key: key);

  static Future<void> delete(String key) =>
      _storage.delete(key: key);

  /// Keys that survive [clearAll] / sign-out. The intro onboarding
  /// flag and similar "device has seen X" markers shouldn't reset
  /// when the user logs out — that's how a returning user ended up
  /// seeing the first-launch intro again after a biometric cancel.
  /// Add any new "device memory" keys here, not auth-related ones.
  static const _preservedKeys = <String>{
    'has_seen_onboarding',
    'biometric_enabled',
    'age_verified',
    'birth_date',
    // Rating-prompt cadence is per-device, not per-login — keep it so
    // signing out doesn't reset the "ask after a week" timer.
    'rate_prompt_first_launch_v1',
    'rate_prompt_opens_v1',
    'rate_prompt_last_shown_v1',
    'rate_prompt_requests_v1',
  };

  static Future<void> clearAll() async {
    // Snapshot the keys we want to keep, wipe everything, then write
    // them back. flutter_secure_storage doesn't have a native
    // selective-clear so this is the cheapest robust approach.
    final preserved = <String, String>{};
    for (final key in _preservedKeys) {
      final value = await _storage.read(key: key);
      if (value != null) preserved[key] = value;
    }
    await _storage.deleteAll();
    for (final entry in preserved.entries) {
      await _storage.write(key: entry.key, value: entry.value);
    }
  }
}
