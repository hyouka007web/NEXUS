import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nexus/services/browser_controller.dart';
import 'package:nexus/theme/nexus_theme.dart';
import 'package:nexus/widgets/nexus_panels.dart';
import 'package:nexus/widgets/nexus_sidebar.dart';
import 'package:nexus/widgets/nexus_url_bar.dart';
import 'package:nexus/widgets/nexus_web_view.dart';
import 'package:nexus/widgets/start_page.dart';
import 'package:nexus/widgets/tab_strip.dart';

class BrowserScreen extends StatelessWidget {
  const BrowserScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BrowserController>();

    return Scaffold(
      backgroundColor: NexusColors.background,
      body: SafeArea(
        child: Row(
          children: [
            const NexusSidebarRail(),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: controller.sidebarExpanded ? 260 : 0,
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(),
              child: controller.sidebarExpanded ? _buildPanel(controller) : null,
            ),
            Expanded(
              child: Column(
                children: [
                  const NexusTabStrip(),
                  const NexusUrlBar(),
                  Expanded(
                    child: Stack(
                      children: controller.tabs.map((tab) {
                        final active = tab.id == controller.activeTabId;
                        return Visibility(
                          visible: active,
                          maintainState: true,
                          child: tab.isHome
                              ? StartPage(
                                  workspace: controller.activeWorkspace,
                                  onOpenUrl: (url) {
                                    tab.update(isHome: false, url: url, title: url);
                                  },
                                  onLayoutChanged: (widgets) =>
                                      controller.updateStartPageWidgets(controller.activeWorkspace.id, widgets),
                                )
                              : NexusWebView(
                                  key: ValueKey(tab.id),
                                  tab: tab,
                                  adblock: controller.adblock,
                                  onOpenNewTab: (url) => controller.newTab(url: url),
                                ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel(BrowserController controller) {
    switch (controller.activePanel) {
      case SidebarPanel.tabs:
        return const TabsPanel();
      case SidebarPanel.harvester:
        return const HarvesterPanel();
      case SidebarPanel.downloads:
        return const DownloadsPanel();
      case SidebarPanel.speedDial:
      case SidebarPanel.none:
        return const TabsPanel();
    }
  }
}

