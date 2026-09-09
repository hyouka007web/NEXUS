import 'package:flutter/foundation.dart';

enum HarvestLogLevel { info, warning, error }

class HarvestLogEntry {
  final DateTime time;
  final String stage;
  final String message;
  final HarvestLogLevel level;
  final Map<String, Object?> data;

  HarvestLogEntry({
    required this.stage,
    required this.message,
    this.level = HarvestLogLevel.info,
    this.data = const {},
  }) : time = DateTime.now();
}

/// Live-Log für einen Harvest-Lauf. Jeder Schritt (Sniffer, DOM-Render,
/// Netzwerk-Crawl) trägt hier ein, damit das Debug-Panel den Ablauf in
/// Echtzeit zeigen kann — genau die Sichtbarkeit, die bisher fehlte
/// ("wir wissen nicht, wo genau er scheitert").
///
/// **Grenze:** der rekursive Netzwerk-Crawl (`VideoHarvesterEngine.harvest`)
/// läuft über `compute()` in einem eigenen Isolate (siehe browser_screen.dart,
/// Performance-Kommentar dort) — aus einem Isolate lässt sich nicht einfach
/// live in dieses Log schreiben, das würde eine eigene Isolate-Kommunikation
/// brauchen. Für den Crawl-Teil gibt es deshalb nur eine Zusammenfassung
/// NACH Abschluss, nicht Schritt-für-Schritt live wie beim Sniffer/DOM-Teil,
/// die beide auf dem Haupt-Isolate laufen (brauchen den WebViewController).
class HarvestLogger extends ChangeNotifier {
  HarvestLogger._();
  static final HarvestLogger instance = HarvestLogger._();

  final List<HarvestLogEntry> entries = [];
  String? currentUrl;
  String currentStage = 'idle';
  bool running = false;
  List<Map<String, dynamic>> lastDomSnapshot = [];

  static const int _maxEntries = 500;

  void start(String url) {
    currentUrl = url;
    currentStage = 'gestartet';
    running = true;
    notifyListeners();
  }

  void log(
    String stage,
    String message, {
    HarvestLogLevel level = HarvestLogLevel.info,
    Map<String, Object?> data = const {},
  }) {
    currentStage = stage;
    entries.add(HarvestLogEntry(stage: stage, message: message, level: level, data: data));
    if (entries.length > _maxEntries) entries.removeAt(0);
    notifyListeners();
  }

  void finish({required bool success}) {
    currentStage = success ? 'fertig' : 'fehlgeschlagen';
    running = false;
    notifyListeners();
  }

  void setDomSnapshot(List<Map<String, dynamic>> snapshot) {
    lastDomSnapshot = snapshot;
    notifyListeners();
  }

  void clear() {
    entries.clear();
    currentUrl = null;
    currentStage = 'idle';
    running = false;
    notifyListeners();
  }
}
