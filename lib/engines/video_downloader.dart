import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import '../models/video_entry.dart';

/// NEXUS Medien-Downloader. Unterstützt progressive HTTP(S)-Medien mit
/// Resume sowie öffentliche, unverschlüsselte HLS-Playlists. Umgeht
/// bewusst keine DRM-, Login-, CAPTCHA- oder Bezahlschranken — 1:1-
/// Verhalten zu Kotlins `VideoDownloader`.
class VideoDownloader {
  VideoDownloader._();

  static const String _indexFile = 'mediathek_index.json';
  static const Duration _connectTimeout = Duration(seconds: 15);
  static const Duration _readTimeout = Duration(seconds: 45);
  static const String _userAgent = 'Mozilla/5.0 (Linux; NEXUS Browser/1.0)';

  static Future<Directory> downloadsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> _indexFilePath() async {
    final dir = await downloadsDir();
    return File('${dir.path}/$_indexFile');
  }

  static Future<List<VideoEntry>> loadIndex() async {
    final file = await _indexFilePath();
    if (!await file.exists()) return [];
    try {
      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      final entries = raw
          .map((e) => VideoEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      final existing = <VideoEntry>[];
      for (final e in entries) {
        if (await File(e.filePath).exists()) existing.add(e);
      }
      return existing;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveIndex(List<VideoEntry> entries) async {
    final target = await _indexFilePath();
    final json = jsonEncode(entries.map((e) => e.toJson()).toList());
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(json);
    try {
      await tmp.rename(target.path);
    } catch (_) {
      await target.writeAsString(json);
    }
  }

  static Future<VideoEntry> download(
    String mediaUrl,
    String pageTitle, {
    String? referer,
    void Function(DownloadProgress)? onProgress,
  }) async {
    if (!mediaUrl.startsWith('http://') && !mediaUrl.startsWith('https://')) {
      throw ArgumentError('mediaUrl muss http(s) sein: $mediaUrl');
    }
    return _looksLikeHls(mediaUrl)
        ? _downloadHls(mediaUrl, pageTitle, referer, onProgress)
        : _downloadDirect(mediaUrl, pageTitle, referer, onProgress);
  }

  static Future<VideoEntry> _downloadDirect(
    String mediaUrl,
    String pageTitle,
    String? referer,
    void Function(DownloadProgress)? onProgress,
  ) async {
    final id = _randomId();
    final ext = _guessExtension(mediaUrl, null);
    final dir = await downloadsDir();
    final baseName = _sanitize(pageTitle).let(
      (s) => s.length > 60 ? s.substring(0, 60) : s,
    );
    final target = File(
      '${dir.path}/${baseName.isEmpty ? 'video' : baseName}-$id.$ext',
    );
    final part = File('${target.path}.part');
    int existing = await part.exists() ? await part.length() : 0;

    final client = HttpClient()..connectionTimeout = _connectTimeout;
    try {
      final response = await _openRange(
        client,
        mediaUrl,
        referer,
        existing > 0 ? existing : null,
      ).timeout(_readTimeout);

      // dart:io hat wie java.net.HttpURLConnection keine Konstante für 416
      // (Range Not Satisfiable) — hier als Literalwert, gleicher Grund wie
      // im Kotlin-Original.
      if (response.statusCode == 416) {
        await response.drain<void>();
        existing = 0;
        if (await part.exists()) await part.delete();
        return _downloadDirect(mediaUrl, pageTitle, referer, onProgress);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw StateError('HTTP ${response.statusCode}');
      }

      final supportsResume = response.statusCode == 206;
      if (!supportsResume && existing > 0) {
        existing = 0;
        if (await part.exists()) await part.delete();
      }
      final contentLength = response.contentLength;
      final total = contentLength >= 0 ? contentLength + existing : -1;
      final append = supportsResume && existing > 0;

      final sink = part.openWrite(
        mode: append ? FileMode.append : FileMode.write,
      );
      int done = existing;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          done += chunk.length;
          final percent =
              total > 0 ? ((done * 100) ~/ total).clamp(0, 100) : -1;
          onProgress?.call(DownloadProgress(
            bytes: done,
            total: total,
            percent: percent,
          ));
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      await part.rename(target.path);
      final entry = _makeEntry(id, pageTitle, target, mediaUrl,
          await target.length());
      await _saveIndex([...await loadIndex(), entry]);
      return entry;
    } finally {
      client.close(force: true);
    }
  }

  static Future<HttpClientResponse> _openRange(
    HttpClient client,
    String url,
    String? referer,
    int? rangeFrom,
  ) async {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
    request.headers.set(HttpHeaders.acceptHeader, '*/*');
    if (referer != null && referer.isNotEmpty) {
      request.headers.set(HttpHeaders.refererHeader, referer);
    }
    if (rangeFrom != null && rangeFrom > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$rangeFrom-');
    }
    return request.close();
  }

  static Future<VideoEntry> _downloadHls(
    String mediaUrl,
    String pageTitle,
    String? referer,
    void Function(DownloadProgress)? onProgress,
  ) async {
    final master = await _fetchText(mediaUrl, referer);
    final playlist = await _chooseVariant(master, mediaUrl, referer);
    if (playlist.toUpperCase().contains('#EXT-X-KEY') &&
        !playlist.toUpperCase().contains('METHOD=NONE')) {
      throw StateError('Verschlüsselte HLS-Streams werden nicht entschlüsselt');
    }
    final segments = _parseSegments(playlist, mediaUrl).take(5000).toList();
    if (segments.isEmpty) {
      throw StateError('HLS-Playlist enthält keine Segmente');
    }

    final id = _randomId();
    final ext = playlist.contains('#EXT-X-MAP') ? 'mp4' : 'ts';
    final dir = await downloadsDir();
    final baseName = _sanitize(pageTitle).let(
      (s) => s.length > 60 ? s.substring(0, 60) : s,
    );
    final target = File(
      '${dir.path}/${baseName.isEmpty ? 'video' : baseName}-$id.$ext',
    );
    final part = File('${target.path}.part');

    final client = HttpClient()..connectionTimeout = _connectTimeout;
    final sink = part.openWrite();
    int done = 0;
    try {
      for (var i = 0; i < segments.length; i++) {
        final response =
            await _openRange(client, segments[i], referer, null)
                .timeout(_readTimeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          await response.drain<void>();
          throw StateError('HTTP ${response.statusCode}');
        }
        await for (final chunk in response) {
          sink.add(chunk);
          done += chunk.length;
        }
        onProgress?.call(DownloadProgress(
          bytes: done,
          total: -1,
          percent: ((i + 1) * 100 ~/ segments.length),
        ));
      }
      await sink.flush();
    } finally {
      await sink.close();
      client.close(force: true);
    }

    await part.rename(target.path);
    final entry =
        _makeEntry(id, pageTitle, target, mediaUrl, await target.length());
    await _saveIndex([...await loadIndex(), entry]);
    return entry;
  }

  static Future<String> _chooseVariant(
    String master,
    String base,
    String? referer,
  ) async {
    final lines =
        master.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (!lines.any((l) => l.toUpperCase().startsWith('#EXT-X-STREAM-INF'))) {
      return master;
    }
    String? bestUrl;
    int bestBandwidth = -1;
    final bandwidthPattern =
        RegExp(r'(?:AVERAGE-BANDWIDTH|BANDWIDTH)=(\d+)', caseSensitive: false);
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].toUpperCase().startsWith('#EXT-X-STREAM-INF')) continue;
      final bandwidth =
          int.tryParse(bandwidthPattern.firstMatch(lines[i])?.group(1) ?? '') ?? 0;
      final next = lines
          .skip(i + 1)
          .firstWhere((l) => !l.startsWith('#'), orElse: () => '');
      if (next.isEmpty) continue;
      if (bandwidth > bestBandwidth) {
        bestBandwidth = bandwidth;
        bestUrl = _resolve(base, next);
      }
    }
    if (bestUrl == null) return master;
    return _fetchText(bestUrl, referer);
  }

