import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'secure_storage_service.dart';

/// User-chosen colour scheme — mirrors Flutter's [ThemeMode] but lives
/// in secure storage so it survives a relaunch. The default is
/// [ThemeMode.light] — the app's brand palette is light-first and most
/// widgets still reference hard-coded `AppColors` values that don't
/// repaint cleanly in dark mode. Users on a dark phone can still flip
/// to dark via Settings; we just don't follow the system by default.
///
/// NOTE: This wires the toggle, but many widgets in the app still
/// reference hard-coded colours from [AppColors] (white, lightGrey,
/// etc.). Those screens won't fully repaint in dark mode until they're
/// migrated to read from `Theme.of(context).colorScheme`. The toggle
/// flips Material widgets (Scaffold, AppBar, Card, BottomNav, etc.)
/// correctly today and unblocks per-screen polish in a later pass.
class ThemeService {
  ThemeService._();

  static const _storageKey = 'app_theme_mode_v1';

  // Default to SYSTEM on a fresh install — the app matches the phone's
  // light/dark setting until the user explicitly picks Light or Dark in
  // Settings -> Appearance, after which that choice persists.
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
