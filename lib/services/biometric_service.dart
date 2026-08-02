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
  static const _enabledKey = 'biometric_enabled';

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

  static Future<bool> isEnabled() async {
    final raw = await SecureStorageService.read(_enabledKey);
    final enabled = raw == 'true';
    _enabledCache = enabled;
    return enabled;
  }

  /// Prompt the user, then persist the choice. Returns true on success.
  /// Caller should reflect the result back into the toggle.
  static Future<bool> setEnabled(bool enabled) async {
    if (!enabled) {
      await SecureStorageService.write(_enabledKey, 'false');
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
        await SecureStorageService.write(_enabledKey, 'true');
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
