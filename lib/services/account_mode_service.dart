import 'dart:async';
import 'package:flutter/foundation.dart';
import 'secure_storage_service.dart';

/// Which face of the app is the user currently looking at?
///
/// * `personal` — clean social experience. Selling / claiming a church
///   are hidden from the UI even if the underlying account is
///   approved as a business.
/// * `business` — full business experience. Only available to users
///   whose profile.is_business = true.
enum AppViewMode { personal, business }

/// In-process broadcaster of the current view mode. Persists the
/// chosen mode in flutter_secure_storage so it survives relaunch.
/// Screens that care about the mode listen to [stream] and rebuild.
class AccountModeService {
  AccountModeService._();

  static const _storageKey = 'app_view_mode_v1';

  static AppViewMode _current = AppViewMode.personal;
  static final ValueNotifier<AppViewMode> _notifier =
      ValueNotifier(AppViewMode.personal);
  static bool _initialized = false;

  /// Read the last saved mode from secure storage. Call once during
  /// app start (main.dart). Defaults to personal if no value stored.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final raw = await SecureStorageService.read(_storageKey);
    if (raw == 'business') {
      _current = AppViewMode.business;
      _notifier.value = AppViewMode.business;
    }
  }

  static AppViewMode get current => _current;
  static ValueListenable<AppViewMode> get notifier => _notifier;

  static Future<void> setMode(AppViewMode mode) async {
    if (mode == _current) return;
    _current = mode;
    _notifier.value = mode;
    await SecureStorageService.write(
      _storageKey,
      mode == AppViewMode.business ? 'business' : 'personal',
    );
  }

  /// Convenience: true when the current view is business mode. Use
  /// this to gate UI affordances that should only show when the user
  /// has explicitly switched into business.
  static bool get inBusinessMode => _current == AppViewMode.business;

  /// Reset to personal on sign-out so the next user starts clean.
  static Future<void> resetToPersonal() => setMode(AppViewMode.personal);
}
