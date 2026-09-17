import 'package:flutter/foundation.dart';
import 'package:nexus/models/browser_tab.dart';
import 'package:nexus/models/start_page_widget.dart';
import 'package:nexus/models/workspace.dart';
import 'package:nexus/services/adblock_engine.dart';
import 'package:nexus/services/start_page_store.dart';
import 'package:nexus/services/video_downloader.dart';

enum SidebarPanel { none, tabs, speedDial, harvester, downloads }

/// BrowserController: zentraler App-State.
/// Tabs sind jetzt pro Workspace isoliert (Master-Prompt Kapitel 12).
/// `tabs` / `activeTabId` delegieren an den aktuell aktiven Workspace,
/// damit bestehende Widgets (Tab-Strip, Sidebar, Panels) unverändert
/// weiterfunktionieren — sie merken vom Workspace-Wechsel nur, dass sich
/// die Tab-Liste austauscht.
class BrowserController extends ChangeNotifier {
  final AdBlockEngine adblock = AdBlockEngine();
  final VideoDownloader downloader = VideoDownloader();

  final List<Workspace> workspaces = DefaultWorkspaces.build();
  late String activeWorkspaceId;

  bool sidebarExpanded = true;
  SidebarPanel activePanel = SidebarPanel.tabs;

  int _tabCounter = 0;

  BrowserController() {
    activeWorkspaceId = workspaces.first.id;
    newTab();
    for (final ws in workspaces) {
      _loadStartPage(ws.id);
    }
  }

  Future<void> _loadStartPage(String workspaceId) async {
    final widgets = await StartPageStore.load(workspaceId);
    final ws = workspaces.firstWhere((w) => w.id == workspaceId, orElse: () => workspaces.first);
    ws.startPageWidgets = widgets;
    ws.startPageLoaded = true;
    notifyListeners();
  }

  void updateStartPageWidgets(String workspaceId, List<StartPageWidgetConfig> widgets) {
    final ws = workspaces.firstWhere((w) => w.id == workspaceId, orElse: () => workspaces.first);
    ws.startPageWidgets = widgets;
    notifyListeners();
    StartPageStore.save(workspaceId, widgets);
  }

  Workspace get activeWorkspace => workspaces.firstWhere(
        (w) => w.id == activeWorkspaceId,
        orElse: () => workspaces.first,
      );

  // --- Delegierte Tab-API (an den aktiven Workspace) ---
  List<BrowserTab> get tabs => activeWorkspace.tabs;
  String? get activeTabId => activeWorkspace.activeTabId;
  BrowserTab? get activeTab => activeWorkspace.activeTab;

  void switchWorkspace(String id) {
    if (workspaces.any((w) => w.id == id)) {
      activeWorkspaceId = id;
      if (activeWorkspace.tabs.isEmpty) {
        newTab();
      } else {
        notifyListeners();
      }
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
    activeWorkspace.tabs.add(tab);
    activeWorkspace.activeTabId = tab.id;
    notifyListeners();
    return tab;
  }

  void closeTab(String id) {
    final ws = activeWorkspace;
    final idx = ws.tabs.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    ws.tabs.removeAt(idx);
    if (ws.tabs.isEmpty) {
      newTab();
      return;
    }
    if (ws.activeTabId == id) {
      final newIdx = idx.clamp(0, ws.tabs.length - 1);
      ws.activeTabId = ws.tabs[newIdx].id;
    }
    notifyListeners();
  }

  void switchTab(String id) {
    if (activeWorkspace.tabs.any((t) => t.id == id)) {
      activeWorkspace.activeTabId = id;
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

  int get totalHarvestedCount => tabs.fold(0, (sum, t) => sum + t.harvestedMedia.length);
}
