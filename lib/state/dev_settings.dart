import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/quick_link.dart';

const Map<String, String> kUserAgentPresets = {
  'Standard (Android WebView)': '', // leer = kein Override, Systemstandard
  'Desktop Chrome':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
  'iPhone Safari':
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 '
          'Mobile/15E148 Safari/604.1',
};

/// Zentraler State für die Power-User-/Hacker-Werkzeuge: User-Agent-
/// Override, domainspezifische Skripte (selbst geschrieben vom Nutzer —
/// NEXUS liefert keine vorgefertigten Site-Payloads, siehe DevTools-Screen)
/// und die Quick-Links des Dashboard-Startbildschirms. Bewusst als eigener
/// `ChangeNotifier` statt in `TabManager`, damit Einstellungs-Änderungen
/// nicht jeden Tab-Rebuild mit auslösen.
class DevSettings extends ChangeNotifier {
  DevSettings._();
  static final DevSettings instance = DevSettings._();

  String? userAgentOverride;
  final Map<String, String> domainScripts = {};
  final List<QuickLink> quickLinks = [
    const QuickLink(label: 'DuckDuckGo', url: 'https://duckduckgo.com'),
  ];

  static const String _file = 'dev_settings.json';

  Future<void> restore() async {
    try {
      final file = await _path();
      if (!await file.exists()) return;
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      userAgentOverride = raw['userAgentOverride'] as String?;
      domainScripts
        ..clear()
        ..addAll((raw['domainScripts'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, v as String)));
      final links = (raw['quickLinks'] as List<dynamic>? ?? [])
          .map((e) => QuickLink.fromJson(e as Map<String, dynamic>))
          .toList();
      if (links.isNotEmpty) {
        quickLinks
          ..clear()
          ..addAll(links);
      }
      notifyListeners();
    } catch (_) {
      // Kaputte/fehlende Datei — einfach mit den Defaults weitermachen.
    }
  }

  void setUserAgent(String? value) {
    userAgentOverride = (value == null || value.isEmpty) ? null : value;
    notifyListeners();
    _persist();
  }

  void setDomainScript(String domain, String script) {
    if (script.trim().isEmpty) {
      domainScripts.remove(domain);
    } else {
      domainScripts[domain] = script;
    }
    notifyListeners();
    _persist();
  }

  void addQuickLink(QuickLink link) {
    quickLinks.add(link);
    notifyListeners();
    _persist();
  }

  void removeQuickLink(QuickLink link) {
    quickLinks.removeWhere((l) => l.url == link.url);
    notifyListeners();
    _persist();
  }

  Future<File> _path() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_file');
  }

  Future<void> _persist() async {
    try {
      final file = await _path();
      await file.writeAsString(jsonEncode({
        'userAgentOverride': userAgentOverride,
        'domainScripts': domainScripts,
        'quickLinks': quickLinks.map((l) => l.toJson()).toList(),
      }));
    } catch (_) {
      // Komfort-Feature — ein Schreibfehler soll das Browsen nicht stören.
    }
  }
}
