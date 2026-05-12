import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'secure_storage_service.dart';

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
    return raw == 'true';
  }

  /// Prompt the user, then persist the choice. Returns true on success.
  /// Caller should reflect the result back into the toggle.
  static Future<bool> setEnabled(bool enabled) async {
    if (!enabled) {
      await SecureStorageService.write(_enabledKey, 'false');
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
