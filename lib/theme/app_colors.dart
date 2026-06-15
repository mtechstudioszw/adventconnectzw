import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color primaryBlue = Color(0xFF1565C0);
  static const Color darkNavy = Color(0xFF0D1B3E);
  static const Color white = Color(0xFFFFFFFF);
  static const Color lightGrey = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF1A1A2E);
  static const Color goldAccent = Color(0xFFC8A951);
  static const Color red = Color(0xFFD32F2F);
  static const Color successGreen = Color(0xFF2E7D32);

  // ---- Brightness-aware surfaces (NOT const) ----------------------------
  // For bespoke `Container`/`Material`/`BoxDecoration` fills that previously
  // hard-coded `white`/`lightGrey`. Updated by [AppTextStyles.applyBrightness]
  // (called from main.dart before each MaterialApp build), so context-less
  // helper methods can adapt to dark mode without threading a BuildContext.
  // Light values are byte-identical to the originals — light mode unchanged.
  // (Screens that already have a BuildContext should prefer `context.palette`.)
  static Color surface = white; // cards, sheets, dialogs
  static Color surfaceMuted = lightGrey; // nested / muted fills
  static Color scaffold = lightGrey; // screen canvas
  // Adaptive text/icon colours for callsites that hard-code `textDark`
  // directly (or via `.copyWith(color: AppColors.textDark)`), which bypass
  // the theme. Use `AppColors.text` / `AppColors.textMuted` instead so the
  // text flips to light in dark mode. Light values == the originals.
  static Color text = textDark;
  static Color textMuted = const Color.fromRGBO(26, 26, 46, 0.6);
  // Adaptive hairline/divider colour (was hard-coded Color.fromRGBO(26,26,46,~0.1)).
  static Color divider = const Color.fromRGBO(26, 26, 46, 0.1);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF1565C0), Color(0xFF1976D2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient appBarGradient = LinearGradient(
    colors: [Color(0xFF0D1B3E), Color(0xFF1A2F5A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
