import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nexus/services/browser_controller.dart';
import 'package:nexus/theme/nexus_theme.dart';

/// Schmale, immer sichtbare Icon-Leiste am linken Rand — das
/// namensgebende Vivaldi-Element. Tippen auf ein Icon klappt das
/// zugehörige Panel auf/zu.
class NexusSidebarRail extends StatelessWidget {
  const NexusSidebarRail({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BrowserController>();

    return Container(
      width: 52,
      color: NexusColors.surface,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Image.asset('assets/nexus_logo.png', width: 28, height: 28, errorBuilder: (_, __, ___) {
            return const Icon(Icons.hexagon, color: NexusColors.accent, size: 26);
          }),
          const SizedBox(height: 12),
          _RailIcon(
            icon: Icons.tab_outlined,
            active: controller.activePanel == SidebarPanel.tabs,
            badge: controller.tabs.length,
            tooltip: 'Tabs',
            onTap: () => controller.showPanel(SidebarPanel.tabs),
          ),
          _RailIcon(
            icon: Icons.grid_view_rounded,
            active: controller.activePanel == SidebarPanel.speedDial,
            tooltip: 'Startseite',
            onTap: () => controller.showPanel(SidebarPanel.speedDial),
          ),
          _RailIcon(
            icon: Icons.travel_explore,
            active: controller.activePanel == SidebarPanel.harvester,
            badge: controller.activeTab?.harvestedMedia.length ?? 0,
            badgeColor: NexusColors.accent,
            tooltip: 'Video-Harvester',
            onTap: () => controller.showPanel(SidebarPanel.harvester),
          ),
          _RailIcon(
            icon: Icons.download_rounded,
            active: controller.activePanel == SidebarPanel.downloads,
            badge: controller.downloader.downloads.where((d) => d.isActive).length,
            tooltip: 'Downloads / Mediathek',
            onTap: () => controller.showPanel(SidebarPanel.downloads),
          ),
          const Spacer(),
          _RailIcon(
            icon: controller.adblock.enabled ? Icons.shield_rounded : Icons.shield_outlined,
            active: false,
            iconColor: controller.adblock.enabled ? NexusColors.success : NexusColors.textDisabled,
            tooltip: controller.adblock.enabled ? 'Adblocker: An' : 'Adblocker: Aus',
            onTap: () {
              controller.adblock.toggle();
              controller.notifyListeners();
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _RailIcon extends StatelessWidget {
  final IconData icon;
  final bool active;
  final int badge;
  final Color? badgeColor;
  final Color? iconColor;
  final String tooltip;
  final VoidCallback onTap;

  const _RailIcon({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onTap,
    this.badge = 0,
    this.badgeColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: active ? NexusColors.accent.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: active ? Border.all(color: NexusColors.accent.withOpacity(0.4)) : null,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, size: 20, color: iconColor ?? (active ? NexusColors.accent : NexusColors.textSecondary)),
              if (badge > 0)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: badgeColor ?? NexusColors.danger,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: const TextStyle(fontSize: 9, color: Colors.black, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
