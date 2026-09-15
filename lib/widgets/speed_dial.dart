import 'package:flutter/material.dart';
import 'package:nexus/theme/nexus_theme.dart';

class SpeedDialEntry {
  final String label;
  final String url;
  final IconData icon;
  const SpeedDialEntry(this.label, this.url, this.icon);
}

const List<SpeedDialEntry> defaultSpeedDial = [
  SpeedDialEntry('DuckDuckGo', 'https://duckduckgo.com', Icons.search),
  SpeedDialEntry('YouTube', 'https://youtube.com', Icons.smart_display_outlined),
  SpeedDialEntry('ARD Mediathek', 'https://www.ardmediathek.de', Icons.live_tv_outlined),
  SpeedDialEntry('ZDF Mediathek', 'https://www.zdf.de', Icons.tv_outlined),
  SpeedDialEntry('Wikipedia', 'https://wikipedia.org', Icons.menu_book_outlined),
  SpeedDialEntry('GitHub', 'https://github.com', Icons.code_rounded),
];

/// Startseite eines neuen Tabs — Kacheln im Vivaldi-Speed-Dial-Stil.
class SpeedDial extends StatelessWidget {
  final void Function(String url) onOpen;

  const SpeedDial({super.key, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: NexusColors.background,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.hexagon_outlined, size: 40, color: NexusColors.accent),
                const SizedBox(height: 8),
                const Text('NEXUS', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 2, color: NexusColors.textPrimary)),
                const SizedBox(height: 24),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: defaultSpeedDial.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.05,
                  ),
                  itemBuilder: (context, index) {
                    final entry = defaultSpeedDial[index];
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => onOpen(entry.url),
                      child: Container(
                        decoration: BoxDecoration(
                          color: NexusColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: NexusColors.divider),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(entry.icon, color: NexusColors.accent, size: 26),
                            const SizedBox(height: 8),
                            Text(
                              entry.label,
                              style: const TextStyle(fontSize: 11, color: NexusColors.textSecondary),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
