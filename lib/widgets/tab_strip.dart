import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
                final accent = NexusColors.tabAccentFor(tab.id);
                return GestureDetector(
                  onTap: () => controller.switchTab(tab.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    constraints: const BoxConstraints(minWidth: 90, maxWidth: 170),
                    margin: const EdgeInsets.only(right: 2, top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: active ? NexusColors.background : Colors.transparent,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                      border: Border(top: BorderSide(color: active ? accent : Colors.transparent, width: 2)),
                    ),
                    child: Row(
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
                          onTap: () => controller.closeTab(tab.id),
                          child: const Icon(Icons.close, size: 13, color: NexusColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
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
