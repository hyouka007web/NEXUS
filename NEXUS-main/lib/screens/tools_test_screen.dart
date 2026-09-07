import 'package:flutter/material.dart';

import '../engines/scraper_engine.dart';
import '../engines/video_downloader.dart';
import '../engines/video_harvester_engine.dart';
import '../models/download_task.dart';
import '../models/harvested_video.dart';
import '../models/scrape_result.dart';
import '../state/download_repository.dart';

/// Test-Oberfläche für die portierten Engines (Scraper, Video Harvester,
/// Downloader) — bewusst schlicht gehalten, kein Design-Anspruch. Zweck ist
/// zu zeigen, dass die Dart-Ports tatsächlich funktionieren, nicht nur
/// unbenutzter Bibliothekscode sind. Das eigentliche NEXUS-UI (Tabs,
/// Adressleiste, Mediathek) kommt erst in der nächsten Stufe.
class ToolsTestScreen extends StatefulWidget {
  const ToolsTestScreen({super.key});

  @override
  State<ToolsTestScreen> createState() => _ToolsTestScreenState();
}

class _ToolsTestScreenState extends State<ToolsTestScreen> {
  final _urlController =
      TextEditingController(text: 'https://example.com');

  bool _scraping = false;
  bool _harvesting = false;
  String? _error;
  ScrapeResult? _scrapeResult;
  List<HarvestedVideo> _harvested = [];

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _runScraper() async {
    setState(() {
      _scraping = true;
      _error = null;
      _scrapeResult = null;
    });
    try {
      final result = await ScraperEngine.scrape(_urlController.text.trim());
      setState(() => _scrapeResult = result);
    } catch (e) {
      setState(() => _error = 'Scraper-Fehler: $e');
    } finally {
      setState(() => _scraping = false);
    }
  }

  Future<void> _runHarvester() async {
    setState(() {
      _harvesting = true;
      _error = null;
      _harvested = [];
    });
    try {
      final result =
          await VideoHarvesterEngine.harvest(_urlController.text.trim());
      setState(() => _harvested = result);
    } catch (e) {
      setState(() => _error = 'Harvester-Fehler: $e');
    } finally {
      setState(() => _harvesting = false);
    }
  }

  Future<void> _downloadVideo(HarvestedVideo video) async {
    final task = DownloadRepository.instance.start(video.title, video.url);
    try {
      await VideoDownloader.download(
        video.url,
        video.title,
        referer: _urlController.text.trim(),
        onProgress: (progress) {
          if (progress.percent >= 0) {
            DownloadRepository.instance.update(task, progress.percent);
          }
        },
      );
      DownloadRepository.instance.finish(task);
    } catch (e) {
      DownloadRepository.instance.fail(task, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('NEXUS · Werkzeug-Test')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'Seiten-URL',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _scraping ? null : _runScraper,
                  child: Text(_scraping ? 'Läuft…' : 'Komplett-Analyse'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: _harvesting ? null : _runHarvester,
                  child: Text(_harvesting ? 'Läuft…' : 'Video Harvester'),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          if (_scrapeResult case final r?) ...[
            const SizedBox(height: 20),
            Text('Titel: ${r.title}',
                style: Theme.of(context).textTheme.titleMedium),
            Text('${r.links.length} Links · ${r.media.length} Medien · '
                '${(r.htmlSize / 1024).toStringAsFixed(1)} KB HTML'),
            const SizedBox(height: 8),
            ...r.media.take(20).map((m) => Text('• $m',
                style: Theme.of(context).textTheme.bodySmall)),
          ],
          if (_harvested.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('${_harvested.length} Treffer',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ..._harvested.map(
              (v) => Card(
                child: ListTile(
                  title: Text(v.title.isEmpty ? v.host : v.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${v.type} · ${v.status}\n${v.url}',
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.download),
                    onPressed: () => _downloadVideo(v),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Divider(),
          const Text('Downloads (dieser Sitzung)'),
          ListenableBuilder(
            listenable: DownloadRepository.instance,
            builder: (context, _) {
              final tasks = DownloadRepository.instance.activeAndRecent();
              if (tasks.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Noch keine Downloads gestartet.'),
                );
              }
              return Column(
                children: tasks.map((t) => _DownloadRow(task: t)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DownloadRow extends StatelessWidget {
  final DownloadTask task;
  const _DownloadRow({required this.task});

  @override
  Widget build(BuildContext context) {
    final subtitle = switch (task.state) {
      DownloadState.queued => 'Wartet…',
      DownloadState.downloading => '${task.percent}%',
      DownloadState.done => 'Fertig',
      DownloadState.failed => 'Fehler: ${task.errorMessage}',
    };
    return ListTile(
      dense: true,
      title: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle),
      trailing: task.state == DownloadState.downloading
          ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                value: task.percent > 0 ? task.percent / 100 : null,
              ),
            )
          : task.state == DownloadState.done
              ? const Icon(Icons.check_circle, color: Colors.green)
              : task.state == DownloadState.failed
                  ? const Icon(Icons.error, color: Colors.redAccent)
                  : null,
    );
  }
}
