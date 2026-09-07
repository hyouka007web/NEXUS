import 'package:flutter/material.dart';

import '../models/download_task.dart';
import '../state/download_repository.dart';
import '../theme/nexus_theme.dart';

/// Aktive + fehlgeschlagene Downloads, live über [DownloadRepository].
/// Eigenständiges Widget, damit es sowohl in der Mediathek als auch als
/// eigenständiges Panel vom Drei-Punkte-Menü aus gezeigt werden kann, ohne
/// den Browser-Screen selbst zu verlassen oder zu blockieren.
class DownloadsSection extends StatelessWidget {
  const DownloadsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
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
              child: Text('Keine laufenden oder fehlgeschlagenen Downloads.',
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
    );
  }
}
