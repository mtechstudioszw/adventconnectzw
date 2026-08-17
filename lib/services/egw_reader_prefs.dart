import 'dart:async';

import 'package:flutter/material.dart';

import 'cache_service.dart';

/// The three reading grounds a book reader is expected to offer.
///
/// Sepia is not decoration — it is the setting most people actually read
/// long-form on, and its absence is part of what made the EGW shelf feel
/// like a PDF viewer rather than a book. A PDF could never have these: its
/// pages are rendered images, so the best it could do was invert them.
enum EgwReadingTheme { day, sepia, night }

/// Palette for one reading ground. Deliberately its own thing rather than
/// `AppPalette`: a reader's page is not the app's scaffold, and sepia has
/// no equivalent anywhere else in the app.
@immutable
class EgwReadingPalette {
  const EgwReadingPalette({
    required this.page,
    required this.text,
    required this.muted,
    required this.accent,
    required this.rule,
    required this.highlight,
  });

  /// The page itself. Warm off-white and warm near-black, never pure
  /// #FFFFFF or #000000 — pure values are what make long reading tiring.
  final Color page;
  final Color text;
  final Color muted;

  /// Chapter numbers, scripture links, the page-number rail.
  final Color accent;
  final Color rule;

  /// Wash behind highlighted text.
  final Color highlight;

  Brightness get brightness =>
      page.computeLuminance() > 0.5 ? Brightness.light : Brightness.dark;

  static const day = EgwReadingPalette(
    page: Color(0xFFFCFCFD),
    text: Color(0xFF1A1A2E),
    muted: Color(0xFF6B7086),
    accent: Color(0xFF1565C0),
    rule: Color(0x141A1A2E),
    highlight: Color(0x33C8A951),
  );

  static const sepia = EgwReadingPalette(
    page: Color(0xFFF6EEDF),
    text: Color(0xFF3A2F21),
    muted: Color(0xFF8A7A63),
    accent: Color(0xFF8A6A1F),
    rule: Color(0x1F3A2F21),
    highlight: Color(0x4DC8A951),
  );

  static const night = EgwReadingPalette(
    page: Color(0xFF0F1319),
    text: Color(0xFFDCE0E8),
    muted: Color(0xFF8A90A0),
    accent: Color(0xFF6FA8F5),
    rule: Color(0x1FDCE0E8),
    highlight: Color(0x40C8A951),
  );

  static EgwReadingPalette of(EgwReadingTheme theme) => switch (theme) {
    EgwReadingTheme.day => day,
    EgwReadingTheme.sepia => sepia,
    EgwReadingTheme.night => night,
  };
}

/// Reader settings, persisted per DEVICE.
///
/// Every key is `pref:`-prefixed on purpose. `CacheService.writePref` does
/// NOT add the prefix for you, and `clearUserData()` deletes anything
/// without it on every sign-out — which has already silently broken two
/// shipped features. Type size and reading ground belong to the handset and
/// the person's eyes, not to the account, so they must survive a sign-out.
class EgwReaderPrefs {
  EgwReaderPrefs._();

  static const _kTheme = 'pref:egw_reader_theme';
  static const _kScale = 'pref:egw_reader_scale';

  /// Rebuilds open readers when the settings sheet changes something.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// The chosen ground and type size, held in memory as well as on disk.
  ///
  /// This is what makes the controls answer the finger. Reported 18 Aug
  /// 2026 as *"text size, day, sepia dosent work"*: both setters used to
  /// `await` a Hive write and only bump [revision] afterwards, so the page
  /// could not change until the handset had finished writing. Hive
  /// serialises a box behind a single queue and `CacheService.initialize()`
  /// starts a prune + `compact()` of a box that grows on every feed
  /// refresh — so that await is not free on a real phone, and while it is
  /// outstanding the page, the swatches and the slider thumb all sit
  /// exactly where they were. From the outside that is a dead button.
  ///
  /// So the value moves first and the disk catches up. Storage is now a
  /// record of the choice rather than a gate on it.
  static EgwReadingTheme? _theme;
  static double? _scale;

  @visibleForTesting
  static void resetForTest() {
    _theme = null;
    _scale = null;
    revision.value = 0;
  }

  /// Persist without ever making the UI wait, and without letting a storage
  /// failure reach a member who only tapped "Sepia" — the setting still
  /// applies for this session either way.
  /// Called, not awaited. `writePref` updates Hive's in-memory keystore
  /// before its first `await`, so a read taken on this same frame already
  /// sees the new value — only the flush to disk is left outstanding, and
  /// nothing on screen depends on it.
  static void _persist(String key, String value) {
    unawaited(
      CacheService.writePref(key, value).catchError(
        (Object e) => debugPrint('EgwReaderPrefs: could not persist $key: $e'),
      ),
    );
  }

  static EgwReadingTheme theme() {
    final chosen = _theme;
    if (chosen != null) return chosen;
    final raw = CacheService.readPref(_kTheme);
    return EgwReadingTheme.values.firstWhere(
      (t) => t.name == raw,
      orElse: () => EgwReadingTheme.day,
    );
  }

  static void setTheme(EgwReadingTheme theme) {
    _theme = theme;
    revision.value++;
    _persist(_kTheme, theme.name);
  }

  /// Type scale. Clamped: below 0.8 the measure gets absurdly wide and
  /// above 1.6 a long word cannot fit the column at all.
  static const double minScale = 0.8;
  static const double maxScale = 1.6;

  static double scale() {
    final chosen = _scale;
    if (chosen != null) return chosen;
    final raw = double.tryParse(CacheService.readPref(_kScale) ?? '');
    return (raw ?? 1.0).clamp(minScale, maxScale);
  }

  static void setScale(double value) {
    final v = value.clamp(minScale, maxScale);
    if (v == scale()) return;
    _scale = v;
    revision.value++;
    _persist(_kScale, v.toStringAsFixed(2));
  }

  /// Resolves the reading ground for a book opened right now.
  ///
  /// A member who has never touched the setting should not be handed a
  /// glaring white page inside a dark app — that was the whole "dark mode
  /// doesn't work in EGW" complaint. So an untouched preference follows the
  /// app; an explicit choice always wins.
  static EgwReadingTheme resolve(BuildContext context) {
    // An in-memory choice counts as explicit even before it has landed on
    // disk — otherwise the ground would snap back to the app's brightness
    // on the very next frame after a tap.
    if (_theme != null || CacheService.readPref(_kTheme) != null) {
      return theme();
    }
    return Theme.of(context).brightness == Brightness.dark
        ? EgwReadingTheme.night
        : EgwReadingTheme.day;
  }
}
