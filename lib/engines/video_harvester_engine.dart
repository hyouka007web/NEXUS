import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import '../models/harvested_video.dart';
import 'manifest_parser.dart';
import 'network_sniffer.dart';

/// Discovers publicly exposed video/player URLs. No DRM/login/CAPTCHA/access-
/// control bypass. 1:1-Verhalten zu Kotlins `VideoHarvesterEngine`.
class VideoHarvesterEngine {
  VideoHarvesterEngine._();

  static const int _maxHtmlBytes = 5 * 1024 * 1024;
  static const int _maxLinkedPages = 60;
  static const int _maxResults = 1000;
  static const String _userAgent = 'Mozilla/5.0 (Linux; NEXUS Browser/1.0)';

  static final RegExp _attrPattern = RegExp(
    r'''(?:href|src|data-src|data-url|data-video|data-file|content)\s*=\s*['"]([^'"]+)['"]''',
    caseSensitive: false,
  );
  // Viele Player betten ihre Quelle als JSON-Konfiguration in einem
  // <script>-Block ein statt als HTML-Attribut, z.B. `"file": "…mp4"` oder
  // `"hls": "…m3u8"` in einem JWPlayer-/Video.js-Setup-Aufruf. Das obige
  // Attribut-Muster sieht so etwas nicht, weil es HTML-Attribut-Syntax
  // erwartet, keine JSON-Syntax.
  static final RegExp _jsonKeyPattern = RegExp(
    r'''"(?:file|src|source|url|hls|dash|contentUrl|videoUrl|streamUrl)"\s*:\s*"([^"]+)"''',
    caseSensitive: false,
  );
  static final RegExp _urlPattern = RegExp(
    r'''https?://[^\s"'<>\\]+''',
    caseSensitive: false,
  );
  static final RegExp _escapedUrlPattern = RegExp(
    r'''https?:\\?/\\?/[^\s"'<>]+''',
    caseSensitive: false,
  );
  static final RegExp _titlePattern = RegExp(
    r'<title[^>]*>(.*?)</title>',
    caseSensitive: false,
    dotAll: true,
  );

  static Future<List<HarvestedVideo>> harvest(
    String pageUrl, {
    bool deepInspect = true,
  }) async {
    final queue = Queue<_QueueItem>()..add(_QueueItem(pageUrl, 'Page'));
    final visited = <String>{};
    final result = <String, HarvestedVideo>{};

    while (queue.isNotEmpty &&
        visited.length < _maxLinkedPages &&
        result.length < _maxResults) {
      final item = queue.removeFirst();
      final normalizedPage = _normalize(item.url);
      if (normalizedPage == null || !visited.add(normalizedPage)) continue;

      final html = await _fetchHtml(normalizedPage);
      if (html == null) continue;

      final pageTitle = _extractTitle(html).isNotEmpty
          ? _extractTitle(html)
          : item.inheritedTitle;

      for (final found in _classifyHtml(html, normalizedPage, pageTitle)) {
        result.putIfAbsent(found.url, () => found);
        if (deepInspect &&
            found.type == 'PLAYER' &&
            queue.length + visited.length < _maxLinkedPages) {
          queue.add(_QueueItem(found.url, pageTitle));
        }
      }
    }
    return result.values.toList();
  }

  /// Wertet bereits vorliegendes HTML aus, statt es selbst per HTTP zu
  /// holen — keine Rekursion in verlinkte Seiten. Der entscheidende
  /// Anwendungsfall: [html] kann das **nach JavaScript-Ausführung
  /// gerenderte** DOM einer echten WebView sein (`document.documentElement.
  /// outerHTML`), nicht nur die rohe Server-Antwort. Viele Streaming-Seiten
  /// bauen ihren `<video>`/Player-Quelltext erst per JS zusammen, nachdem
  /// die Seite geladen ist — ein reiner HTTP-Fetch (wie [harvest] ihn für
  /// verlinkte Seiten macht) sieht diese URLs nie, weil sie in der
  /// Server-Antwort schlicht noch nicht existieren. Das war bei genauerer
  /// Betrachtung vermutlich die eigentliche Ursache dafür, dass zuletzt kaum
  /// echte Videodateien gefunden wurden, nicht nur ein zu schwacher
  /// Downloader.
  static List<HarvestedVideo> extractFromRenderedHtml(
    String html,
    String baseUrl, {
    String titleHint = '',
  }) {
    final title =
        _extractTitle(html).isNotEmpty ? _extractTitle(html) : titleHint;
    return _classifyHtml(html, baseUrl, title);
  }

