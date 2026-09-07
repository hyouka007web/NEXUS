code = '''import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:nexus_flutter/models/video_entry.dart';

class VideoDownloader {
  static const Duration _connectTimeout = Duration(seconds: 15);
  static const Duration _readTimeout = Duration(seconds: 30);
  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  static Future<File> download(
    String url,
    String savePath, {
    String? title,
    String? referer,
    Map<String, String> headers = const {},
    void Function(int count, int total)? onProgress,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = _connectTimeout;
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, headers['User-Agent'] ?? _userAgent);
      if (referer != null && referer.isNotEmpty) {
        req.headers.set(HttpHeaders.refererHeader, referer);
      }
      headers.forEach((k, v) {
        if (k.toLowerCase() != 'user-agent' && k.toLowerCase() != 'referer') {
          req.headers.set(k, v);
        }
      });

      final res = await req.close().timeout(_connectTimeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw HttpException('HTTP Status ${res.statusCode}');
      }

      final file = File(savePath);
      final sink = file.openWrite();
      final total = res.contentLength;
      int downloaded = 0;

      await for (final chunk in res.timeout(_readTimeout)) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (onProgress != null) {
          onProgress(downloaded, total);
        }
      }
      await sink.flush();
      await sink.close();

      await _addToIndex(VideoEntry(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title ?? 'Video Download',
        filePath: savePath,
        totalBytes: downloaded,
        date: DateTime.now(),
      ));

      return file;
    } finally {
      client.close();
    }
  }

  static Future<String> _fetchText(String url, String? referer, [Map<String, String> headers = const {}]) async {
    final client = HttpClient();
    client.connectionTimeout = _connectTimeout;
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, headers['User-Agent'] ?? _userAgent);
      if (referer != null && referer.isNotEmpty) {
        req.headers.set(HttpHeaders.refererHeader, referer);
      }
      headers.forEach((k, v) {
        if (k.toLowerCase() != 'user-agent' && k.toLowerCase() != 'referer') {
          req.headers.set(k, v);
        }
      });

      final res = await req.close().timeout(_connectTimeout);
      final bodyBytes = await res.fold<List<int>>([], (p, e) => p..addAll(e)).timeout(_readTimeout);
      return utf8.decode(bodyBytes);
    } finally {
      client.close();
    }
  }

  static Future<String?> parseMasterPlaylist(String mediaUrl, String? referer, [Map<String, String> headers = const {}]) async {
    final master = await _fetchText(mediaUrl, referer, headers);
    if (!master.contains('#EXTM3U')) return null;
    if (!master.contains('#EXT-X-STREAM-INF')) return mediaUrl;

    final lines = master.split('\\n');
    String? bestUrl;
    int maxBw = -1;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        int bw = 0;
        final bwMatch = RegExp(r'BANDWIDTH=(\\d+)').firstMatch(line);
        if (bwMatch != null) {
          bw = int.tryParse(bwMatch.group(1) ?? '0') ?? 0;
        }
        if (i + 1 < lines.length) {
          final nextLine = lines[i + 1].trim();
          if (nextLine.isNotEmpty && !nextLine.startsWith('#')) {
            if (bw > maxBw) {
              maxBw = bw;
              bestUrl = nextLine.startsWith('http')
                  ? nextLine
                  : Uri.parse(mediaUrl).resolve(nextLine).toString();
            }
          }
        }
      }
    }
    return bestUrl ?? mediaUrl;
  }

  static Future<List<VideoEntry>> loadIndex() async {
    try {
      final file = File('/data/data/com.nexus.browser/files/downloads_index.json');
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final List list = jsonDecode(content);
      return list.map((e) => VideoEntry.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _addToIndex(VideoEntry entry) async {
    try {
      final items = await loadIndex();
      items.add(entry);
      final file = File('/data/data/com.nexus.browser/files/downloads_index.json');
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(items.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  static Future<void> delete(VideoEntry entry) async {
    try {
      final file = File(entry.filePath);
      if (await file.exists()) await file.delete();
      final items = await loadIndex();
      items.removeWhere((e) => e.id == entry.id);
      final indexFile = File('/data/data/com.nexus.browser/files/downloads_index.json');
      await indexFile.writeAsString(jsonEncode(items.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }
}
'''

with open('lib/engines/video_downloader.dart', 'w') as f:
    f.write(code)

print("video_downloader.dart mit VideoEntry & gemischten Parametern gefixt.")
