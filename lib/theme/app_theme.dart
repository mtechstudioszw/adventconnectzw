import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:google_fonts/google_fonts.dart';
import '../widgets/motion/page_transitions.dart';
import 'app_colors.dart';
import 'app_palette.dart';
import 'app_text_styles.dart';

/// App-wide route transition: custom brand fade-through on Android (and
/// desktop), native Cupertino slide on iOS/macOS so the edge-swipe back
/// gesture keeps working. Every GoRoute builds a MaterialPage, which
/// reads this — so ALL routes animate consistently with zero per-route
/// wiring.
const PageTransitionsTheme _brandPageTransitions = PageTransitionsTheme(
  builders: <TargetPlatform, PageTransitionsBuilder>{
    TargetPlatform.android: BrandFadeThroughTransitionsBuilder(),
    TargetPlatform.fuchsia: BrandFadeThroughTransitionsBuilder(),
    TargetPlatform.linux: BrandFadeThroughTransitionsBuilder(),
    TargetPlatform.windows: BrandFadeThroughTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
  },
);

/// Builder for `showDatePicker` / `showTimePicker` / `showDateRangePicker`
/// that keeps the brand-blue accent but follows the ACTIVE brightness — so
/// pickers render dark in dark mode instead of a glaring white calendar.
/// Several screens previously forced `ColorScheme.light(...)` here, which
/// left a white picker (and sometimes invisible text) on a dark app.
Widget brandPickerBuilder(BuildContext context, Widget? child) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final scheme = (dark ? const ColorScheme.dark() : const ColorScheme.light())
      .copyWith(
    primary: AppColors.primaryBlue,
    onPrimary: AppColors.white,
  );
  return Theme(
    data: Theme.of(context).copyWith(colorScheme: scheme),
    child: child ?? const SizedBox.shrink(),
  );
}

class AppTheme {
  AppTheme._();

