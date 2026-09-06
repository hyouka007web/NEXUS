import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../adblock/redirect_shield.dart';
import '../models/block_event.dart';
import '../models/tab_model.dart';

/// Verwaltet alle offenen Tabs, ihre WebViewController und den
/// Redirect-Shield-Zähler — Pendant zu Kotlins `TabManager`. Anders als
/// dort (ein einzelnes, wiederverwendetes `GeckoView` wird zwischen Tabs
/// umgehängt) bekommt hier jeder Tab seinen eigenen, dauerhaften
/// `WebViewController` — `webview_flutter`s `WebViewWidget` ist dafür
/// ausgelegt, mehrere gleichzeitig zu halten, ein Umhängen wie bei
/// GeckoView ist hier weder nötig noch vorgesehen.
class TabManager extends ChangeNotifier {
  final List<NexusTab> tabs = [];
  int activeIndex = 0;
  int blockedCount = 0;
  BlockEvent? lastBlockEvent;

  NexusTab? get activeTab => tabs.isEmpty ? null : tabs[activeIndex];

  TabManager() {
    addTab();
  }

  NexusTab addTab({String url = kHomeSentinel, bool navigate = true}) {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
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
        },
      ),
    );

    tabs.add(tab);
    activeIndex = tabs.length - 1;
    if (navigate && url != kHomeSentinel) {
      _load(tab, url);
    }
    notifyListeners();
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
  }

  void _load(NexusTab tab, String url) {
    tab.pendingAppNavigation = true;
    tab.url = url;
    tab.controller.loadRequest(Uri.parse(url));
    notifyListeners();
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