  static List<HarvestedVideo> classifyUrls(
    List<String> urls,
    String pageTitle, {
    String pageUrl = '',
    String referrer = '',
    String userAgent = '',
  }) {
    return classifyCaptures(urls.map((url) => MediaCapture(
          url: url, pageUrl: pageUrl, referrer: referrer, userAgent: userAgent,
        )).toList(), pageTitle);
  }

  static List<HarvestedVideo> classifyCaptures(
    List<MediaCapture> captures,
    String pageTitle,
  ) {
    final out = <HarvestedVideo>[];
    final seen = <String>{};
    for (final capture in captures) {
      final raw = capture.url;
      if (!seen.add(raw)) continue;
      final normalized = _normalize(raw);
      if (normalized == null) continue;
      final type = _classify(normalized);
      if (type == 'LINK' || type == 'PLAYER') continue;
      String host;
      try {
        host = Uri.parse(normalized).host;
      } catch (_) {
        host = '';
      }
      out.add(HarvestedVideo(
        title: pageTitle,
        url: normalized,
        host: host,
        type: type,
        status: type == 'BLOB'
            ? 'MEDIA SOURCE · ${capture.source} (blob: — nicht direkt herunterladbar)'
            : 'MEDIA SOURCE · ${capture.source}',
        source: capture.source,
        pageUrl: capture.pageUrl,
        referrer: capture.referrer,
        userAgent: capture.userAgent,
        headers: capture.headers,
        cookies: capture.cookies,
      ));
    }
    return out;
  }

  static List<HarvestedVideo> _classifyHtml(
    String html,
    String baseUrl,
    String pageTitle,
  ) {
    final out = <HarvestedVideo>[];
    for (final candidate in _extractCandidates(html, baseUrl)) {
      final normalized = _normalize(candidate);
      if (normalized == null) continue;
      final type = _classify(normalized);
      if (type == 'LINK') continue;
      String host;
      try {
        host = Uri.parse(normalized).host;
      } catch (_) {
        host = '';
      }
      final status = type == 'BLOB'
          ? 'MEDIA SOURCE (blob: — nicht direkt herunterladbar)'
          : {'MP4', 'WEBM', 'M3U8', 'MEDIA', 'DASH'}.contains(type)
              ? 'MEDIA SOURCE'
              : 'PLAYER / VIDEO PAGE';
      out.add(HarvestedVideo(
        title: pageTitle,
        url: normalized,
        host: host,
        type: type,
        status: status,
        source: 'DOM',
        pageUrl: baseUrl,
      ));
    }
    return out;
  }

  /// Parses public HLS/DASH manifests and attaches quality variants.
  static Future<HarvestedVideo> enrichManifest(HarvestedVideo video) async {
    if (video.type != 'M3U8' && video.type != 'DASH') return video;
    final variants = await ManifestParser.inspect(video.url, headers: {
      ...video.headers,
      if (video.referrer.isNotEmpty) 'Referer': video.referrer,
      if (video.userAgent.isNotEmpty) 'User-Agent': video.userAgent,
      if (video.cookies.isNotEmpty) 'Cookie': video.cookies,
    });
    if (variants.isEmpty) return video;
    final best = variants.reduce((a, b) => a.bandwidth >= b.bandwidth ? a : b);
    return video.copyWith(
      variants: variants,
      quality: best.quality,
      status: '${video.status} · ${variants.length} Qualitätsstufen',
    );
  }

