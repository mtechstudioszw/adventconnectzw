import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTextStyles {
  AppTextStyles._();

  // Brightness-aware text colours. The LIGHT values are byte-identical to the
  // originals, so light mode is completely unchanged. The DARK values match
  // AppPalette.dark (.text / .textMuted). main.dart calls [applyBrightness]
  // before every MaterialApp build, so the hundreds of direct
  // `AppTextStyles.*` usages across the app adapt to dark mode automatically
  // — no per-screen text migration needed. (White button/app-bar styles stay
  // white; they sit on brand-coloured surfaces in both modes.)
  static const Color _lightBody = AppColors.textDark;
  static const Color _lightMuted = Color.fromRGBO(26, 26, 46, 0.6);
  static const Color _darkBody = Color(0xFFE8ECF5);
  static const Color _darkMuted = Color(0xFF9AA3BD);

  static Color _bodyColor = _lightBody;
  static Color _mutedColor = _lightMuted;

  /// Point the body/muted text colours at the active brightness. Called from
  /// main.dart's theme builder before MaterialApp builds its routes.
  static void applyBrightness(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    _bodyColor = dark ? _darkBody : _lightBody;
    _mutedColor = dark ? _darkMuted : _lightMuted;
    // Keep the context-less surface colours in sync (match AppPalette.dark).
    AppColors.surface = dark ? const Color(0xFF131A30) : AppColors.white;
    AppColors.surfaceMuted = dark ? const Color(0xFF1A2240) : AppColors.lightGrey;
    AppColors.scaffold = dark ? const Color(0xFF0B1124) : AppColors.lightGrey;
    AppColors.text = dark ? _darkBody : _lightBody;
    AppColors.textMuted = dark ? _darkMuted : _lightMuted;
  }

  static TextStyle get displayLarge => GoogleFonts.poppins(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: _bodyColor,
      );

  static TextStyle get displayMedium => GoogleFonts.poppins(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: _bodyColor,
      );

  static TextStyle get headlineLarge => GoogleFonts.poppins(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: _bodyColor,
      );

  static TextStyle get headlineMedium => GoogleFonts.poppins(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: _bodyColor,
      );

  static TextStyle get headlineSmall => GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: _bodyColor,
      );

  static TextStyle get titleLarge => GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: _bodyColor,
      );

  static TextStyle get titleMedium => GoogleFonts.poppins(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: _bodyColor,
      );

  static TextStyle get titleSmall => GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: _bodyColor,
      );

  static TextStyle get bodyLarge => GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: _bodyColor,
      );

  static TextStyle get bodyMedium => GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: _bodyColor,
      );

  static TextStyle get bodySmall => GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: _bodyColor,
      );

  static TextStyle get labelLarge => GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.white,
        letterSpacing: 0.5,
      );

  static TextStyle get labelMedium => GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: _bodyColor,
      );

  static TextStyle get labelSmall => GoogleFonts.poppins(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: _bodyColor,
      );

  static TextStyle get caption => GoogleFonts.poppins(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: _mutedColor,
      );

  static TextStyle get buttonText => GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.white,
        letterSpacing: 0.3,
      );

  static TextStyle get appBarTitle => GoogleFonts.poppins(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.white,
      );

  static TextStyle get overline => GoogleFonts.poppins(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: _bodyColor,
        letterSpacing: 1.2,
      );
}
