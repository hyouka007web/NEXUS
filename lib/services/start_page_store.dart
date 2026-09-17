import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexus/models/start_page_widget.dart';

/// Speichert/lädt das Start-Page-Layout je Workspace lokal auf dem Gerät
/// (Master-Prompt Kapitel 11: "Layout Speicherung"). Ein Workspace ohne
/// gespeichertes Layout bekommt die Standard-Kacheln.
class StartPageStore {
  static String _keyFor(String workspaceId) => 'nexus_startpage_$workspaceId';

  static Future<List<StartPageWidgetConfig>> load(String workspaceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyFor(workspaceId));
      if (raw == null || raw.isEmpty) return defaultStartPageWidgets();
      final decoded = jsonDecode(raw) as List;
      final widgets = decoded
          .map((e) => StartPageWidgetConfig.fromJson(e as Map<String, dynamic>))
          .toList();
      return widgets.isEmpty ? defaultStartPageWidgets() : widgets;
    } catch (_) {
      return defaultStartPageWidgets();
    }
  }

  static Future<void> save(String workspaceId, List<StartPageWidgetConfig> widgets) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(widgets.map((w) => w.toJson()).toList());
      await prefs.setString(_keyFor(workspaceId), raw);
    } catch (_) {
      // Persistenz ist "best effort" — ein fehlgeschlagener Save darf die
      // App nicht zum Absturz bringen, das Layout bleibt dann nur für die
      // laufende Session erhalten.
    }
  }
}
