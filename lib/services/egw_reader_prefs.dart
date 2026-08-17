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

  static EgwReadingTheme theme() {
    final raw = CacheService.readPref(_kTheme);
    return EgwReadingTheme.values.firstWhere(
      (t) => t.name == raw,
      orElse: () => EgwReadingTheme.day,
    );
  }

  static Future<void> setTheme(EgwReadingTheme theme) async {
    await CacheService.writePref(_kTheme, theme.name);
    revision.value++;
  }

  /// Type scale. Clamped: below 0.8 the measure gets absurdly wide and
  /// above 1.6 a long word cannot fit the column at all.
  static const double minScale = 0.8;
  static const double maxScale = 1.6;

  static double scale() {
    final raw = double.tryParse(CacheService.readPref(_kScale) ?? '');
    return (raw ?? 1.0).clamp(minScale, maxScale);
  }

  static Future<void> setScale(double value) async {
    final v = value.clamp(minScale, maxScale);
    await CacheService.writePref(_kScale, v.toStringAsFixed(2));
    revision.value++;
  }

  /// Resolves the reading ground for a book opened right now.
  ///
  /// A member who has never touched the setting should not be handed a
  /// glaring white page inside a dark app — that was the whole "dark mode
  /// doesn't work in EGW" complaint. So an untouched preference follows the
  /// app; an explicit choice always wins.
  static EgwReadingTheme resolve(BuildContext context) {
    if (CacheService.readPref(_kTheme) != null) return theme();
    return Theme.of(context).brightness == Brightness.dark
        ? EgwReadingTheme.night
        : EgwReadingTheme.day;
  }
}
