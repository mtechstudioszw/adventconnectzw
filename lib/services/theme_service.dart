import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'secure_storage_service.dart';

/// User-chosen colour scheme — mirrors Flutter's [ThemeMode] but lives
/// in secure storage so it survives a relaunch.
///
/// **Default is [ThemeMode.system]** (founder's call, 17 Aug 2026). It used
/// to be [ThemeMode.light], deliberately, because the palette is light-first
/// and a number of screens still hard-code `AppColors.white` /
/// `AppColors.lightGrey` instead of reading `context.palette`. Those screens
/// do not repaint cleanly, so following the system used to mean shipping
/// half-dark screens to anyone whose phone is in dark mode.
///
/// That trade has been taken deliberately: a member on a dark phone being
/// shown a stubbornly white app is the more visible fault. **The consequence
/// is that any remaining un-migrated screen is now reachable by default**, so
/// dark-mode bugs are live bugs rather than opt-in ones — two were reported
/// alongside this change (the interests chips in profile setup, and the
/// events icon).
///
/// So: when a colour looks wrong in dark mode, the fix is to migrate that
/// widget to `context.palette`, NOT to move this default back.
///
/// An explicit Light or Dark choice in Settings → Appearance still wins and
/// still persists; only the *unset* case changed.
class ThemeService {
  ThemeService._();

  static const _storageKey = 'app_theme_mode_v1';

  // Follow the phone on a fresh install. See the class doc for what this
  // trades away.
  static ThemeMode _current = ThemeMode.system;
  static final ValueNotifier<ThemeMode> _notifier =
      ValueNotifier(ThemeMode.system);
  static bool _initialized = false;

  /// Read the saved choice once at startup. Cheap secure-storage read;
  /// must finish before the first MaterialApp build so the user doesn't
  /// see a one-frame flash in the wrong theme.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final raw = await SecureStorageService.read(_storageKey);
    final mode = _parse(raw);
    _current = mode;
    _notifier.value = mode;
  }

  static ThemeMode get current => _current;
  static ValueListenable<ThemeMode> get notifier => _notifier;

  static Future<void> setMode(ThemeMode mode) async {
    if (mode == _current) return;
    _current = mode;
    _notifier.value = mode;
    await SecureStorageService.write(_storageKey, _encode(mode));
  }

  static ThemeMode _parse(String? raw) {
    switch (raw) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      default:
        // Covers null (never chosen) AND an unrecognised stored value. Must
        // match the field initialisers above, or a fresh install would
        // follow the phone until init() ran and then silently snap to light.
        return ThemeMode.system;
    }
  }

  static String _encode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.light:
        return 'light';
      case ThemeMode.system:
        return 'system';
    }
  }
}
