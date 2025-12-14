import 'package:flutter/material.dart';

// Defines the color scheme and styling for the application's dark theme.
class AppTheme {
  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: const Color(0xFF212121), // Dark grey for primary surfaces
    scaffoldBackgroundColor: const Color(0xFF121212), // Even darker for background
    hintColor: Colors.deepPurple.shade300, // A deep purple for accents
    fontFamily: 'Inter',

    // Define text styling for different elements.
    textTheme: const TextTheme(
      headlineSmall: TextStyle(fontSize: 24.0, fontWeight: FontWeight.bold, color: Colors.white),
      titleLarge: TextStyle(fontSize: 20.0, fontWeight: FontWeight.bold, color: Colors.white70),
      bodyMedium: TextStyle(fontSize: 14.0, color: Colors.white60),
      bodySmall: TextStyle(fontSize: 12.0, color: Colors.white54),
    ),

    // Define styling for icons.
    iconTheme: const IconThemeData(
      color: Colors.white70,
      size: 24.0,
    ),

    // Define styling for buttons.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.deepPurple.shade400, // Deep purple accent for buttons
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
      ),
    ),

    // Define styling for focus highlights, crucial for TV navigation.
    focusColor: Colors.white.withOpacity(0.9),

    colorScheme: ColorScheme.dark(
      primary: Colors.deepPurple,
      secondary: Colors.deepPurple.shade300, // Deep purple for secondary color
      surface: const Color(0xFF1F1F1F), // Slightly lighter grey for card surfaces
      onSurface: Colors.white,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
    ),
  );
}

