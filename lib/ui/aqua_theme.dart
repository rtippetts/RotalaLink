import 'package:flutter/material.dart';

ThemeData aquaTheme(ColorScheme cs) {
  final radius = 14.0;

  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: cs.background,

    appBarTheme: AppBarTheme(
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      elevation: 0,
      centerTitle: true,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cs.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: cs.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: cs.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
      labelStyle: TextStyle(color: cs.onSurface.withOpacity(.72)),
      hintStyle: TextStyle(color: cs.onSurface.withOpacity(.56)),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: cs.onSurface,
        side: BorderSide(color: cs.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: cs.primary,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
    ),

    cardTheme: CardThemeData(
      color: cs.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outline),
      ),
      margin: const EdgeInsets.all(12),
    ),

    dividerTheme: DividerThemeData(color: cs.outline, thickness: 1),

    textTheme: const TextTheme().copyWith(
      displaySmall:  TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface),
      titleLarge:    TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface),
      bodyMedium:    TextStyle(height: 1.35, color: cs.onSurface),
      labelLarge:    TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface),
    ),
  );
}
