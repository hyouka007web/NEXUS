import 'package:flutter/material.dart';
import 'package:nexus/services/video_downloader.dart';

/// MediathekScreen: Download-Manager mit Fortschrittsbalken, Offline-Player.
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
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    style: const TextStyle(color: Colors.white70),
                    decoration: InputDecoration(
                      hintText: 'ARD-Mediathek-URL',
                      hintStyle: const TextStyle(color: Colors.white38),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _scrapeArd,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD7FF00)),
                  child: const Text('Scrapen'),
                ),
              ],
            ),
          ),
          if (_scraperStatus.isNotEmpty)
            Padding(padding: const EdgeInsets.all(8.0), child: Text(_scraperStatus, style: const TextStyle(color: Color(0xFF8FBF00)))),
          Expanded(
            child: VideoDownloader.downloads.isEmpty
                ? const Center(child: Text('Keine Downloads', style: TextStyle(color: Colors.white54)))
                : ListView.builder(
                    itemCount: VideoDownloader.downloads.length,
                    itemBuilder: (context, index) {
                      final entry = VideoDownloader.downloads[index];
                      final isDone = entry.status == DownloadStatus.completed;
                      final isFailed = entry.status == DownloadStatus.failed;
                      
                      return Card(
                        color: const Color(0xFF2A2E24),
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Column(
                          children: [
                            ListTile(
                              leading: CircleChild(backgroundColor: const Color(0xFFD7FF00), child: const Icon(Icons.video_library, color: Colors.black)),
                              title: Text(entry.title, style: const TextStyle(color: Colors.white)),
                              subtitle: Text("${_formatBytes(entry.receivedBytes)}/${_formatBytes(entry.totalBytes)} • ${entry.type.toUpperCase()}", style: const TextStyle(color: Colors.white54)),
                              trailing: isDone
                                  ? const Icon(Icons.check, color: Color(0xFF8FBF00))
                                  : isFailed
                                      ? const Icon(Icons.error, color: Color(0xFFFF3B30))
                                      : const SizedBox.shrink(),
                            ),
                            if (entry.status == DownloadStatus.downloading)
                              LinearProgressIndicator(
                                value: entry.progress,
                                backgroundColor: Colors.grey[800],
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF8FBF00)),
                              ),
                            if (isDone && entry.localPath != null)
                              TextButton.icon(
                                onPressed: () => _playVideo(entry.localPath!),
                                icon: const Icon(Icons.play_arrow, color: Color(0xFFD7FF00)),
                                label: const Text('Abspielen', style: TextStyle(color: Color(0xFFD7FF00))),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _playVideo(String path) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: const Color(0xFF0B0C0A), title: const Text('Video-Player', style: TextStyle(color: Color(0xFFD7FF00)))),
      body: Center(child: Text('Pfad: $path', style: const TextStyle(color: Colors.white))),
    )));
  }
}

class CircleChild extends StatelessWidget {
  final Color backgroundColor;
  final Widget child;
  const CircleChild({required this.backgroundColor, required this.child});

  @override
  Widget build(BuildContext context) => CircleAvatar(backgroundColor: backgroundColor, child: child, radius: 16);
}
