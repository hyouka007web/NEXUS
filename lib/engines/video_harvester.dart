// Dart (Flutter-Projekt), async/await, dart:io
// (konsistent mit video_harvester_engine.dart und manifest_parser.dart)
//
// video_harvester: Rekursive Video-URL-Suche
//
// Erweitert VideoHarvesterEngine um:
// - Rekursive iFrame-Durchstöße (wie im Blatzar-Scraping-Tutorial)
// - yt-dlp Fallback via Process.run
// - Deep-HTML-Analyse über HtmlExtractor
// - HLS/DASH-Manifest-Parsing über ManifestParser
//
// Vorgehen (analog zu Scrapling/Blatzar-Tutorial):
//   1. Finde <iframe>-Tags mit src-Attribut
//   2. Falls iFrame src gefunden → hole HTML des iFrames separat
//   3. In iFrame-HTML nach Video-Links suchen (.mp4, .m3u8, .mpd)
//   4. Arbeite rückwärts vom Video-Link zum Ursprung
//   5. Wenn keine direkten Links → yt-dlp Fallback

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import '../models/harvested_video.dart';
import 'html_extractor.dart';
import 'manifest_parser.dart';
import 'network_sniffer.dart';
import 'video_harvester_engine.dart';

/// Ergebnis eines Video-Harvesting-Durchlaufs.
class HarvestResult {
  final List<HarvestedVideo> videos;
  final List<MediaCandidate> docCandidates;
  final List<String> iframeUrls;
  final List<String> processedUrls;
  final List<String> errors;
  final bool ytDlpFallbackUsed;

  HarvestResult({
    required this.videos,
    required this.docCandidates,
    required this.iframeUrls,
    required this.processedUrls,
    required this.errors,
    this.ytDlpFallbackUsed = false,
  });
}

/// Konfiguration für VideoHarvester.
class HarvestConfig {
  final int maxDepth;
  final int maxPages;
  final int maxResults;
  final Duration timeout;
  final List<String> userAgents;
  final bool useYtDlp;
  final bool followIframes;
  final String? ytDlpPath;
  final List<String> targetDomains;
  final Map<String, String>? extraHeaders;
  final void Function(String)? onLog;
  final void Function(double)? onProgress;

  HarvestConfig({
    this.maxDepth = 3,
    this.maxPages = 60,
    this.maxResults = 100,
    this.timeout = const Duration(seconds: 30),
    this.userAgents = const [
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0',
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Mobile/15E148 Safari/604.1',
    ],
    this.useYtDlp = true,
    this.followIframes = true,
    this.ytDlpPath,
    this.targetDomains = const [],
    this.extraHeaders,
    this.onLog,
    this.onProgress,
  });
}

/// Rekursive Video-Harvester-Engine.
/// Findet Video-URLs in HTML, iFrames, JSON-Blobs und HLS/DASH-Manifesten.
class VideoHarvester {
  final HarvestConfig config;
  final HtmlExtractor _htmlExtractor;
  final HttpClient _httpClient;
  final Set<String> _visited = {};
  final List<String> _errors = [];
  final List<String> _iframeUrls = [];
  int _processedCount = 0;
  bool _ytDlpUsed = false;

  VideoHarvester({
    HarvestConfig? config,
    HtmlExtractor? htmlExtractor,
    HttpClient? httpClient,
  })  : config = config ?? HarvestConfig(),
        _htmlExtractor = htmlExtractor ?? HtmlExtractor(
          userAgents: config?.userAgents,
          timeout: config?.timeout,
        ),
        _httpClient = httpClient ?? HttpClient() {
    _httpClient.autoUncompress = true;
    _httpClient.connectionTimeout = config.timeout;
  }

