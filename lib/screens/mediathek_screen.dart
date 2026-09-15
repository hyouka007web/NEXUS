import 'package:flutter/material.dart';
import 'package:nexus/services/video_downloader.dart';

class MediathekScreen extends StatefulWidget {
  const MediathekScreen({super.key});

  @override
  State<MediathekScreen> createState() => _MediathekScreenState();
}

class _MediathekScreenState extends State<MediathekScreen> {
  final TextEditingController _urlController = TextEditingController();
  String _scraperStatus = '';

  Future<void> _scrapeArd() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() => _scraperStatus = 'Scrape läuft...');
    try {
      final entries = await VideoDownloader.downloadArd(url);
      setState(() => _scraperStatus = '${entries.length} Video(s) gefunden!');
    } catch (e) {
      setState(() => _scraperStatus = 'Fehler: $e');
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1048576) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    if (bytes < 1073741824) return "${(bytes / 1048576).toStringAsFixed(1)} MB";
    return "${(bytes / 1073741824).toStringAsFixed(1)} GB";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141610),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0C0A),
        title: const Text('NEXUS Mediathek', style: TextStyle(color: Color(0xFFD7FF00))),
        bottom: AppBar(
          backgroundColor: const Color(0xFF0B0C0A),
          title: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  style: const TextStyle(color: Colors.white70),
                  decoration: InputDecoration(
                    hintText: 'ARD-Mediathek-URL einfügen',
                    hintStyle: const TextStyle(color: Colors.white38),
                    border: const OutlineInputBorder(),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFD7FF00))),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _scrapeArd,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD7FF00), foregroundColor: Colors.black),
                child: const Text('Scrapen'),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          if (_scraperStatus.isNotEmpty)
            Padding(padding: const EdgeInsets.all(8.0), child: Text(_scraperStatus, style: const TextStyle(color: Color(0xFF8FBF00)))),
          Expanded(
            child: VideoDownloader.downloads.isEmpty
                ? const Center(child: Text('Keine Downloads', style: TextStyle(color: Colors.white54)))
                : ListView.builder(
                    itemCount: VideoDownloader.downloads.length,
                    itemBuilder: (context, index) {
                      final entry = VideoDownloader.downloads[index];
                      return ListTile(
                        title: Text(entry.title, style: const TextStyle(color: Colors.white)),
                        subtitle: Text("${_formatBytes(entry.receivedBytes)}/${_formatBytes(entry.totalBytes)}", style: const TextStyle(color: Colors.white54)),
                        trailing: entry.status == DownloadStatus.completed ? const Icon(Icons.download_done, color: Color(0xFFD7FF00)) : const SizedBox.shrink(),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
