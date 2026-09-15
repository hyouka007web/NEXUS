import 'package:flutter/material.dart';

/// Zentrales Farbschema für NEXUS — dunkles, flaches "Panel"-Design
/// im Stil von Vivaldi: fast schwarze Chrome-Flächen, eine kräftige
/// Akzentfarbe (Lime), farbige Tab-Indikatoren.
class NexusColors {
  NexusColors._();

  // Chrome / Panels
  static const Color background = Color(0xFF0B0C0A); // App-Hintergrund
  static const Color surface = Color(0xFF141610); // Sidebar / Tabstrip / Cards
  static const Color surfaceRaised = Color(0xFF1D2018); // Popups, Sheets
  static const Color divider = Color(0xFF2A2E24);

  // Akzent
  static const Color accent = Color(0xFFD7FF00); // NEXUS-Lime
  static const Color accentDim = Color(0xFF8FBF00);
  static const Color accentOnDark = Color(0xFFD7FF00);

  // Text
  static const Color textPrimary = Color(0xFFF2F5EC);
  static const Color textSecondary = Color(0xFFAAB2A0);
  static const Color textDisabled = Color(0xFF5A6152);

  // Status
  static const Color danger = Color(0xFFFF3B30);
  static const Color warning = Color(0xFFFFB020);
  static const Color success = Color(0xFF8FBF00);

  // Tab-Akzentfarben (rotierend, wie Vivaldis Tab-Farbcodierung je Domain)
  static const List<Color> tabAccents = [
    Color(0xFFD7FF00),
    Color(0xFF00E0D7),
    Color(0xFFFF6B6B),
    Color(0xFF6E8BFF),
    Color(0xFFFFA94D),
    Color(0xFFC792EA),
  ];

  static Color tabAccentFor(String key) {
    final idx = key.hashCode.abs() % tabAccents.length;
    return tabAccents[idx];
  }
}

class NexusTheme {
  NexusTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: NexusColors.background,
      colorScheme: base.colorScheme.copyWith(
        primary: NexusColors.accent,
        secondary: NexusColors.accentDim,
        surface: NexusColors.surface,
        error: NexusColors.danger,
        onPrimary: Colors.black,
        onSurface: NexusColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: NexusColors.surface,
        foregroundColor: NexusColors.textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      cardColor: NexusColors.surface,
      dividerColor: NexusColors.divider,
      textTheme: base.textTheme.apply(
        bodyColor: NexusColors.textPrimary,
        displayColor: NexusColors.textPrimary,
      ),
      iconTheme: const IconThemeData(color: NexusColors.textSecondary),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: NexusColors.accent,
          foregroundColor: Colors.black,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: NexusColors.surfaceRaised,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: NexusColors.textSecondary),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: NexusColors.accent,
        linearTrackColor: NexusColors.divider,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: NexusColors.surfaceRaised,
        contentTextStyle: TextStyle(color: NexusColors.textPrimary),
        behavior: SnackBarBehavior.floating,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: NexusColors.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
      ),
      splashFactory: InkRipple.splashFactory,
    );
  }
}
