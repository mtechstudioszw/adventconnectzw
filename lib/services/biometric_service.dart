import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'secure_storage_service.dart';

/// Which sensor the device leads with. Drives the lock screen's glyph,
/// its instruction copy and the shape of its scanning animation — a
/// camera and a fingertip do not look like the same act.
enum BiometricKind { fingerprint, face, iris }

/// Wraps `local_auth` so screens don't have to know about platform
/// quirks. Used by the Settings → biometric toggle.
///
/// The biometric flag is stored in secure storage (not the profile row)
/// so we never have to round-trip the server to check whether to prompt
/// on app open.
class BiometricService {
  BiometricService._();

  static final LocalAuthentication _auth = LocalAuthentication();

  /// The pre-fix key: one flag for the whole PHONE. Kept only so an
  /// existing user's opt-in can be migrated onto their own key once; see
  /// [_resolveKey]. Never written again.
  static const _legacyEnabledKey = 'biometric_enabled';

  /// Per-account key. Biometric unlock guards a signed-in SESSION, so the
  /// setting belongs to the account, not the handset — with one shared
  /// flag, a second member signing in on the same phone inherited the
  /// first member's biometric gate (and a brand-new account arrived with
  /// unlock already switched on, which it never consented to).
  ///
  /// The prefix is preserved across sign-out by
  /// [SecureStorageService.preservedKeyPrefixes]: a namespaced key can't
  /// leak, because signing in as somebody else simply reads a different
  /// key and finds nothing — while the original account keeps its choice
  /// when it comes back to the same phone.
  static String _keyFor(String userId) => 'biometric_enabled:$userId';

  /// What the device will actually use, so the lock screen can show the
  /// right sensor and the right instruction. A phone that unlocks by face
  /// should not be told to touch a fingerprint sensor, and sonar ripples
  /// spreading from a fingertip are the wrong idea entirely for a camera.
  static BiometricKind? _kindCache;

  /// Last-known sensor kind, available synchronously once [primaryKind]
  /// has run at least once this launch.
  static BiometricKind? get kindCached => _kindCache;

  /// Which sensor this device leads with. `getAvailableBiometrics()` is a
  /// platform-channel round trip, so the result is cached for the launch —
  /// enrolled hardware does not change while the app is open.
  ///
  /// Face wins when both are present: on a phone with both, the camera
  /// fires first and the fingerprint is the fallback.
  static Future<BiometricKind> primaryKind() async {
    final cached = _kindCache;
    if (cached != null) return cached;
    try {
      final available = await _auth.getAvailableBiometrics();
      final kind = available.contains(BiometricType.face)
          ? BiometricKind.face
          : available.contains(BiometricType.iris)
          ? BiometricKind.iris
          : BiometricKind.fingerprint;
      _kindCache = kind;
      return kind;
    } on PlatformException catch (e) {
      debugPrint('BiometricService: primaryKind failed: $e');
      // Fingerprint is the safe default — it is the overwhelmingly common
      // sensor on the Android hardware this app actually runs on.
      return BiometricKind.fingerprint;
    }
  }

  /// Open the platform channel early so the FIRST [authenticate] call
  /// isn't also paying for channel setup + hardware enumeration. Called
  /// from the splash while the app is booting anyway. Never throws.
  static Future<void> prewarm() async {
    try {
      await primaryKind();
    } catch (_) {
      // Best-effort only: this exists to save milliseconds, never to gate.
    }
  }

  // In-memory mirror of the stored flag so the Settings toggle paints the
  // right state instantly instead of flashing off → on after the async read.
  // Populated by the first isEnabled() (the splash calls it at startup) and
  // kept in sync by setEnabled().
  static bool? _enabledCache;

  /// Last-known enabled state, available synchronously. Null until the first
  /// read/write this launch.
  static bool? get enabledCached => _enabledCache;

  /// Whether the device has fingerprint / face hardware enrolled. False
  /// on emulators with nothing enrolled — don't show the toggle.
  static Future<bool> isAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final canCheck = await _auth.canCheckBiometrics;
      return canCheck;
    } on PlatformException catch (e) {
      debugPrint('BiometricService: isAvailable failed: $e');
      return false;
    }
  }

  /// This account's storage key, or null when nobody is signed in.
  ///
  /// The id comes from secure storage rather than
  /// `Supabase.auth.currentUser` on purpose: the splash asks whether to
  /// show the lock screen BEFORE the session has finished refreshing, so
  /// `currentUser` can still be null for a user who is very much signed
  /// in. The persisted id is a local read, written on every sign-in path
  /// by `AuthService._persistSession` and wiped by `clearAll()`.
  ///
  /// Also performs the one-time migration off the old device-wide key:
  /// whoever is signed in on this phone is the member who switched
  /// biometrics on, so the flag is adopted onto their key and the shared
  /// one is deleted so it can never be inherited again.
  static Future<String?> _resolveKey() async {
    final userId = await SecureStorageService.getUserId();
    if (userId == null || userId.isEmpty) return null;
    final key = _keyFor(userId);
    final legacy = await SecureStorageService.read(_legacyEnabledKey);
    if (legacy != null) {
      if (await SecureStorageService.read(key) == null) {
        await SecureStorageService.write(key, legacy);
      }
      await SecureStorageService.delete(_legacyEnabledKey);
    }
    return key;
  }

  /// Whether THIS account opted into biometric unlock on THIS device.
  ///
  /// Signed out — or signed in as somebody who never opted in — is false,
  /// which is the safe direction: the worst case is being asked for a
  /// password instead of a fingerprint.
  static Future<bool> isEnabled() async {
    final key = await _resolveKey();
    if (key == null) {
      _enabledCache = false;
      return false;
    }
    final raw = await SecureStorageService.read(key);
    final enabled = raw == 'true';
    _enabledCache = enabled;
    return enabled;
  }

  /// Forget the signed-out account's biometric state.
  ///
  /// The stored flag is already namespaced per user, but [_enabledCache]
  /// is a plain static: without this the NEXT account inherits the last
  /// one's value for the rest of the app's life, since signing out does
  /// not restart the isolate.
  static void clearSessionOnSignOut() {
    _enabledCache = null;
  }

  /// Prompt the user, then persist the choice. Returns true on success.
  /// Caller should reflect the result back into the toggle.
  ///
  /// A no-op when signed out — there is no account to attach the choice
  /// to, and writing a device-wide flag is the bug this replaced.
  static Future<bool> setEnabled(bool enabled) async {
    final key = await _resolveKey();
    if (key == null) return false;
    if (!enabled) {
      await SecureStorageService.write(key, 'false');
      _enabledCache = false;
      return true;
    }
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Confirm with biometrics to enable quick unlock.',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      if (ok) {
        await SecureStorageService.write(key, 'true');
        _enabledCache = true;
      }
      return ok;
    } on PlatformException catch (e) {
      debugPrint('BiometricService: setEnabled failed: $e');
      return false;
    }
  }

  /// Prompt the user without changing the stored flag. Used at app
  /// resume when biometric_enabled is already true.
  static Future<bool> authenticate({
    String reason = 'Unlock Advent Connect ZW',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } on PlatformException catch (e) {
      debugPrint('BiometricService: authenticate failed: $e');
      return false;
    }
  }
}
