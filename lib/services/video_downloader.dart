import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Video-Downloader: Scannt Webseiten per JS-Injection nach Video-Tags/HLS/DASH
/// und lädt diese native mit dart:io herunter.
class VideoDownloader {
  // ✅ Globale Liste aller gefundenen Videos (für Mediathek)
  static final List<VideoEntry> downloads = [];

  /// Scannt die aktuelle Webseite mit JS nach allen Video-Quellen
  static Future<List<VideoEntry>> scrapeVideos(dynamic webViewController) async {
    // JS-Injection: Scanne Video-Tags, Source-Tags, HLS- und DASH-Quellen
    final result = await webViewController.evaluateJavascript(source: '''
      (function() {
        var entries = [];
        
        // Standard Video-Tags & Source-Tags
        document.querySelectorAll('video, source').forEach(function(el) {
          var src = el.src || el.getAttribute('src');
          if (src && src.startsWith('http')) {
            entries.push({url: src, type: 'video', title: el.getAttribute('data-title') || ''});
          }
        });
        
        // HLS-Streams (.m3u8)
        document.querySelectorAll('video, source').forEach(function(el) {
          var src = el.src || el.getAttribute('src');
          if (src && src.includes('.m3u8')) {
            entries.push({url: src, type: 'hls', title: el.getAttribute('data-title') || ''});
          }
        });
        
        // DASH-Streams (.mpd)
        document.querySelectorAll('video, source').forEach(function(el) {
          var src = el.src || el.getAttribute('src');
          if (src && src.includes('.mpd')) {
            entries.push({url: src, type: 'dash', title: el.getAttribute('data-title') || ''});
          }
        });
        
        // Skript-Inhalte nach .m3u8/.mpd durchsuchen
        document.querySelectorAll('script').forEach(function(script) {
          var text = script.textContent || '';
          var urls = text.match(/https?:\/\/[^\s"']+\.(m3u8|mpd)/gi);
          if (urls) {
            urls.forEach(function(url) {
              entries.push({url: url, type: 'manifest', title: ''});
            });
          }
        });
        
        // JSON.stringify für Rückgabe
        return JSON.stringify(entries);
      })();
    ''');

    if (result == null) return [];
    final List<dynamic> parsed = jsonDecode(result);
    return parsed.map((item) => VideoEntry.fromJson(item)).toList();
  }

  /// Native Download via dart:io
  static Future<VideoEntry> download(String url, {String title = ''}) async {
    final entry = VideoEntry(
      url: url,
      type: _detectType(url),
      title: title,
      status: DownloadStatus.pending,
      progress: 0.0,
    );
    downloads.add(entry);

    final dir = await getApplicationDocumentsDirectory();
    final filename = title.isNotEmpty ? '$title.mp4' : 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final file = File('${dir.path}/$filename');

    entry.status = DownloadStatus.downloading;

    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) {
        entry.status = DownloadStatus.failed;
        return entry;
      }

      final contentLength = response.contentLength;
      var received = 0;

      entry.totalBytes = contentLength;

      final sink = file.openWrite();
      response.listen(
        (chunk) {
          sink.add(chunk);
          received += chunk.length;
          entry.receivedBytes = received;
          entry.progress = contentLength > 0 ? received / contentLength : 0.0;
        },
        onDone: () async {
          await sink.flush();
          await sink.close();
          entry.status = DownloadStatus.completed;
          entry.localPath = file.path;
        },
        onError: (e) {
          entry.status = DownloadStatus.failed;
        },
      );
    } catch (e) {
      entry.status = DownloadStatus.failed;
    }
    return entry;
  }

  static String _detectType(String url) {
    if (url.contains('.m3u8')) return 'hls';
    if (url.contains('.mpd')) return 'dash';
    return 'video';
  }
}

enum DownloadStatus { pending, downloading, completed, failed }

class VideoEntry {
  final String url;
  final String type;
  final String title;
  DownloadStatus status;
  double progress;
  int totalBytes;
  int receivedBytes;
  String? localPath;

  VideoEntry({
    required this.url,
    required this.type,
    required this.title,
    required this.status,
    required this.progress,
    this.totalBytes = 0,
    this.receivedBytes = 0,
    this.localPath,
  });

  factory VideoEntry.fromJson(Map<String, dynamic> json) {
    return VideoEntry(
      url: json['url'] ?? '',
      type: json['type'] ?? 'video',
      title: json['title'] ?? '',
      status: DownloadStatus.pending,
      progress: 0.0,
    );
  }
}
