import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nexus/models/browser_tab.dart';
import 'package:nexus/services/browser_controller.dart';
import 'package:nexus/theme/nexus_theme.dart';

class NexusTabStrip extends StatelessWidget {
  const NexusTabStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BrowserController>();
    return Container(
      height: 38,
      color: NexusColors.surface,
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: controller.tabs.length,
              itemBuilder: (context, index) {
                final tab = controller.tabs[index];
                final active = tab.id == controller.activeTabId;
                return _TabChip(
                  tab: tab,
                  active: active,
                  onTap: () => controller.switchTab(tab.id),
                  onClose: () => controller.closeTab(tab.id),
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 18, color: NexusColors.accent),
            tooltip: 'Neuer Tab',
            onPressed: () => controller.newTab(),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final BrowserTab tab;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _TabChip({required this.tab, required this.active, required this.onTap, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final accent = NexusColors.tabAccentFor(tab.id);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        constraints: const BoxConstraints(minWidth: 90, maxWidth: 170),
        margin: const EdgeInsets.only(right: 2, top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active ? NexusColors.background : Colors.transparent,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (active)
              const Positioned(
                top: -4,
                left: 0,
                right: 0,
                child: SizedBox(
                  height: 2,
                  child: DecoratedBox(decoration: BoxDecoration(gradient: NexusColors.energyGradientCompact)),
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (tab.isLoading)
                  const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(strokeWidth: 1.6, color: NexusColors.accent),
                  )
                else
                  Icon(Icons.circle, size: 8, color: accent),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    tab.title.isEmpty ? tab.url : tab.title,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12,
                      color: active ? NexusColors.textPrimary : NexusColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onClose,
                  child: const Icon(Icons.close, size: 13, color: NexusColors.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