  static List<String> _parseSegments(String playlist, String base) {
    final out = <String>[];
    String? map;
    final mapUriPattern = RegExp(r'URI="([^"]+)"');
    for (final raw in playlist.split('\n')) {
      final line = raw.trim();
      if (line.toUpperCase().startsWith('#EXT-X-MAP')) {
        final uri = mapUriPattern.firstMatch(line)?.group(1);
        if (uri != null) map = _resolve(base, uri);
      } else if (line.isNotEmpty && !line.startsWith('#')) {
        out.add(_resolve(base, line));
      }
    }
    if (map != null) out.insert(0, map);
    return out;
  }

  static Future<String> _fetchText(String url, String? referer) async {
    final client = HttpClient()..connectionTimeout = _connectTimeout;
    try {
      final response =
          await _openRange(client, url, referer, null).timeout(_readTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw StateError('HTTP ${response.statusCode}');
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length >= 8 * 1024 * 1024) break;
      }
      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      client.close(force: true);
    }
  }

  static bool _looksLikeHls(String url) {
    try {
      return Uri.parse(url).path.toLowerCase().endsWith('.m3u8');
    } catch (_) {
      return false;
    }
  }

  static String _guessExtension(String url, String? contentType) {
    String path;
    try {
      path = Uri.parse(url).path.toLowerCase();
    } catch (_) {
      path = '';
    }
    final fromPath = RegExp(r'\.([a-z0-9]{2,5})$').firstMatch(path)?.group(1);
    if (fromPath != null) return fromPath;
    if (contentType?.contains('webm') == true) return 'webm';
    if (contentType?.contains('mpeg') == true) return 'mpg';
    if (contentType?.contains('mp4') == true) return 'mp4';
    return 'bin';
  }

  static VideoEntry _makeEntry(
    String id,
    String title,
    File target,
    String source,
    int sizeBytes,
  ) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final formatted =
        '${two(now.day)}.${two(now.month)}.${now.year} ${two(now.hour)}:${two(now.minute)}';
    return VideoEntry(
      id: id,
      title: title.trim().isEmpty ? 'Video $id' : title,
      filePath: target.path,
      sourceUrl: source,
      downloadedAt: formatted,
      sizeBytes: sizeBytes,
    );
  }

  static String _sanitize(String value) {
    final cleaned =
        value.replaceAll(RegExp(r'[\\/:*?"<>|\r\n]+'), '_').trim();
    return cleaned.isEmpty ? 'video' : cleaned;
  }

  static String _resolve(String base, String child) =>
      Uri.parse(base).resolve(child).toString();

  static Future<void> delete(VideoEntry entry) async {
    final file = File(entry.filePath);
    if (await file.exists()) await file.delete();
    final remaining = (await loadIndex()).where((e) => e.id != entry.id).toList();
    await _saveIndex(remaining);
  }

  static String _randomId() {
    final rnd = Random.secure();
    return List.generate(12, (_) => rnd.nextInt(16).toRadixString(16)).join();
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) block) => block(this);
}
