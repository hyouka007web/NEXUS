import 'package:flutter/material.dart';

import '../models/download_task.dart';
import '../state/batch_download_manager.dart';
import '../state/download_repository.dart';
import '../theme/nexus_theme.dart';

/// Batch-Downloads (mehrere auf einmal aus dem Harvester-Ergebnisblatt
/// ausgewählte Videos) — eigener Abschnitt mit Pause/Fortsetzen pro
/// Video, damit man bei 50 gefundenen Videos nicht 50x einzeln auf
/// "Download" tippen muss.
class BatchDownloadsSection extends StatelessWidget {
  const BatchDownloadsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: BatchDownloadManager.instance,
      builder: (context, _) {
        final items = BatchDownloadManager.instance.items;
        if (items.isEmpty) return const SizedBox.shrink();
        final manager = BatchDownloadManager.instance;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  'Batch-Download (${manager.doneCount}/${items.length} fertig)',
                  style: const TextStyle(color: NexusColors.textMuted),
                ),
                const Spacer(),
                if (manager.doneCount > 0)
                  TextButton(
                    onPressed: manager.clearFinished,
                    child: const Text('Fertige entfernen', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            ...items.map((item) => Card(
                  child: ListTile(
                    dense: true,
                    title: Text(
                      item.video.title.isEmpty ? item.video.host : item.video.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: item.state == BatchItemState.failed
                        ? Text(item.errorMessage ?? 'Fehler',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: NexusColors.accentDanger))
                        : LinearProgressIndicator(
                            value: item.percent > 0 ? item.percent / 100 : null,
                          ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (item.state == BatchItemState.downloading)
                          IconButton(
                            icon: const Icon(Icons.pause, size: 20),
                            onPressed: () => manager.pause(item),
                          )
                        else if (item.state == BatchItemState.paused ||
                            item.state == BatchItemState.failed)
                          IconButton(
                            icon: const Icon(Icons.play_arrow, size: 20,
                                color: NexusColors.accentPrimary),
                            onPressed: () => manager.resume(item),
                          )
                        else if (item.state == BatchItemState.done)
                          const Icon(Icons.check_circle,
                              color: NexusColors.accentSuccess, size: 20),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => manager.remove(item),
                        ),
                      ],
                    ),
                  ),
                )),
            const Divider(height: 20),
          ],
        );
      },
    );
  }
}

/// Aktive + fehlgeschlagene Downloads, live über [DownloadRepository].
/// Eigenständiges Widget, damit es sowohl in der Mediathek als auch als
/// eigenständiges Panel vom Drei-Punkte-Menü aus gezeigt werden kann, ohne
/// den Browser-Screen selbst zu verlassen oder zu blockieren.
class DownloadsSection extends StatelessWidget {
  const DownloadsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const BatchDownloadsSection(),
        ListenableBuilder(
      listenable: DownloadRepository.instance,
      builder: (context, _) {
        final all = DownloadRepository.instance.activeAndRecent();
        final active =
            all.where((t) => t.state == DownloadState.downloading).toList();
        final failed =
            all.where((t) => t.state == DownloadState.failed).toList();

        if (active.isEmpty && failed.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('Keine laufenden oder fehlgeschlagenen Einzel-Downloads.',
                  style: TextStyle(color: NexusColors.textMuted)),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (active.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Läuft gerade',
                    style: TextStyle(color: NexusColors.textMuted)),
              ),
              ...active.map((t) => Card(
                    child: ListTile(
                      dense: true,
                      title: Text(t.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: LinearProgressIndicator(
                        value: t.percent > 0 ? t.percent / 100 : null,
                      ),
                      trailing: Text('${t.percent}%'),
                    ),
                  )),
            ],
            if (failed.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Fehlgeschlagen',
                    style: TextStyle(color: NexusColors.accentDanger)),
              ),
              ...failed.map((t) => Card(
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.error_outline,
                          color: NexusColors.accentDanger),
                      title: Text(t.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        t.errorMessage ?? 'Unbekannter Fehler',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () =>
                            DownloadRepository.instance.dismiss(t),
                      ),
                    ),
                  )),
            ],
          ],
        );
      },
        ),
      ],
    );
  }
}
