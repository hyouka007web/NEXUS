import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:nexus/services/mediathek_scraper.dart';

/// VideoDownloader: Downloadt Videos via JS-Injection + native dart:io HTTP-Streaming.
/// Scans <video>, <source>, HLS (.m3u8), DASH (.mpd) manifests.
/// Unterstützt ARD-Mediathek-Scraping.
class VideoDownloader {
  static final List<VideoEntry> downloads = [];

  /// Scannt Webseite via JS-Injection nach Video-Quellen.
  static Future<List<VideoEntry>> scrapeVideos(dynamic controller) async {
    final result = await controller.evaluateJavascript(source: '''
      (function() {
        var entries = [];
        
        document.querySelectorAll('video, source').forEach(function(el) {
          var src = el.src || el.getAttribute('src');
          if (src && src.indexOf('http') === 0) {
            entries.push(JSON.stringify({url: src, type: 'video'}));
          }
        });
        
        document.querySelectorAll('script').forEach(function(script) {
          var text = script.textContent || '';
          var urls = text.match(/https?:\\/\\/[^\\s"']+\\.m3u8/gi);
          if (urls) {
            urls.forEach(function(url) {
              entries.push(JSON.stringify({url: url, type: 'hls'}));
            });
          }
        });
        
        document.querySelectorAll('script').forEach(function(script) {
          var text = script.textContent || '';
          var urls = text.match(/https?:\\/\\/[^\\s"']+\\.mpd/gi);
          if (urls) {
            urls.forEach(function(url) {
              entries.push(JSON.stringify({url: url, type: 'dash'}));
            });
          }
        });
        
        return JSON.stringify(entries);
      })();
    ''') ?? '[]';

    if (result == '[]') return [];
    final List<dynamic> parsed = jsonDecode(result);
    return parsed.map((item) => VideoEntry.fromJson(jsonDecode(item))).toList();
  }

  /// Scrappt ARD-Mediathek-URL und startet Downloads.
  static Future<List<VideoEntry>> downloadArd(String url) async {
    final content = await MediathekScraper.scrapeArd(url);
    final List<VideoEntry> entries = [];

    for (final stream in content.streamUrls) {
      final entry = await download(stream.url, title: content.title, type: stream.type);
      entries.add(entry);
    }
    return entries;
  }

  /// Native Download via dart:io HTTP-Streaming
  static Future<VideoEntry> download(String url, {String title = '', String type = 'video'}) async {
    final entry = VideoEntry(
      url: url,
      type: type,
      title: title.isNotEmpty ? title : 'video_${DateTime.now().millisecondsSinceEpoch}',
      status: DownloadStatus.downloading,
      progress: 0.0,
    );
    downloads.add(entry);

    final dir = await getApplicationDocumentsDirectory();
    final filename = '${entry.title}.mp4';
    final file = File('${dir.path}/$filename');

    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        entry.status = DownloadStatus.failed;
        return entry;
      }

      final contentLength = response.contentLength;
      entry.totalBytes = contentLength;

      var received = 0;
      final sink = file.openWrite();
      
      response.listen(
        (chunk) {
          sink.add(chunk);
          received += chunk.length;
          entry.receivedBytes = received;
          if (contentLength > 0) {
            entry.progress = received / contentLength;
          }
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
}

enum DownloadStatus { pending, downloading, completed, failed }

class VideoEntry {
  final String url;
  String type;
  String title;
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
      title: '',
      status: DownloadStatus.pending,
      progress: 0.0,
    );
  }
}
