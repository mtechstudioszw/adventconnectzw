import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Brightness-aware surface palette.
///
/// Backstory: every screen used to read raw `AppColors.lightGrey` /
/// `AppColors.white` for scaffold backgrounds, card fills, dividers
/// etc. That made the Light/Dark toggle in Settings only paint
/// Material-themed widgets — bespoke containers stayed light even in
/// dark mode. AppPalette centralises those semantic surface colours
/// so screens can do `context.palette.card` and get the right value
/// for whichever brightness is active.
///
/// Brand identity colours (primaryBlue, darkNavy, goldAccent, red,
/// successGreen) stay on [AppColors] — they're the identity, they
/// don't flip with brightness.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.scaffoldBg,
    required this.card,
    required this.cardMuted,
    required this.divider,
    required this.text,
    required this.textMuted,
    required this.sheet,
    required this.chipBg,
    required this.inputFill,
  });

  /// Solid background behind the scrolling content of a screen.
  /// Used by `Scaffold(backgroundColor:)`.
  final Color scaffoldBg;

  /// Surface of an elevated card, dialog, list tile, or modal sheet.
  /// In light mode this is `AppColors.white`; in dark mode it's a
  /// deep navy so cards still feel raised against the scaffold.
  final Color card;

  /// A subtler card variant — used for nested cards or section fills
  /// where [card] would visually fight the parent.
  final Color cardMuted;

  /// Horizontal hairline separator inside lists and sections.
  final Color divider;

  /// Primary body text colour.
  final Color text;

  /// Secondary / metadata text colour, used by timestamps, helper
  /// captions, and the muted parts of list rows.
  final Color textMuted;

  /// Background of bottom sheets / modal sheets when they want a
  /// touch more contrast than [card].
  final Color sheet;

  /// Background of filter / category chips (Selectable Choice chips).
  final Color chipBg;

  /// Fill colour of `TextField` / `InputDecorator` boxes.
  final Color inputFill;

  /// Light-mode palette — preserves the existing visual design so the
  /// pre-dark-mode look is byte-for-byte unchanged.
  static const AppPalette light = AppPalette(
    scaffoldBg: AppColors.lightGrey,
    card: AppColors.white,
    cardMuted: AppColors.lightGrey,
    divider: Color.fromRGBO(26, 26, 46, 0.10),
    text: AppColors.textDark,
    textMuted: Color.fromRGBO(26, 26, 46, 0.60),
    sheet: AppColors.white,
    chipBg: AppColors.lightGrey,
    inputFill: AppColors.white,
  );

  /// Dark-mode palette — matches the deep navy `_darkBg` / `_darkSurface`
  /// values already used in `AppTheme.dark` so theme-aware Material
  /// widgets and palette-aware bespoke widgets stay in sync.
  static const AppPalette dark = AppPalette(
    scaffoldBg: Color(0xFF0B1124),
    card: Color(0xFF131A30),
    cardMuted: Color(0xFF1A2240),
    divider: Color.fromRGBO(232, 236, 245, 0.12),
    text: Color(0xFFE8ECF5),
    textMuted: Color(0xFF9AA3BD),
    sheet: Color(0xFF131A30),
    chipBg: Color(0xFF1A2240),
    inputFill: Color(0xFF131A30),
  );

  @override
  AppPalette copyWith({
    Color? scaffoldBg,
    Color? card,
    Color? cardMuted,
    Color? divider,
    Color? text,
    Color? textMuted,
    Color? sheet,
    Color? chipBg,
    Color? inputFill,
  }) {
    return AppPalette(
      scaffoldBg: scaffoldBg ?? this.scaffoldBg,
      card: card ?? this.card,
      cardMuted: cardMuted ?? this.cardMuted,
      divider: divider ?? this.divider,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      sheet: sheet ?? this.sheet,
      chipBg: chipBg ?? this.chipBg,
      inputFill: inputFill ?? this.inputFill,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      scaffoldBg: Color.lerp(scaffoldBg, other.scaffoldBg, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardMuted: Color.lerp(cardMuted, other.cardMuted, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      sheet: Color.lerp(sheet, other.sheet, t)!,
      chipBg: Color.lerp(chipBg, other.chipBg, t)!,
      inputFill: Color.lerp(inputFill, other.inputFill, t)!,
    );
  }
}

/// Ergonomic `context.palette` accessor. Falls back to the light
/// palette if the extension wasn't registered (shouldn't happen in
/// production but keeps tests + previews running).
extension AppPaletteContext on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}
