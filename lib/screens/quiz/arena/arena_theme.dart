import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

/// Visual tokens for the Quiz **Arena** — the quiz section's own world.
///
/// Why this exists instead of `context.palette`: the Arena is deliberately
/// ALWAYS dark navy, in both light and dark app themes, exactly like the
/// stories viewer or a video player. That single decision is what makes
/// tapping "Quiz" feel like opening a different app rather than pushing
/// another screen. Every other new screen still follows the palette rule —
/// this one is the documented exception.
///
/// Everything here is derived from the brand scheme in CLAUDE.md. The two
/// `...OnNavy` colours are the SAME hues as `AppColors.successGreen` /
/// `AppColors.red`, lifted in lightness so they're legible against a deep
/// navy canvas — tints of the scheme, not new colours in it.
class ArenaTheme {
  ArenaTheme._();

  // ---- Canvas -------------------------------------------------------------

  /// Top of the arena canvas — the brand's Dark Navy.
  static const Color canvasTop = AppColors.darkNavy; // #0D1B3E

  /// Bottom of the arena canvas — navy pushed deeper so the gradient reads.
  static const Color canvasBottom = Color(0xFF060C1F);

  /// The full-screen backdrop gradient.
  static const LinearGradient canvas = LinearGradient(
    colors: [canvasTop, canvasBottom],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// A brighter navy used for the glow that follows the answer state.
  static const Color canvasLift = Color(0xFF16295C);

  // ---- Glass surfaces -----------------------------------------------------

  /// Fill of a raised "glass" panel on the canvas (question card, tiles).
  static const Color glass = Color(0x14FFFFFF); // white @ 8%

  /// A slightly stronger glass for elements that must separate from a
  /// panel they sit inside.
  static const Color glassStrong = Color(0x1FFFFFFF); // white @ 12%

  /// Hairline around glass panels.
  static const Color glassBorder = Color(0x26FFFFFF); // white @ 15%

  /// Border for the element the user is about to act on.
  static const Color glassBorderActive = Color(0x59FFFFFF); // white @ 35%

  // ---- Text ---------------------------------------------------------------

  static const Color textOnNavy = Color(0xFFF2F5FC);
  static const Color textMutedOnNavy = Color(0xB3F2F5FC); // 70%
  static const Color textFaintOnNavy = Color(0x80F2F5FC); // 50%

  // ---- Semantic state -----------------------------------------------------

  /// `AppColors.successGreen` (#2E7D32) at the lightness it needs to be
  /// readable on navy. Same hue (123°) — used for the correct-answer
  /// border, check badge and label only. Never as a page background.
  static const Color correctOnNavy = Color(0xFF41C864);

  /// `AppColors.red` (#D32F2F) lifted for the same reason. Wrong answers
  /// and the final seconds of the timer only.
  static const Color wrongOnNavy = Color(0xFFF2564B);

  /// The celebration colour. Gold carries score, combo, stars and every
  /// particle burst — on navy it reads far richer than a green splash.
  static const Color gold = AppColors.goldAccent;

  /// Gold pushed warm for gradient ends and glows.
  static const Color goldBright = Color(0xFFE8CE7A);

  static const LinearGradient goldGradient = LinearGradient(
    colors: [goldBright, gold],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient blueGradient = AppColors.primaryGradient;

  /// Fill behind the primary action in the arena.
  static const LinearGradient actionGradient = LinearGradient(
    colors: [Color(0xFF2B7FE0), AppColors.primaryBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ---- Shape --------------------------------------------------------------

  static const double radiusCard = 22;
  static const double radiusTile = 16;
  static const double radiusPill = 999;

  static BorderRadius get cardRadius => BorderRadius.circular(radiusCard);
  static BorderRadius get tileRadius => BorderRadius.circular(radiusTile);

  /// Soft lift under a glass panel.
  static List<BoxShadow> get panelShadow => const [
        BoxShadow(
          color: Color(0x59000000),
          blurRadius: 24,
          offset: Offset(0, 10),
        ),
      ];

  /// A coloured glow, used when an answer resolves.
  static List<BoxShadow> glow(Color color, {double strength = 1}) => [
        BoxShadow(
          color: color.withValues(alpha: 0.34 * strength),
          blurRadius: 22 * strength,
          spreadRadius: 1 * strength,
        ),
      ];

  // ---- Difficulty ---------------------------------------------------------

  /// Colour for a difficulty label. Stays inside the scheme: blue for the
  /// easy end, gold for hard.
  static Color difficulty(String value) {
    switch (value) {
      case 'easy':
        return const Color(0xFF6FA8E8);
      case 'hard':
        return gold;
      default:
        return const Color(0xFF9EC0EC);
    }
  }
}
