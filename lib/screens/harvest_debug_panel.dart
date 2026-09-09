import 'package:flutter/material.dart';

import '../engines/harvest_logger.dart';
import '../theme/nexus_theme.dart';

/// Live-Debug-Panel für den Harvester — zeigt aktuelle URL, Zustand und
/// jeden protokollierten Schritt in Echtzeit. Als Pane integrierbar
/// (`PaneKind.harvesterDebug`), genau wie Terminal/DevTools.
class HarvestDebugPanel extends StatelessWidget {
  const HarvestDebugPanel({super.key});

  Color _colorFor(HarvestLogLevel level) => switch (level) {
        HarvestLogLevel.error => NexusColors.accentDanger,
        HarvestLogLevel.warning => NexusColors.accentPrimary,
        HarvestLogLevel.info => NexusColors.textPrimary,
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: HarvestLogger.instance,
      builder: (context, _) {
        final logger = HarvestLogger.instance;
        return Container(
          color: NexusColors.bgBase,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                color: NexusColors.bgSurfaceRaised,
                child: Row(
                  children: [
                    Icon(
                      logger.running ? Icons.sync : Icons.check_circle_outline,
                      size: 16,
                      color: logger.running
                          ? NexusColors.accentPrimary
                          : NexusColors.accentSuccess,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(logger.currentUrl ?? 'Kein Lauf gestartet',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: NexusColors.textMuted)),
                          Text(logger.currentStage,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: NexusColors.textPrimary)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: logger.clear,
                      tooltip: 'Log leeren',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  reverse: true,
                  itemCount: logger.entries.length,
                  itemBuilder: (context, i) {
                    final entry = logger.entries[logger.entries.length - 1 - i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                          children: [
                            TextSpan(
                              text: '[${entry.stage}] ',
                              style: const TextStyle(color: NexusColors.accentPrimary),
                            ),
                            TextSpan(
                              text: entry.message,
                              style: TextStyle(color: _colorFor(entry.level)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (logger.lastDomSnapshot.isNotEmpty)
                _DomSnapshotSection(snapshot: logger.lastDomSnapshot),
            ],
          ),
        );
      },
    );
  }
}

class _DomSnapshotSection extends StatelessWidget {
  final List<Map<String, dynamic>> snapshot;
  const _DomSnapshotSection({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: NexusColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text('DOM-Snapshot (${snapshot.length} relevante Tags)',
                style: const TextStyle(fontSize: 11, color: NexusColors.textMuted)),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: snapshot.length,
              itemBuilder: (context, i) {
                final item = snapshot[i];
                final tag = item['tag'] as String? ?? '?';
                final preview = tag == 'script'
                    ? (item['preview'] as String? ?? '')
                    : (item['attrs']?.toString() ?? item['currentSrc']?.toString() ?? '');
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: SelectableText(
                    '<$tag> $preview',
                    maxLines: 2,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
