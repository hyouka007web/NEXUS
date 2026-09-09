import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/video_entry.dart';

/// Erlaubt es, einen laufenden Download von außen abzubrechen (für die
/// Batch-Download-Warteschlange: "Pausieren" bricht den aktuellen Request
/// sauber ab, der bereits geschriebene `.part`-Anteil bleibt liegen und
/// wird beim nächsten Aufruf über den ohnehin vorhandenen Range-Resume
/// fortgesetzt — kein separater Pause/Resume-Mechanismus nötig, das ist
/// derselbe Weg wie bei einem echten Netzwerkabbruch.
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class DownloadCancelledException implements Exception {
  @override
  String toString() => 'Download pausiert';
}

/// Live-Fortschritt während eines laufenden Downloads. [total] ist -1, wenn
/// die Gegenstelle keine Content-Length liefert (z.B. bei manchen
/// HLS-Quellen).
class DownloadProgress {
  final int bytes;
  final int total;
  final int percent;

  const DownloadProgress({
    required this.bytes,
    required this.total,
    required this.percent,
  });
}

/// NEXUS Medien-Downloader. Unterstützt progressive HTTP(S)-Medien mit
/// Resume sowie öffentliche, unverschlüsselte HLS-Playlists.
///
/// **Bugfix-Hinweis:** eine zwischenzeitlich eingespielte Version dieser
/// Datei nahm einen fertigen Dateipfad als zweiten Parameter entgegen,
/// während die Aufrufer (browser_screen.dart, tools_test_screen.dart)
/// weiterhin einen Anzeigetitel übergeben haben ("Staffel 1 von...") — der
/// wurde dann direkt als Dateipfad benutzt, was strukturell nie
/// zuverlässig funktionieren konnte. Dazu kam ein hartkodierter Index-Pfad
/// (`/data/data/com.nexus.browser/...`), der bei abweichender
/// `applicationId` ins Leere zeigt. Diese Fassung generiert den Dateinamen
/// wieder intern aus dem Titel und nutzt `path_provider` statt eines
/// hartkodierten Pfads — passend zu dem, was die Aufrufer tatsächlich
/// übergeben.
class VideoDownloader {
  VideoDownloader._();

  static const String _indexFile = 'mediathek_index.json';
  static const Duration _connectTimeout = Duration(seconds: 15);
  static const Duration _readTimeout = Duration(seconds: 45);
  static const String _defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

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

  static Future<void> delete(VideoEntry entry) async {
    final file = File(entry.filePath);
    if (await file.exists()) await file.delete();
    final remaining =
        (await loadIndex()).where((e) => e.id != entry.id).toList();
    await _saveIndex(remaining);
  }

