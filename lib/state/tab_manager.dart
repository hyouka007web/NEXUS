import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../adblock/redirect_shield.dart';
import '../models/block_event.dart';
import '../models/tab_model.dart';
import 'dev_settings.dart';

/// Verwaltet alle offenen Tabs, ihre WebViewController und den
/// Redirect-Shield-Zähler — Pendant zu Kotlins `TabManager`. Anders als
/// dort (ein einzelnes, wiederverwendetes `GeckoView` wird zwischen Tabs
/// umgehängt) bekommt hier jeder Tab seinen eigenen, dauerhaften
/// `WebViewController` — `webview_flutter`s `WebViewWidget` ist dafür
/// ausgelegt, mehrere gleichzeitig zu halten, ein Umhängen wie bei
/// GeckoView ist hier weder nötig noch vorgesehen.
///
/// Tabs überleben jetzt einen Neustart (vorher fehlte das komplett): jede
/// strukturelle Änderung (neuer Tab, geschlossener Tab, Navigation) schreibt
/// die aktuelle URL-Liste in eine kleine JSON-Datei; [restore] liest sie
/// beim Start wieder ein — entspricht Kotlins `TabPersistence`.
class TabManager extends ChangeNotifier {
  final List<NexusTab> tabs = [];
  int activeIndex = 0;
  int blockedCount = 0;
  BlockEvent? lastBlockEvent;

  NexusTab? get activeTab => tabs.isEmpty ? null : tabs[activeIndex];

  static const String _persistFile = 'tabs.json';

  /// Muss einmalig aufgerufen werden, bevor die UI die Tabs anzeigt (siehe
  /// `BrowserScreen.initState`). Lädt gespeicherte Tabs, oder legt — falls
  /// keine da sind oder das Lesen fehlschlägt — einen einzelnen Start-Tab an.
  Future<void> restore() async {
    try {
      final file = await _persistFilePath();
      if (await file.exists()) {
        final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
        final urls = raw.whereType<String>().toList();
        if (urls.isNotEmpty) {
          for (final url in urls) {
            addTab(url: url, navigate: url != kHomeSentinel, persist: false);
          }
          return;
        }
      }
    } catch (_) {
      // Kaputte/fehlende Datei — einfach mit einem frischen Tab starten,
      // statt die App-Öffnung daran scheitern zu lassen.
    }
    addTab(persist: false);
  }

  NexusTab addTab({
    String url = kHomeSentinel,
    bool navigate = true,
    bool persist = true,
  }) {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
    final uaOverride = DevSettings.instance.userAgentOverride;
    if (uaOverride != null && uaOverride.isNotEmpty) {
      controller.setUserAgent(uaOverride);
    }
    final tab = NexusTab(controller: controller, url: url);

    controller.setNavigationDelegate(
      RedirectShield.build(
        tab: tab,
        onBlocked: (event) {
          blockedCount++;
          lastBlockEvent = event;
          notifyListeners();
        },
        onLoadingChange: (_) => notifyListeners(),
        onLocationChange: (newUrl) {
          tab.url = newUrl;
          notifyListeners();
          _persist();
        },
      ),
    );

    tabs.add(tab);
    activeIndex = tabs.length - 1;
    if (navigate && url != kHomeSentinel) {
      _load(tab, url, persist: false);
    }
    notifyListeners();
    if (persist) _persist();
    return tab;
  }

  void closeTab(String tabId) {
    final index = tabs.indexWhere((t) => t.id == tabId);
    if (index == -1) return;
    tabs.removeAt(index);
    if (tabs.isEmpty) {
      addTab();
      return;
    }
    if (activeIndex >= tabs.length) activeIndex = tabs.length - 1;
    notifyListeners();
    _persist();
  }

  void switchTab(String tabId) {
    final index = tabs.indexWhere((t) => t.id == tabId);
    if (index == -1) return;
    activeIndex = index;
    notifyListeners();
  }

  /// Nimmt Freitext aus der Adressleiste entgegen — entweder eine URL oder
  /// eine Suchanfrage — und navigiert den aktiven Tab dorthin. Entspricht
  /// Kotlins `resolveInput()` + `navigate()`.
  void navigateInput(String raw) {
    final tab = activeTab;
    if (tab == null) return;
    final resolved = _resolveInput(raw.trim());
    _load(tab, resolved);
  }

  void reload() => activeTab?.controller.reload();

  Future<void> goBack() async {
    final tab = activeTab;
    if (tab == null) return;
    if (await tab.controller.canGoBack()) {
      tab.pendingAppNavigation = true;
      await tab.controller.goBack();
    }
  }

  Future<void> goForward() async {
    final tab = activeTab;
    if (tab == null) return;
    if (await tab.controller.canGoForward()) {
      tab.pendingAppNavigation = true;
      await tab.controller.goForward();
    }
  }

  void goHome() {
    final tab = activeTab;
    if (tab == null) return;
    tab.url = kHomeSentinel;
    tab.title = 'Neuer Tab';
    notifyListeners();
    _persist();
  }

  void _load(NexusTab tab, String url, {bool persist = true}) {
    tab.pendingAppNavigation = true;
    tab.url = url;
    tab.controller.loadRequest(Uri.parse(url));
    notifyListeners();
    if (persist) _persist();
  }

  Future<File> _persistFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_persistFile');
  }

  Future<void> _persist() async {
    try {
      final file = await _persistFilePath();
      final urls = tabs.map((t) => t.url).toList();
      await file.writeAsString(jsonEncode(urls));
    } catch (_) {
      // Tab-Speicherung ist ein Komfort-Feature — ein Schreibfehler hier
      // soll das Browsen selbst nicht stören.
    }
  }

  static String _resolveInput(String raw) {
    if (raw.isEmpty) return kHomeSentinel;
    final looksLikeUrl = raw.startsWith('http://') ||
        raw.startsWith('https://') ||
        (raw.contains('.') && !raw.contains(' '));
    if (looksLikeUrl) {
      return raw.startsWith('http://') || raw.startsWith('https://')
          ? raw
          : 'https://$raw';
    }
    // Standard-Suchmaschine: DuckDuckGo HTML-Endpunkt, wie im
    // Kotlin-Original als Default hinterlegt.
    final query = Uri.encodeQueryComponent(raw);
    return 'https://duckduckgo.com/html/?q=$query';
  }
}
