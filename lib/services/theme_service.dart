import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'secure_storage_service.dart';

/// User-chosen colour scheme — mirrors Flutter's [ThemeMode] but lives
/// in secure storage so it survives a relaunch. The default is
/// [ThemeMode.system] so users on a dark phone get a dark app right
/// out of the box; settings can override either way.
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
