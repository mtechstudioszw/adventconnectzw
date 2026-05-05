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