  // Dark-mode surface palette. Kept private so screens keep using
  // [AppColors] for the light defaults; the dark theme below substitutes
  // these into the Material widgets that respect ColorScheme/ThemeData.
  static const Color _darkBg = Color(0xFF0B1124);
  static const Color _darkSurface = Color(0xFF131A30);
  static const Color _darkSurfaceAlt = Color(0xFF1A2240);
  static const Color _darkOnSurface = Color(0xFFE8ECF5);
  static const Color _darkOnSurfaceMuted = Color(0xFF9AA3BD);

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        pageTransitionsTheme: _brandPageTransitions,
        extensions: const <ThemeExtension<dynamic>>[AppPalette.light],
        colorScheme: const ColorScheme.light(
          primary: AppColors.primaryBlue,
          onPrimary: AppColors.white,
          secondary: AppColors.goldAccent,
          onSecondary: AppColors.white,
          error: AppColors.red,
          onError: AppColors.white,
          surface: AppColors.white,
          onSurface: AppColors.textDark,
        ),
        scaffoldBackgroundColor: AppColors.lightGrey,
        textTheme: GoogleFonts.poppinsTextTheme().copyWith(
          displayLarge: AppTextStyles.displayLarge,
          displayMedium: AppTextStyles.displayMedium,
          headlineLarge: AppTextStyles.headlineLarge,
          headlineMedium: AppTextStyles.headlineMedium,
          headlineSmall: AppTextStyles.headlineSmall,
          titleLarge: AppTextStyles.titleLarge,
          titleMedium: AppTextStyles.titleMedium,
          titleSmall: AppTextStyles.titleSmall,
          bodyLarge: AppTextStyles.bodyLarge,
          bodyMedium: AppTextStyles.bodyMedium,
          bodySmall: AppTextStyles.bodySmall,
          labelLarge: AppTextStyles.labelLarge,
          labelMedium: AppTextStyles.labelMedium,
          labelSmall: AppTextStyles.labelSmall,
        ),
        // Flat, single-colour header: the app bar shares the scaffold
        // background so the screen reads as one continuous colour from the
        // status bar down (WhatsApp-style). scrolledUnderElevation +
        // surfaceTintColor are pinned so M3 never tints the bar on scroll.
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.lightGrey,
          foregroundColor: AppColors.darkNavy,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          centerTitle: false,
          titleTextStyle:
              AppTextStyles.appBarTitle.copyWith(color: AppColors.darkNavy),
          iconTheme: const IconThemeData(color: AppColors.darkNavy),
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryBlue,
            foregroundColor: AppColors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: AppTextStyles.buttonText,
            elevation: 0,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primaryBlue,
            minimumSize: const Size(double.infinity, 52),
            side: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primaryBlue,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color.fromRGBO(26, 26, 46, 0.2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color.fromRGBO(26, 26, 46, 0.2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.red),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.red, width: 1.5),
          ),
          hintStyle: AppTextStyles.bodyMedium.copyWith(
            color: const Color.fromRGBO(26, 26, 46, 0.4),
          ),
          labelStyle: AppTextStyles.labelMedium,
          errorStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.red),
        ),
        cardTheme: CardThemeData(
          color: AppColors.white,
          elevation: 2,
          shadowColor: const Color.fromRGBO(26, 26, 46, 0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          margin: EdgeInsets.zero,
        ),
        dividerTheme: const DividerThemeData(
          color: Color.fromRGBO(26, 26, 46, 0.1),
          thickness: 1,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.darkNavy,
          contentTextStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          behavior: SnackBarBehavior.floating,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.white,
          selectedItemColor: AppColors.primaryBlue,
          unselectedItemColor: Color(0xFF9E9E9E),
          type: BottomNavigationBarType.fixed,
          elevation: 8,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.lightGrey,
          selectedColor: AppColors.primaryBlue,
          labelStyle: AppTextStyles.labelMedium,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: AppColors.white,
          elevation: 4,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: AppColors.primaryBlue,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          titleTextStyle: AppTextStyles.headlineSmall,
          contentTextStyle: AppTextStyles.bodyMedium,
        ),
      );

  /// Dark counterpart. Brand blue / navy / gold stay the same — they're
  /// the identity. What changes are surfaces (scaffold, card, sheet,
  /// input fill) and the default text colour, so anything that reads
  /// from Theme/ColorScheme adapts. Hardcoded `AppColors.white` /
  /// `AppColors.lightGrey` callsites in individual widgets will still
  /// appear light until those screens are migrated.
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        pageTransitionsTheme: _brandPageTransitions,
        extensions: const <ThemeExtension<dynamic>>[AppPalette.dark],
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primaryBlue,
          onPrimary: AppColors.white,
          secondary: AppColors.goldAccent,
          onSecondary: AppColors.white,
          error: AppColors.red,
          onError: AppColors.white,
          surface: _darkSurface,
          onSurface: _darkOnSurface,
        ),
        scaffoldBackgroundColor: _darkBg,
        textTheme: GoogleFonts.poppinsTextTheme(
          ThemeData(brightness: Brightness.dark).textTheme,
        ).copyWith(
          displayLarge: AppTextStyles.displayLarge.copyWith(color: _darkOnSurface),
          displayMedium: AppTextStyles.displayMedium.copyWith(color: _darkOnSurface),
          headlineLarge: AppTextStyles.headlineLarge.copyWith(color: _darkOnSurface),
          headlineMedium: AppTextStyles.headlineMedium.copyWith(color: _darkOnSurface),
          headlineSmall: AppTextStyles.headlineSmall.copyWith(color: _darkOnSurface),
          titleLarge: AppTextStyles.titleLarge.copyWith(color: _darkOnSurface),
          titleMedium: AppTextStyles.titleMedium.copyWith(color: _darkOnSurface),
          titleSmall: AppTextStyles.titleSmall.copyWith(color: _darkOnSurface),
          bodyLarge: AppTextStyles.bodyLarge.copyWith(color: _darkOnSurface),
          bodyMedium: AppTextStyles.bodyMedium.copyWith(color: _darkOnSurface),
          bodySmall: AppTextStyles.bodySmall.copyWith(color: _darkOnSurfaceMuted),
          labelLarge: AppTextStyles.labelLarge.copyWith(color: _darkOnSurface),
          labelMedium: AppTextStyles.labelMedium.copyWith(color: _darkOnSurface),
          labelSmall: AppTextStyles.labelSmall.copyWith(color: _darkOnSurfaceMuted),
        ),
        // Flat, single-colour header (see light theme note) — in dark mode the
        // bar matches the dark scaffold so the screen stays one colour.
        appBarTheme: AppBarTheme(
          backgroundColor: _darkBg,
          foregroundColor: _darkOnSurface,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          centerTitle: false,
          titleTextStyle:
              AppTextStyles.appBarTitle.copyWith(color: _darkOnSurface),
          iconTheme: const IconThemeData(color: _darkOnSurface),
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryBlue,
            foregroundColor: AppColors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: AppTextStyles.buttonText,
            elevation: 0,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primaryBlue,
            minimumSize: const Size(double.infinity, 52),
            side: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: AppColors.primaryBlue),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _darkSurfaceAlt,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: _darkOnSurfaceMuted.withValues(alpha: 0.4)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: _darkOnSurfaceMuted.withValues(alpha: 0.4)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.red),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.red, width: 1.5),
          ),
          hintStyle: AppTextStyles.bodyMedium.copyWith(
            color: _darkOnSurfaceMuted,
          ),
          labelStyle: AppTextStyles.labelMedium.copyWith(color: _darkOnSurface),
          errorStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.red),
        ),
        cardTheme: CardThemeData(
          color: _darkSurface,
          elevation: 2,
          shadowColor: Colors.black.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          margin: EdgeInsets.zero,
        ),
        dividerTheme: DividerThemeData(
          color: _darkOnSurfaceMuted.withValues(alpha: 0.18),
          thickness: 1,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: _darkSurfaceAlt,
          contentTextStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          behavior: SnackBarBehavior.floating,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: _darkSurface,
          selectedItemColor: AppColors.primaryBlue,
          unselectedItemColor: _darkOnSurfaceMuted,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: _darkSurfaceAlt,
          selectedColor: AppColors.primaryBlue,
          labelStyle: AppTextStyles.labelMedium.copyWith(color: _darkOnSurface),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: AppColors.white,
          elevation: 4,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: AppColors.primaryBlue,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: _darkSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          titleTextStyle: AppTextStyles.headlineSmall.copyWith(color: _darkOnSurface),
          contentTextStyle: AppTextStyles.bodyMedium.copyWith(color: _darkOnSurface),
        ),
      );
}
