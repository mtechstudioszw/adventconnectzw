import 'package:flutter/foundation.dart';
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
  ///
  /// NOTE: the bare `biometric_enabled` key used to live here. That made
  /// biometric unlock a property of the PHONE rather than of the account,
  /// so a second member signing in on the same handset inherited the
  /// first one's setting. It is now stored per user id — see
  /// [preservedKeyPrefixes] and `BiometricService`.
  static const _preservedKeys = <String>{
    'has_seen_onboarding',
    'age_verified',
    'birth_date',
    // Rating-prompt cadence is per-device, not per-login — keep it so
    // signing out doesn't reset the "ask after a week" timer.
    'rate_prompt_first_launch_v1',
    'rate_prompt_opens_v1',
    'rate_prompt_last_shown_v1',
    'rate_prompt_requests_v1',
  };

  /// Key PREFIXES that survive [clearAll], for settings that are stored
  /// once per user id rather than once per device.
  ///
  /// A namespaced key cannot leak: signing in as somebody else reads a
  /// different key and finds nothing, so the new account starts at the
  /// default. Keeping the entry means the ORIGINAL account still has its
  /// choice when it signs back in on the same phone.
  static const preservedKeyPrefixes = <String>{
    'biometric_enabled:',
  };

  static bool _isPreserved(String key) =>
      _preservedKeys.contains(key) ||
      preservedKeyPrefixes.any(key.startsWith);

  /// Does [key] survive a sign-out? Exposed so the rule can be tested
  /// without a platform channel — the plugin itself is not the part that
  /// was wrong, the contents of this set were.
  @visibleForTesting
  static bool debugIsPreserved(String key) => _isPreserved(key);

  static Future<void> clearAll() async {
    // Snapshot the keys we want to keep, wipe everything, then write
    // them back. flutter_secure_storage doesn't have a native
    // selective-clear so this is the cheapest robust approach.
    //
    // readAll() (rather than reading _preservedKeys one by one) is what
    // lets the prefixed per-user keys above be matched at all — we can't
    // enumerate them ahead of time because they carry a user id.
    Map<String, String> all;
    try {
      all = await _storage.readAll();
    } catch (_) {
      // If the whole store can't be read, fall back to the exact-match
      // set. Losing a preserved key is a nuisance; failing to wipe the
      // session is a security bug, so the wipe below still runs.
      all = <String, String>{};
      for (final key in _preservedKeys) {
        final value = await _storage.read(key: key);
        if (value != null) all[key] = value;
      }
    }
    final preserved = <String, String>{
      for (final entry in all.entries)
        if (_isPreserved(entry.key)) entry.key: entry.value,
    };
    await _storage.deleteAll();
    for (final entry in preserved.entries) {
      await _storage.write(key: entry.key, value: entry.value);
    }
  }
}