  static Future<VideoEntry> download(
    String mediaUrl,
    String pageTitle, {
    String? referer,
    Map<String, String> headers = const {},
    void Function(DownloadProgress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (!mediaUrl.startsWith('http://') && !mediaUrl.startsWith('https://')) {
      throw ArgumentError('mediaUrl muss http(s) sein: $mediaUrl');
    }
    if (_looksLikeDash(mediaUrl)) {
      // DASH-Manifeste (.mpd) sind XML-Playlists, keine Videodatei selbst —
      // ohne diese Prüfung würde ein Klartext-Download die XML-Datei
      // "erfolgreich" unter einem Video-Dateinamen speichern.
      throw StateError(
        'DASH-Streams (.mpd) werden noch nicht unterstützt — nur HLS '
        '(.m3u8) und direkte Dateien (mp4/webm/...).',
      );
    }
    return _looksLikeHls(mediaUrl)
        ? _downloadHls(mediaUrl, pageTitle, referer, headers, onProgress, cancelToken)
        : _downloadDirect(mediaUrl, pageTitle, referer, headers, onProgress, cancelToken);
  }

  static Future<VideoEntry> _downloadDirect(
    String mediaUrl,
    String pageTitle,
    String? referer,
    Map<String, String> headers,
    void Function(DownloadProgress)? onProgress,
    CancelToken? cancelToken,
  ) async {
    // Deterministisch statt zufällig: derselbe mediaUrl+Titel ergibt
    // denselben Ziel-/.part-Dateinamen. Nur dadurch findet ein späterer
    // "Fortsetzen"-Aufruf (neue Batch-Download-Warteschlange, siehe unten)
    // dieselbe, bereits teilweise geschriebene .part-Datei wieder — mit
    // einer zufälligen ID pro Aufruf (vorherige Fassung) wäre jeder erneute
    // Versuch bei 0 gestartet, selbst wenn schon Bytes vorlagen.
    final id = _deterministicId(mediaUrl, pageTitle);
    final ext = _guessExtension(mediaUrl);
    final dir = await downloadsDir();
    final baseName = _sanitize(pageTitle)
        .let((s) => s.length > 60 ? s.substring(0, 60) : s);
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
        headers,
        existing > 0 ? existing : null,
      ).timeout(_readTimeout);

      // dart:io hat wie java.net.HttpURLConnection keine Konstante für 416
      // (Range Not Satisfiable) — hier als Literalwert.
      if (response.statusCode == 416) {
        await response.drain<void>();
        existing = 0;
        if (await part.exists()) await part.delete();
        return _downloadDirect(mediaUrl, pageTitle, referer, headers, onProgress, cancelToken);
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

      final contentType = response.headers.value(HttpHeaders.contentTypeHeader) ?? '';
      if (contentType.contains('text/html') || contentType.contains('application/json')) {
        await response.drain<void>();
        // Klassischer stiller Fehler: Hotlink-Schutz oder eine nötige
        // Anmeldung liefert mit Statuscode 200 eine HTML-/JSON-Fehlerseite
        // statt der Videodatei.
        throw StateError(
          'Server hat keine Videodatei geliefert (Content-Type: '
          '$contentType) — vermutlich Hotlink-Schutz, Login oder Geoblock.',
        );
      }

      final contentLength = response.contentLength;
      final total = contentLength >= 0 ? contentLength + existing : -1;
      final append = supportsResume && existing > 0;

      final sink = part.openWrite(mode: append ? FileMode.append : FileMode.write);
      int done = existing;
      StreamSubscription<List<int>>? sub;
      try {
        final completer = Completer<void>();
        sub = response.listen(
          (chunk) {
            if (cancelToken?.isCancelled == true) {
              sub?.pause();
              if (!completer.isCompleted) completer.completeError(DownloadCancelledException());
              return;
            }
            sink.add(chunk);
            done += chunk.length;
            final percent = total > 0 ? ((done * 100) ~/ total).clamp(0, 100) : -1;
            onProgress?.call(DownloadProgress(bytes: done, total: total, percent: percent));
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (Object e) {
            if (!completer.isCompleted) completer.completeError(e);
          },
          cancelOnError: true,
        );
        await completer.future;
        await sink.flush();
      } finally {
        await sub?.cancel();
        await sink.close();
      }

      await part.rename(target.path);
      final entry = _makeEntry(id, pageTitle, target, mediaUrl, await target.length());
      await _saveIndex([...await loadIndex(), entry]);
      return entry;
    } on DownloadCancelledException {
      // .part bleibt bewusst liegen — der nächste Aufruf mit derselben
      // mediaUrl+Titel (also derselben deterministischen ID) setzt hier
      // über den oben ohnehin vorhandenen Range-Resume fort.
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  static Future<HttpClientResponse> _openRange(
    HttpClient client,
    String url,
    String? referer,
    Map<String, String> headers,
    int? rangeFrom,
  ) async {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.userAgentHeader, headers['User-Agent'] ?? _defaultUserAgent);
    request.headers.set(HttpHeaders.acceptHeader, '*/*');
    if (referer != null && referer.isNotEmpty) {
      request.headers.set(HttpHeaders.refererHeader, referer);
      try {
        final origin = Uri.parse(referer);
        request.headers.set(
          'Origin',
          '${origin.scheme}://${origin.host}${origin.hasPort ? ':${origin.port}' : ''}',
        );
      } catch (_) {
        // referer war keine gültige URL — Origin dann einfach weglassen.
      }
    }
    headers.forEach((key, value) {
      final lower = key.toLowerCase();
      if (lower != 'user-agent' && lower != 'referer') {
        request.headers.set(key, value);
      }
    });
    if (rangeFrom != null && rangeFrom > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$rangeFrom-');
    }
    return request.close();
  }

  static Future<VideoEntry> _downloadHls(
    String mediaUrl,
    String pageTitle,
    String? referer,
    Map<String, String> headers,
    void Function(DownloadProgress)? onProgress,
    CancelToken? cancelToken,
  ) async {
    final master = await _fetchText(mediaUrl, referer, headers);
    final playlist = await _chooseVariant(master, mediaUrl, referer, headers);
    if (playlist.toUpperCase().contains('#EXT-X-KEY') &&
        !playlist.toUpperCase().contains('METHOD=NONE')) {
      throw StateError('Verschlüsselte HLS-Streams werden nicht entschlüsselt');
    }
    final segments = _parseSegments(playlist, mediaUrl).take(5000).toList();
    if (segments.isEmpty) {
      throw StateError('HLS-Playlist enthält keine Segmente');
    }

    // Anders als beim direkten Download oben: hier gibt es noch KEIN
    // echtes Segment-Resume (welches Segment zuletzt geschrieben wurde
    // müsste separat mitgeführt werden). "Pausieren" bricht sauber ab,
    // ein späterer erneuter Aufruf beginnt beim Segment 0 neu — ehrliche
    // Einschränkung, keine stillschweigende Lücke.
    final id = _deterministicId(mediaUrl, pageTitle);
    final ext = playlist.contains('#EXT-X-MAP') ? 'mp4' : 'ts';
    final dir = await downloadsDir();
    final baseName = _sanitize(pageTitle)
        .let((s) => s.length > 60 ? s.substring(0, 60) : s);
    final target = File(
      '${dir.path}/${baseName.isEmpty ? 'video' : baseName}-$id.$ext',
    );
    final part = File('${target.path}.part');

    final client = HttpClient()..connectionTimeout = _connectTimeout;
    final sink = part.openWrite();
    int done = 0;
    try {
      for (var i = 0; i < segments.length; i++) {
        if (cancelToken?.isCancelled == true) {
          throw DownloadCancelledException();
        }
        final response = await _openRange(client, segments[i], referer, headers, null)
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
    final entry = _makeEntry(id, pageTitle, target, mediaUrl, await target.length());
    await _saveIndex([...await loadIndex(), entry]);
    return entry;
  }

  static Future<String> _chooseVariant(
    String master,
    String base,
    String? referer,
    Map<String, String> headers,
  ) async {
    final lines = master.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (!lines.any((l) => l.toUpperCase().startsWith('#EXT-X-STREAM-INF'))) {
      return master;
    }
    String? bestUrl;
    int bestBandwidth = -1;
    final bandwidthPattern = RegExp(r'(?:AVERAGE-BANDWIDTH|BANDWIDTH)=(\d+)', caseSensitive: false);
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].toUpperCase().startsWith('#EXT-X-STREAM-INF')) continue;
      final bandwidth = int.tryParse(bandwidthPattern.firstMatch(lines[i])?.group(1) ?? '') ?? 0;
      final next = lines.skip(i + 1).firstWhere((l) => !l.startsWith('#'), orElse: () => '');
      if (next.isEmpty) continue;
      if (bandwidth > bestBandwidth) {
        bestBandwidth = bandwidth;
        bestUrl = _resolve(base, next);
      }
    }
    if (bestUrl == null) return master;
    return _fetchText(bestUrl, referer, headers);
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

  static Future<String> _fetchText(String url, String? referer, Map<String, String> headers) async {
    final client = HttpClient()..connectionTimeout = _connectTimeout;
    try {
      final response = await _openRange(client, url, referer, headers, null).timeout(_readTimeout);
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

  static bool _looksLikeDash(String url) {
    try {
      return Uri.parse(url).path.toLowerCase().endsWith('.mpd');
    } catch (_) {
      return false;
    }
  }

  static String _guessExtension(String url) {
    String path;
    try {
      path = Uri.parse(url).path.toLowerCase();
    } catch (_) {
      path = '';
    }
    final fromPath = RegExp(r'\.([a-z0-9]{2,5})$').firstMatch(path)?.group(1);
    return fromPath ?? 'mp4';
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
    final cleaned = value.replaceAll(RegExp(r'[\\/:*?"<>|\r\n]+'), '_').trim();
    return cleaned.isEmpty ? 'video' : cleaned;
  }

  static String _resolve(String base, String child) => Uri.parse(base).resolve(child).toString();

  /// Deterministisch statt zufällig, extra kurz gehasht (8 Hex-Zeichen
  /// reichen für Kollisionsfreiheit innerhalb einer Downloads-Warteschlange,
  /// das ist kein Sicherheits-Hash). Dieselbe mediaUrl+Titel-Kombination
  /// ergibt immer denselben Dateinamen — Voraussetzung dafür, dass
  /// "Pausieren" (CancelToken) später an derselben .part-Datei fortsetzt.
  static String _deterministicId(String mediaUrl, String title) {
    final input = '$mediaUrl|$title';
    var hash = 0x811C9DC5; // FNV-1a 32-bit offset basis
    for (final byte in utf8.encode(input)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xFFFFFFFF; // FNV prime, 32-bit wrap
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) block) => block(this);
}