  /// Haupt-Einstieg: Video-URLs von einer URL sammeln.
  Future<HarvestResult> harvest(String url) async {
    _log('Starte Video-Harvest für: $url');

    // 1. Bestehende VideoHarvesterEngine verwenden (bewährt)
    final engineResults = await VideoHarvesterEngine.harvest(url, deepInspect: true);

    final allVideos = <HarvestedVideo>{};
    final docCandidates = <MediaCandidate>[];
    final processedUrls = <String>[url];

    // Engine-Ergebnisse sammeln
    for (final v in engineResults) {
      allVideos.putIfAbsent(v.url, () => v);
    }

    if (allVideos.isNotEmpty) {
      _log('VideoHarvesterEngine fand ${allVideos.length} Kandidaten');
    }

    // 2. HTML-Extraktion für Deep-Analyse (iFrames, JSON-Blobs, data-Attrs)
    final html = await _fetchHtml(url);
    if (html != null) {
      final extractResult = _htmlExtractor.parseHtml(url, html);

      // iFrames rekursiv verfolgen
      if (config.followIframes) {
        for (final candidate in extractResult.candidates) {
          if (candidate.source == 'iframe') {
            _iframeUrls.add(candidate.url);
            _log('iFrame gefunden: ${candidate.url}');
          }
        }

        await _processIframes(extractResult.candidates, allVideos, docCandidates);
      }

      // Dokument-Kandidaten sammeln
      for (final c in extractResult.candidates) {
        if (_isDocumentType(c.type)) {
          docCandidates.add(c);
        }
      }
    }

    // 3. HLS/DASH-Manifeste parsen
    for (final video in List.of(allVideos)) {
      if (video.type == 'M3U8' || video.type == 'DASH') {
        _log('Parse Manifest: ${video.url}');
        final enriched = await VideoHarvesterEngine.enrichManifest(video);
        if (enriched.variants.isNotEmpty) {
          allVideos.remove(video);
          allVideos.putIfAbsent(enriched.url, () => enriched);
          _log('Manifest: ${enriched.variants.length} Varianten gefunden');
        }
      }
    }

    // 4. yt-dlp Fallback wenn keine Videos gefunden
    if (allVideos.isEmpty && config.useYtDlp) {
      _log('Keine Videos gefunden — versuche yt-dlp Fallback');
      final ytDlpResults = await _tryYtDlp(url);
      if (ytDlpResults.isNotEmpty) {
        _ytDlpUsed = true;
        for (final v in ytDlpResults) {
          allVideos.putIfAbsent(v.url, () => v);
        }
        _log('yt-dlp fand ${ytDlpResults.length} Videos');
      }
    }

    _processedCount = processedUrls.length;

    _log('Fertig. ${allVideos.length} Videos, ${docCandidates.length} Dokumente, '
        '${_iframeUrls.length} iFrames');

    return HarvestResult(
      videos: allVideos.toList(),
      docCandidates: docCandidates,
      iframeUrls: _iframeUrls,
      processedUrls: processedUrls,
      errors: _errors,
      ytDlpFallbackUsed: _ytDlpUsed,
    );
  }

