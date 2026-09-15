import 'package:flutter/foundation.dart';
import 'package:nexus/models/browser_tab.dart';
import 'package:nexus/services/adblock_engine.dart';
import 'package:nexus/services/video_downloader.dart';

enum SidebarPanel { none, tabs, speedDial, harvester, downloads }

/// BrowserController: zentraler App-State (Tabs, aktiver Tab, Sidebar,
/// geteilte Services). Wird per Provider oben im Widget-Baum bereitgestellt.
class BrowserController extends ChangeNotifier {
  final AdBlockEngine adblock = AdBlockEngine();
  final VideoDownloader downloader = VideoDownloader();

  final List<BrowserTab> tabs = [];
  String? activeTabId;

  bool sidebarExpanded = true;
  SidebarPanel activePanel = SidebarPanel.tabs;

  int _tabCounter = 0;

  BrowserController() {
    newTab();
  }

  BrowserTab? get activeTab {
    if (activeTabId == null) return null;
    try {
      return tabs.firstWhere((t) => t.id == activeTabId);
    } catch (_) {
      return null;
    }
  }

  BrowserTab newTab({String? url}) {
    _tabCounter++;
    final tab = BrowserTab(
      id: 'tab_$_tabCounter',
      url: url ?? 'nexus://home',
      isHome: url == null,
      title: url == null ? 'Neuer Tab' : url,
    );
    tabs.add(tab);
    activeTabId = tab.id;
    notifyListeners();
    return tab;
  }

  void closeTab(String id) {
    final idx = tabs.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    tabs.removeAt(idx);
    if (tabs.isEmpty) {
      newTab();
      return;
    }
    if (activeTabId == id) {
      final newIdx = idx.clamp(0, tabs.length - 1);
      activeTabId = tabs[newIdx].id;
    }
    notifyListeners();
  }

  void switchTab(String id) {
    if (tabs.any((t) => t.id == id)) {
      activeTabId = id;
      notifyListeners();
    }
  }

  void toggleSidebar() {
    sidebarExpanded = !sidebarExpanded;
    notifyListeners();
  }

  void showPanel(SidebarPanel panel) {
    if (activePanel == panel && sidebarExpanded) {
      sidebarExpanded = false;
    } else {
      activePanel = panel;
      sidebarExpanded = true;
    }
    notifyListeners();
  }

  /// Alle Downloads aus allen Tabs in einer Liste — für die Mediathek.
  int get totalHarvestedCount => tabs.fold(0, (sum, t) => sum + t.harvestedMedia.length);
}