  static Future<String?> fetchHtmlForDebug(String url) => _fetchHtml(url);

  static Future<String?> _fetchHtml(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..autoUncompress = true;
    try {
      final request = await client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 12));
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'text/html,application/xhtml+xml,application/json,text/plain,*/*;q=0.8',
      );
      final response =
          await request.close().timeout(const Duration(seconds: 20));
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length >= _maxHtmlBytes) break;
      }
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static List<String> _extractCandidates(String html, String baseUrl) {
    final out = <String>{};
    void add(String? raw) {
      if (raw == null || raw.trim().isEmpty) return;
      final value = _decode(raw.trim());
      if (value.startsWith('data:') ||
          value.startsWith('javascript:') ||
          value.startsWith('mailto:')) {
        return;
      }
      try {
        out.add(Uri.parse(baseUrl).resolve(value).toString());
      } catch (_) {
        // ignorieren, wie im Kotlin-Original (runCatching { }.getOrNull())
      }
    }

    for (final m in _attrPattern.allMatches(html)) {
      add(m.group(1));
    }
    for (final m in _jsonKeyPattern.allMatches(html)) {
      add(m.group(1)?.replaceAll(r'\/', '/'));
    }
    for (final m in _urlPattern.allMatches(html)) {
      add(m.group(0));
    }
    for (final m in _escapedUrlPattern.allMatches(html)) {
      add(m.group(0)?.replaceAll(r'\/', '/'));
    }
    return out.toList();
  }

  static String? _normalize(String url) {
    try {
      final u = Uri.parse(url);
      final scheme = u.scheme.toLowerCase();
      if (scheme == 'blob') {
        // blob:https://origin/uuid — kein normaler Host-Teil, aber ein
        // starkes, eigenständiges Signal (siehe _classify: wird als
        // eigener, ausdrücklich NICHT herunterladbarer Typ markiert statt
        // stillschweigend verworfen zu werden).
        return url;
      }
      if ((scheme != 'http' && scheme != 'https') || u.host.isEmpty) {
        return null;
      }
      return u.toString();
    } catch (_) {
      return null;
    }
  }

  static String _classify(String url) {
    if (url.toLowerCase().startsWith('blob:')) return 'BLOB';
    String path;
    try {
      path = Uri.parse(url).path.toLowerCase();
    } catch (_) {
      path = '';
    }
    const directExtensions = {
      '.mp4', '.m4v', '.mov', '.webm', '.mkv', '.flv', '.3gp', '.ogv', //
    };
    if (path.endsWith('.mp4') || path.endsWith('.m4v') || path.endsWith('.mov')) {
      return 'MP4';
    }
    if (path.endsWith('.webm')) return 'WEBM';
    if (directExtensions.any(path.endsWith)) return 'MEDIA';
    if (path.endsWith('.m3u8')) return 'M3U8';
    if (path.endsWith('.mpd')) return 'DASH';
    if (path.endsWith('.ts')) return 'MEDIA';
    if (_isLikelyVideoPage(url)) return 'PLAYER';
    return 'LINK';
  }

  static bool _isLikelyVideoPage(String url) {
    final s = url.toLowerCase();
    const markers = [
      '/video', '/watch', '/embed', '/player', '/stream', '/trailer',
      '/episode', '/play', 'videoplayer', //
    ];
    return markers.any(s.contains);
  }

  static String _extractTitle(String html) {
    final match = _titlePattern.firstMatch(html);
    if (match == null) return '';
    final decoded = _decode(match.group(1) ?? '')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return decoded.length > 160 ? decoded.substring(0, 160) : decoded;
  }

  static String _decode(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(r'\/', '/');
}

class _QueueItem {
  final String url;
  final String inheritedTitle;
  const _QueueItem(this.url, this.inheritedTitle);
}
