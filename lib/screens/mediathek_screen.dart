import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nexus/models/download_entry.dart';
import 'package:nexus/services/browser_controller.dart';
import 'package:nexus/theme/nexus_theme.dart';

/// Vollbild-Ansicht aller Downloads — die "Mediathek". Die kompakte
/// Variante lebt im Sidebar-Panel (DownloadsPanel); diese Seite ist die
/// aufgeklappte Vollbild-Version mit mehr Platz für Details.
class MediathekScreen extends StatelessWidget {
  const MediathekScreen({super.key});

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '?';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BrowserController>();
    return Scaffold(
      backgroundColor: NexusColors.background,
      appBar: AppBar(title: const Text('NEXUS Mediathek')),
      body: AnimatedBuilder(
        animation: controller.downloader,
        builder: (context, _) {
          final items = controller.downloader.downloads;
          if (items.isEmpty) {
            return const Center(
              child: Text('Noch keine Downloads.\nÖffne den Video-Harvester in der Sidebar, um Medien zu finden.',
                  textAlign: TextAlign.center, style: TextStyle(color: NexusColors.textSecondary)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final entry = items[index];
              return Card(
                color: NexusColors.surface,
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: NexusColors.accent,
                    child: Icon(
                      entry.isDone ? Icons.check : (entry.isFailed ? Icons.error_outline : Icons.downloading),
                      color: Colors.black,
                    ),
                  ),
                  title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${_formatBytes(entry.receivedBytes)} / ${_formatBytes(entry.totalBytes)} · ${entry.type.toUpperCase()}'
                    '${entry.isFailed ? " · Fehler: ${entry.error}" : ""}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: entry.isActive
                      ? IconButton(icon: const Icon(Icons.close), onPressed: () => controller.downloader.cancel(entry.id))
                      : IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => controller.downloader.remove(entry.id)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
