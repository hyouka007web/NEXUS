import 'package:flutter/material.dart';
import 'package:nexus/models/browser_tab.dart';
import 'package:nexus/models/start_page_widget.dart';

/// Ein Workspace kapselt einen eigenen Satz Tabs (Kapitel 12 im Master-
/// Prompt). Jeder Workspace hat seine eigene Tab-Liste + aktiven Tab;
/// Cookies/Sessions werden (noch) nicht isoliert — das ist als spätere
/// Ausbaustufe vorgesehen (siehe Kapitel 12, "wenn technisch sinnvoll").
class Workspace {
  final String id;
  String name;
  final IconData icon;

  final List<BrowserTab> tabs = [];
  String? activeTabId;

  /// Start-Page-Layout dieses Workspace (Kapitel 11 + 12: jeder Workspace
  /// hat seine eigene Startseite). Wird lazy aus dem StartPageStore
  /// geladen (siehe BrowserController) und startet mit den Standard-Kacheln.
  List<StartPageWidgetConfig> startPageWidgets = defaultStartPageWidgets();
  bool startPageLoaded = false;

  Workspace({required this.id, required this.name, required this.icon});

  BrowserTab? get activeTab {
    if (activeTabId == null) return null;
    try {
      return tabs.firstWhere((t) => t.id == activeTabId);
    } catch (_) {
      return null;
    }
  }
}

/// Die fünf Standard-Workspaces aus dem Master-Prompt (Kapitel 12).
class DefaultWorkspaces {
  DefaultWorkspaces._();

  static List<Workspace> build() => [
        Workspace(id: 'void', name: 'VOID', icon: Icons.hexagon_outlined),
        Workspace(id: 'dev', name: 'DEV', icon: Icons.code_rounded),
        Workspace(id: 'research', name: 'RESEARCH', icon: Icons.travel_explore),
        Workspace(id: 'media', name: 'MEDIA', icon: Icons.live_tv_rounded),
        Workspace(id: 'custom', name: 'CUSTOM', icon: Icons.tune_rounded),
      ];
}
