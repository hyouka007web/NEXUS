import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// NEXUS Design Tokens (Master-Spec Kapitel 5) + Energy-Gradient-System
/// (Kapitel 4). Basis bleibt Schwarz/Dunkelgrau; Gelb→Lime→Grün wird NICHT
/// als drei getrennte Flächenfarben verwendet, sondern als ein
/// durchgehender Verlauf für aktive/energiegeladene Zustände
/// (aktive Tabs, Fokus, Hover, Progress, Harvest-Aktivität, Glow).
class NexusColors {
  NexusColors._();

  // --- Bestehende NEXUS-Tokens (aus dem Master-Prompt übernommen) ---
  static const Color chromeStructure = Color(0xFFFFB800); // Gold/Yellow-Struktur
  static const Color chromeEnergy = Color(0xFF00FF66); // Grün-Energie
  static const Color chromeDanger = Color(0xFFFF3B3B);

  static const Color bgBase = Color(0xFF1E1E1E);
  static const Color bgSurface = Color(0xFF2E3033);
  static const Color raised = Color(0xFF3A3D40);

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textMuted = Color(0xFFA0A0A0);
  static const Color textDisabled = Color(0xFF6A6D70);

  static const Color borderHairline = Color(0xFF3F4245);

  // --- Erweiterung: die drei Verlaufs-Stationen des Energy-Gradient ---
  static const Color energyYellow = Color(0xFFFFD400);
  static const Color energyGold = Color(0xFFFFB800); // = chromeStructure
  static const Color energyLime = Color(0xFFA8FF00);
  static const Color energyGreen = Color(0xFF00FF66); // = chromeEnergy

  static const Color danger = chromeDanger;
  static const Color background = bgBase;
  static const Color surface = bgSurface;
  static const Color surfaceRaised = raised;
  static const Color divider = borderHairline;

  /// Der durchgehende NEXUS-Energy-Gradient: eine einzige Lichtenergie,
  /// die durch das UI fließt (Yellow → Gold → Lime → Green → Lime → Yellow).
  static const LinearGradient energyGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [energyYellow, energyGold, energyLime, energyGreen, energyLime, energyGold],
  );

  /// Kompaktere 2-Stopp-Variante für schmale Elemente (Tab-Unterstrich, Border).
  static const LinearGradient energyGradientCompact = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [energyGold, energyGreen],
  );

  /// Radialer Glow-Gradient für Fokus-/Hover-Zustände (z.B. hinter Icons).
  static RadialGradient energyGlow({double opacity = 0.35}) => RadialGradient(
        colors: [energyLime.withOpacity(opacity), energyGreen.withOpacity(0)],
      );

  /// Stabile Zuordnung eines Verlaufs-Ausschnitts pro Tab-/Workspace-Key —
  /// ersetzt die alte "eine feste Farbe pro Tab"-Logik durch einen
  /// Ausschnitt aus dem Energy-Gradient, bleibt aber pro Key stabil.
  static Color accentFor(String key) {
    const stops = [energyYellow, energyGold, energyLime, energyGreen];
    return stops[key.hashCode.abs() % stops.length];
  }

  // --- Kompatibilitäts-Aliase (alte Namen, jetzt auf das Energy-System gemappt) ---
  static const Color accent = energyGreen;
  static const Color accentDim = energyGold;
  static const Color success = energyGreen;
  static const Color warning = energyYellow;
  static const Color textSecondary = textMuted;
  static Color tabAccentFor(String key) => accentFor(key);
}

/// Zentrale Typografie: Chakra Petch für UI/Navigation, JetBrains Mono für
/// technische Inhalte (URLs, Logs, Scraper-/Netzwerkdaten, Code).
class NexusFonts {
  NexusFonts._();

  static TextStyle ui({double size = 13, FontWeight weight = FontWeight.w500, Color? color}) =>
      GoogleFonts.chakraPetch(fontSize: size, fontWeight: weight, color: color ?? NexusColors.textPrimary);

  static TextStyle uiMuted({double size = 12, FontWeight weight = FontWeight.w500}) =>
      GoogleFonts.chakraPetch(fontSize: size, fontWeight: weight, color: NexusColors.textMuted);

  static TextStyle heading({double size = 20, FontWeight weight = FontWeight.w700}) =>
      GoogleFonts.chakraPetch(fontSize: size, fontWeight: weight, color: NexusColors.textPrimary, letterSpacing: 1.2);

  static TextStyle mono({double size = 12, FontWeight weight = FontWeight.w400, Color? color}) =>
      GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: weight, color: color ?? NexusColors.textMuted);

  static TextStyle monoAccent({double size = 12}) =>
      GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: FontWeight.w600, color: NexusColors.energyGreen);
}

class NexusTheme {
  NexusTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final chakraTextTheme = GoogleFonts.chakraPetchTextTheme(base.textTheme).apply(
      bodyColor: NexusColors.textPrimary,
      displayColor: NexusColors.textPrimary,
    );

    return base.copyWith(
      scaffoldBackgroundColor: NexusColors.bgBase,
      colorScheme: base.colorScheme.copyWith(
        primary: NexusColors.energyGreen,
        secondary: NexusColors.energyGold,
        surface: NexusColors.bgSurface,
        error: NexusColors.chromeDanger,
        onPrimary: Colors.black,
        onSurface: NexusColors.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: NexusColors.bgSurface,
        foregroundColor: NexusColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: NexusFonts.heading(size: 17),
      ),
      cardColor: NexusColors.bgSurface,
      dividerColor: NexusColors.borderHairline,
      textTheme: chakraTextTheme,
      iconTheme: const IconThemeData(color: NexusColors.textMuted),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: NexusColors.energyGreen,
          foregroundColor: Colors.black,
          textStyle: NexusFonts.ui(weight: FontWeight.w700),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: NexusColors.raised,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
        hintStyle: NexusFonts.uiMuted(),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: NexusColors.energyGreen,
        linearTrackColor: NexusColors.borderHairline,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: NexusColors.raised,
        contentTextStyle: NexusFonts.ui(size: 12),
        behavior: SnackBarBehavior.floating,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: NexusColors.raised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      ),
      splashFactory: InkRipple.splashFactory,
    );
  }
}

/// Wiederverwendbarer "Energy Border" — ein dünner, verlaufender Rahmen,
/// der aktive/fokussierte Panels/Tabs/Buttons markiert, statt einer
/// einzelnen flachen Akzentfarbe.
class EnergyBorder extends StatelessWidget {
  final Widget child;
  final double width;
  final BorderRadius radius;
  final bool active;

  const EnergyBorder({
    super.key,
    required this.child,
    this.width = 1.4,
    this.radius = const BorderRadius.all(Radius.circular(10)),
    this.active = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: NexusColors.energyGradientCompact,
      ),
      padding: EdgeInsets.all(width),
      child: Container(
        decoration: BoxDecoration(color: NexusColors.bgSurface, borderRadius: BorderRadius.circular(radius.topLeft.x - width)),
        child: child,
      ),
    );
  }
}
