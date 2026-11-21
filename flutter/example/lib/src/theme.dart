import 'package:flutter/material.dart';

/// The example's colors: near-black, softly lit surfaces, and an indigo to
/// violet accent.
abstract final class Palette {
  static const background = Color(0xFF07070C);
  static const surface = Color(0xFF111119);
  static const surfaceHigh = Color(0xFF1A1A25);
  static const border = Color(0x1FFFFFFF);
  static const text = Color(0xFFF5F5FA);
  static const muted = Color(0xFF9D9DB4);
  static const link = Color(0xFFB9A9FF);
  static const indigo = Color(0xFF6366F1);
  static const violet = Color(0xFF8B5CF6);
  static const purple = Color(0xFFA855F7);
  static const success = Color(0xFF34D399);
  static const danger = Color(0xFFF87171);

  static const accent = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [indigo, purple],
  );
}

OutlineInputBorder _border(Color color, {double width = 1}) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color, width: width),
    );

ThemeData appTheme() {
  const scheme = ColorScheme.dark(
    primary: Palette.violet,
    onPrimary: Colors.white,
    secondary: Palette.indigo,
    surface: Palette.surface,
    onSurface: Palette.text,
    onSurfaceVariant: Palette.muted,
    error: Palette.danger,
    outline: Palette.border,
    outlineVariant: Palette.border,
  );
  final base = ThemeData(colorScheme: scheme, brightness: Brightness.dark);
  final text = base.textTheme.apply(
    bodyColor: Palette.text,
    displayColor: Palette.text,
  );

  return base.copyWith(
    scaffoldBackgroundColor: Palette.background,
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      titleLarge: text.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Palette.text,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.surface,
      prefixIconColor: Palette.muted,
      labelStyle: const TextStyle(color: Palette.muted),
      floatingLabelStyle: const TextStyle(color: Palette.link),
      helperStyle: const TextStyle(color: Palette.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: _border(Palette.border),
      enabledBorder: _border(Palette.border),
      focusedBorder: _border(Palette.violet, width: 1.4),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(58),
        foregroundColor: Palette.text,
        side: const BorderSide(color: Palette.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: Palette.muted),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Palette.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: const BorderSide(color: Palette.border),
      ),
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      contentTextStyle: text.bodyMedium?.copyWith(
        color: Palette.muted,
        height: 1.45,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Palette.surfaceHigh,
      elevation: 0,
      contentTextStyle: const TextStyle(color: Palette.text, fontSize: 15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Palette.border),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Palette.violet,
    ),
  );
}
