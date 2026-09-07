import 'package:flutter/material.dart';

import '../engines/video_downloader.dart';
import '../models/video_entry.dart';
import '../state/download_repository.dart';
import '../theme/nexus_theme.dart';
import 'downloads_panel.dart';

class MediathekScreen extends StatefulWidget {
  const MediathekScreen({super.key});

  @override
  State<MediathekScreen> createState() => _MediathekScreenState();
}

class _MediathekScreenState extends State<MediathekScreen> {
  List<VideoEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final entries = await VideoDownloader.loadIndex();
    setState(() {
      _entries = entries;
      _loading = false;
    });
    // Nur fertige Downloads aus dem Live-Register räumen — die stehen jetzt
    // im Index. Fehlgeschlagene bleiben sichtbar, siehe DownloadRepository.
    DownloadRepository.instance.clearDone();
  }

  Future<void> _delete(VideoEntry entry) async {
    await VideoDownloader.delete(entry);
    _load();
  }

  String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexusColors.bgBase,
      appBar: AppBar(
        title: const Text('Mediathek'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const DownloadsSection(),
            const Divider(height: 24),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_entries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    'Noch keine heruntergeladenen Videos.',
                    style: TextStyle(color: NexusColors.textMuted),
                  ),
                ),
              )
            else
              ..._entries.map(
                (entry) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.movie_outlined,
                        color: NexusColors.accentPrimary),
                    title: Text(entry.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${entry.downloadedAt} · ${_formatSize(entry.sizeBytes)}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: NexusColors.accentDanger),
                      onPressed: () => _delete(entry),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
