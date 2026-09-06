import 'package:flutter/material.dart';

/// Design-Tokens direkt aus der alten `design.md` des Kotlin-NEXUS
/// übernommen — Farben, Formen, Bewegungsdauern. Wer die Werte ändern will,
/// ändert sie hier zentral statt verstreut in den Screens.
class NexusColors {
  NexusColors._();

  static const bgBase = Color(0xFF1E1E1E);
  static const bgSurface = Color(0xFF2E3033);
  static const bgSurfaceRaised = Color(0xFF3A3D40);
  static const bgPill = Color(0xFF252729); // Suchleiste / Startseiten-Fläche
  static const accentPrimary = Color(0xFFFFB800);
  static const accentPrimarySoft = Color(0x40FFB800);
  static const accentSuccess = Color(0xFF00FF66);
  static const accentDanger = Color(0xFFFF3B3B);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textMuted = Color(0xFFA0A0A0);
  static const border = Color(0xFF3F4245);
}

class NexusRadii {
  NexusRadii._();

  static const button = 14.0;
  static const panel = 18.0;
  static const pill = 28.0; // voll rund auf einem 52–56dp hohen Element
  static const sidebarCollapsedWidth = 28.0; // Pfeil bleibt sicht-/tippbar
}

class NexusMotion {
  NexusMotion._();

  static const sidebar = Duration(milliseconds: 180);
  static const bottomPanel = Duration(milliseconds: 220);
  static const loadingTrace = Duration(milliseconds: 500);
}

/// Fertiges ThemeData für die MaterialApp — dark-mode-only, wie im Original
/// ("Dark-mode only" in design.md), keine Light-Variante vorgesehen.
ThemeData buildNexusTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: NexusColors.accentPrimary,
    brightness: Brightness.dark,
    surface: NexusColors.bgSurface,
    onSurface: NexusColors.textPrimary,
    primary: NexusColors.accentPrimary,
    error: NexusColors.accentDanger,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: NexusColors.bgBase,
    colorScheme: colorScheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: NexusColors.bgBase,
      foregroundColor: NexusColors.textPrimary,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: NexusColors.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NexusRadii.panel),
      ),
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: NexusColors.textPrimary),
      bodySmall: TextStyle(color: NexusColors.textMuted),
    ),
    dividerColor: NexusColors.border,
  );
}
