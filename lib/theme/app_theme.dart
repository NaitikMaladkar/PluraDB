import 'package:flutter/material.dart';

class AppTheme {
  static const Color background = Color(0xFF0D0F12);
  static const Color surface = Color(0xFF161920);
  static const Color surfaceLight = Color(0xFF1E222A);
  static const Color accent = Color(0xFF00E5A0);
  static const Color accentDim = Color(0xFF00B87E);
  static const Color textPrimary = Color(0xFFE8ECF1);
  static const Color textSecondary = Color(0xFF8B95A5);
  static const Color textMuted = Color(0xFF555F6E);
  static const Color border = Color(0xFF2A2F3A);
  static const Color error = Color(0xFFEF4444);
  static const Color success = Color(0xFF00E5A0);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: accent,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: accentDim,
        surface: surface,
        error: error,
        onPrimary: background,
        onSurface: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        elevation: 0,
        titleTextStyle: TextStyle(color: textPrimary, fontSize: 18, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
        iconTheme: IconThemeData(color: textSecondary),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: border, width: 0.5),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceLight,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: accent, width: 1.5)),
        hintStyle: const TextStyle(color: textMuted, fontSize: 14),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: textPrimary, fontSize: 28, fontWeight: FontWeight.bold, fontFamily: 'Inter'),
        headlineMedium: TextStyle(color: textPrimary, fontSize: 22, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
        headlineSmall: TextStyle(color: textPrimary, fontSize: 18, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
        titleLarge: TextStyle(color: textPrimary, fontSize: 16, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
        titleMedium: TextStyle(color: textPrimary, fontSize: 14, fontWeight: FontWeight.w500, fontFamily: 'Inter'),
        bodyLarge: TextStyle(color: textPrimary, fontSize: 15, fontFamily: 'Inter'),
        bodyMedium: TextStyle(color: textSecondary, fontSize: 13, fontFamily: 'Inter'),
        bodySmall: TextStyle(color: textMuted, fontSize: 12, fontFamily: 'Inter'),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: background,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, fontFamily: 'Inter'),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: border),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: textMuted,
        indicatorColor: accent,
        dividerColor: border,
        labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, fontFamily: 'Inter'),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 13, fontFamily: 'Inter'),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 0.5),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceLight,
        contentTextStyle: const TextStyle(color: textPrimary, fontFamily: 'Inter'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: border)),
        titleTextStyle: const TextStyle(color: textPrimary, fontSize: 18, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
        contentTextStyle: const TextStyle(color: textSecondary, fontSize: 14, fontFamily: 'Inter'),
      ),
    );
  }
}