  /// Holt HTML einer URL mit User-Agent-Rotation.
  Future<String?> _fetchHtml(String url) async {
    try {
      final ua = config.userAgents[_processedCount % config.userAgents.length];
      final request = await _httpClient.getUrl(Uri.parse(url));
      request.headers.userAgent = ua;
      request.headers.set('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
      request.headers.set('Accept-Language', 'de-DE,de;q=0.9,en-US;q=0.8,en;q=0.7');
      config.extraHeaders?.forEach((k, v) => request.headers.set(k, v));

      final response = await request.close().timeout(config.timeout);
      if (response.statusCode != HttpStatus.ok) {
        _errors.add('HTTP ${response.statusCode} für $url');
        return null;
      }

      return await response.transform(utf8.decoder).join();
    } catch (e) {
      _errors.add('Fetch-Fehler ($url): $e');
      return null;
    }
  }

  /// Verarbeitet iFrames rekursiv (analog Blatzar-Tutorial Schritt 1+2).
  Future<void> _processIframes(
    List<MediaCandidate> candidates,
    Set<HarvestedVideo> allVideos,
    List<MediaCandidate> docCandidates,
  ) async {
    for (final candidate in candidates) {
      if (candidate.source != 'iframe') continue;

      final normalized = _normalizeUrl(candidate.url);
      if (normalized == null || !_visited.add(normalized)) continue;

      _log('Verarbeite iFrame: ${candidate.url}');

      final iframeHtml = await _fetchHtml(candidate.url);
      if (iframeHtml == null) continue;

      // Deep-Analyse des iFrame-Inhalts
      final iframeResult = _htmlExtractor.parseHtml(candidate.url, iframeHtml);

      // Video-Kandidaten aus iFrame
      final iframeVideos = VideoHarvesterEngine.classifyCaptures(
        iframeResult.candidates
            .map((c) => MediaCapture(
          url: c.url,
          pageUrl: candidate.url,
        ))
            .toList(),
        iframeResult.title ?? '',
      );

      for (final v in iframeVideos) {
        if (allVideos.putIfAbsent(v.url, () => v) == v) {
          _log('Video aus iFrame gefunden: ${v.url} (${v.type})');
        }
      }

      // Dokumente aus iFrame
      for (final c in iframeResult.candidates) {
        if (_isDocumentType(c.type)) {
          docCandidates.add(c);
        }
      }

      // Rekursiv weitere iFrames im iFrame
      _depth++;
      if (_depth <= config.maxDepth) {
        await _processIframes(
          iframeResult.candidates.where((c) => c.source == 'iframe').toList(),
          allVideos,
          docCandidates,
        );
      }
      _depth--;
    }
  }

  /// Versucht yt-dlp als Fallback.
  Future<List<HarvestedVideo>> _tryYtDlp(String url) async {
    final ytDlp = config.ytDlpPath ?? 'yt-dlp';
    try {
      _log('Rufe yt-dlp auf: $ytDlp -f best --get-url "$url"');
      final result = await Process.run(
        ytDlp,
        ['-f', 'best', '--get-url', url],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(config.timeout * 2);

      if (result.exitCode == 0) {
        final lines = (result.stdout as String).trim().split('\n');
        final videos = <HarvestedVideo>[];
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty && trimmed.startsWith('http')) {
            final type = _classifyVideoType(trimmed);
            videos.add(HarvestedVideo(
              title: 'yt-dlp: $url',
              url: trimmed,
              host: Uri.parse(trimmed).host,
              type: type,
              status: 'MEDIA SOURCE (yt-dlp fallback)',
              source: 'yt-dlp',
              pageUrl: url,
            ));
          }
        }
        return videos;
      } else {
        _errors.add('yt-dlp fehlgeschlagen: ${result.stderr}');
        _log('yt-dlp fehlgeschlagen: ${result.stderr}');
      }
    } catch (e) {
      _errors.add('yt-dlp nicht verfügbar: $e');
      _log('yt-dlp nicht verfügbar: $e');
    }
    return [];
  }

  /// Klassifiziert eine Video-URL nach Dateiendung.
  String _classifyVideoType(String url) {
    final lower = url.toLowerCase();
    if (lower.endsWith('.mp4')) return 'MP4';
    if (lower.endsWith('.m3u8')) return 'M3U8';
    if (lower.endsWith('.mpd')) return 'DASH';
    if (lower.endsWith('.webm')) return 'WEBM';
    if (lower.endsWith('.mkv')) return 'MEDIA';
    if (lower.endsWith('.flv')) return 'MEDIA';
    return 'MEDIA';
  }

  /// Prüft, ob ein Mime-Typ auf ein Dokument verweist.
  bool _isDocumentType(String type) {
    return type == 'application/pdf' ||
        type == 'application/epub+zip' ||
        type == 'application/x-mobipocket-ebook' ||
        type == 'image/vnd.djvu';
  }

  /// Normalisiert eine URL für Deduplizierung.
  String? _normalizeUrl(String url) {
    try {
      final u = Uri.parse(url);
      final scheme = u.scheme.toLowerCase();
      if ((scheme != 'http' && scheme != 'https') || u.host.isEmpty) {
        return null;
      }
      return u.toString();
    } catch (e) {
      return null;
    }
  }

  /// Hilfsfunktion für Logging.
  void _log(String message) {
    // Nutzt den bestehenden HarvestLogger, falls konfiguriert.
    config.onLog?.call(message);
  }

  /// Aktueller Tiefe-Tracker (für Rekursion).
  int _depth = 0;
}
