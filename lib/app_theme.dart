import 'package:flutter/material.dart';

/// Brand palette — taken straight from the logo gradient.
const Color kBrandPurple = Color(0xFFB026FF);
const Color kBrandRed = Color(0xFFE50914);
const LinearGradient kBrandGradient = LinearGradient(
  colors: [kBrandPurple, kBrandRed],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

// Defines the color scheme and styling for the application's dark theme.
class AppTheme {
  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: kBrandPurple,
    scaffoldBackgroundColor: const Color(0xFF0B0B0F),
    hintColor: kBrandPurple,
    fontFamily: 'Inter',

    // Define text styling for different elements.
    textTheme: const TextTheme(
      headlineSmall:
          TextStyle(fontSize: 24.0, fontWeight: FontWeight.bold, color: Colors.white),
      titleLarge:
          TextStyle(fontSize: 20.0, fontWeight: FontWeight.bold, color: Colors.white70),
      bodyMedium: TextStyle(fontSize: 14.0, color: Colors.white60),
      bodySmall: TextStyle(fontSize: 12.0, color: Colors.white54),
    ),

    iconTheme: const IconThemeData(color: Colors.white70, size: 24.0),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: kBrandPurple,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      ),
    ),

    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: kBrandPurple),

    // Focus highlight for TV navigation.
    focusColor: Colors.white.withValues(alpha: 0.9),

    colorScheme: const ColorScheme.dark(
      primary: kBrandPurple,
      secondary: kBrandRed,
      surface: Color(0xFF16161D),
      onSurface: Colors.white,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
    ),
  );
}
