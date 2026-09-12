// Dart (Flutter-Projekt), async/await, regex-basiertes HTML-Parsing
// (konsistent mit scraper_engine.dart und manifest_parser.dart)
//
// html_extractor: Tiefe HTML-Analyse
// Findet <video>/<source>/<audio>/<iframe>/<embed>/<object>-Tags,
// data-*-Attribute, <script type="application/ld+json"> und
// <script type="application/json"> Blobs (window.__INITIAL_STATE__,
// __NEXT_DATA__, window.__DATA__), OpenGraph/Twitter-Meta-Tags.
// Löst relative URLs via Uri.resolve() gegen die Basis-URL auf.

import 'dart:convert';
import 'dart:io';

/// Ergebnis eines HTML-Extraktions-Laufs.
class HtmlExtractResult {
  /// Alle gefundenen Media-Kandidaten (Videos, Audios, Dokumente, iframed).
  final List<MediaCandidate> candidates;

  /// Titel der Seite (<title>-Tag).
  final String? title;

  /// Meta-Description.
  final String? description;

  /// OpenGraph-Typ (og:type).
  final String? ogType;

  /// OpenGraph-Bild-URL (og:image).
  final String? ogImage;

  /// OpenGraph-Titel (og:title).
  final String? ogTitle;

  /// Twitter-Card-Typ (twitter:card).
  final String? twitterCard;

  HtmlExtractResult({
    required this.candidates,
    this.title,
    this.description,
    this.ogType,
    this.ogImage,
    this.ogTitle,
    this.twitterCard,
  });
}

/// Ein Kandidat für einen Media-Download, der vom Scraper gefunden wurde.
class MediaCandidate {
  /// Der (aufgelöste) URL-Pfad zum Media.
  final String url;

  /// Mime-Typ oder Dateiendung-basierter Typ (z.B. 'video/mp4', 'application/pdf').
  final String type;

  /// Wo der Kandidat gefunden wurde ('video', 'source', 'audio', 'iframe',
  /// 'embed', 'object', 'data-*', 'json-ld', 'json-blob', 'og', 'twitter',
  /// 'a', 'srcset').
  final String source;

  /// Dateigröße in Bytes (falls per HEAD-Request ermittelbar), sonst null.
  final int? bytes;

  /// Label/Titel (falls verfügbar, z.B. aus title-Attribut oder JSON).
  final String? label;

  MediaCandidate({
    required this.url,
    required this.type,
    required this.source,
    this.bytes,
    this.label,
  });
}

/// Regex-Muster für verschiedene HTML-Tags und Attribute.
/// WICHTIG: In Dart raw strings (r'...') ist \ ein Literal-Backslash.
/// Daher r'\b' = Backslash + b (für regex \b = Wortgrenze)
/// und r'\s' = Backslash + s (für regex \s = Whitespace).
/// Verwende r'''...''' (triple-quoted) wenn das Pattern ein ' enthält.
class _Patterns {
  // Regex für <video ...>...</video> mit src-Attribut
  static final RegExp videoSrc = RegExp(
    r'''<video\b[^>]*\bsrc\s*=\s*['"]([^'"]+)['"]''',
    multiLine: true,
    caseSensitive: false,
  );

  // Regex für <source ... src="..." type="...">
  static final RegExp sourceSrc = RegExp(
    r'''<source\b[^>]*\bsrc\s*=\s*['"]([^'"]+)['"](?:[^>]*\btype\s*=\s*['"]([^'"]+)['"])?''',
    multiLine: true,
    caseSensitive: false,
  );

  // Regex für <audio ... src="...">
  static final RegExp audioSrc = RegExp(
    r'''<audio\b[^>]*\bsrc\s*=\s*['"]([^'"]+)['"]''',
    multiLine: true,
    caseSensitive: false,
  );

  // Regex für <iframe ... src="...">
  static final RegExp iframeSrc = RegExp(
    r'''<iframe\b[^>]*\bsrc\s*=\s*['"]([^'"]+)['"]''',
    multiLine: true,
    caseSensitive: false,
  );

  // Regex für <embed ... src="...">
  static final RegExp embedSrc = RegExp(
    r'''<embed\b[^>]*\bsrc\s*=\s*['"]([^'"]+)['"]''',
    multiLine: true,
    caseSensitive: false,
  );

  // Regex für <object ... data="...">
  static final RegExp objectData = RegExp(
    r'''<object\b[^>]*\bdata\s*=\s*['"]([^'"]+)['"]''',
    multiLine: true,
    caseSensitive: false,
  );

  // Regex für <a href="...">
  static final RegExp linkHref = RegExp(
    r'''<a\b[^>]*\bhref\s*=\s*['"]([^'"]+)['"]''',
    multiLine: true,
    caseSensitive: false,
  );

  // Regex für data-*-Attribute (z.B. data-video-src, data-src, data-href)
  static final RegExp dataAttr = RegExp(
    r'''data-(?:[\w-]*?)(?:video|src|href|url|source|media)['"]?\s*=\s*['"]([^'"]+)['"]''',
    multiLine: true,
    caseSensitive: false,
  );

  // Regex für srcset-Attribute
  static final RegExp srcset = RegExp(
    r'''srcset\s*=\s*['"][^'"]*(?:,\s*[^'"]*)*['"]''',
    multiLine: true,
    caseSensitive: false,
  );

  // Regex für <title>...</title>
  static final RegExp title = RegExp(
    r'''<title[^>]*>\s*(.*?)\s*</title>''',
    multiLine: true,
    caseSensitive: false,
    dotAll: true,
  );

  // Regex für <meta name="description" content="...">
  static final RegExp metaDescription = RegExp(
    r'''<meta\b[^>]*\bname\s*=\s*['"]description['"][^>]*\bcontent\s*=\s*['"]([^'"]*)['"]''',
    caseSensitive: false,
  );

  // Regex für <meta property="og:*" content="...">
  static final RegExp ogMeta = RegExp(
    r'''<meta\b[^>]*\bproperty\s*=\s*['"](og:[\w:]+)['"][^>]*\bcontent\s*=\s*['"]([^'"]*)['"]''',
    caseSensitive: false,
  );

  // Regex für <meta name="twitter:*" content="...">
  static final RegExp twitterMeta = RegExp(
    r'''<meta\b[^>]*\bname\s*=\s*['"](twitter:[\w:]+)['"][^>]*\bcontent\s*=\s*['"]([^'"]*)['"]''',
    caseSensitive: false,
  );

  // Regex für <script type="application/ld+json">...</script>
  static final RegExp jsonLd = RegExp(
    r'''<script\b[^>]*\btype\s*=\s*['"]application/ld\+json['"][^>]*>(.*?)</script>''',
    multiLine: true,
    caseSensitive: false,
    dotAll: true,
  );

  // Regex für <script type="application/json">...</script>
  static final RegExp appJson = RegExp(
    r'''<script\b[^>]*\btype\s*=\s*['"]application/json['"][^>]*>(.*?)</script>''',
    multiLine: true,
    caseSensitive: false,
    dotAll: true,
  );

  // Regex für versteckte JSON-Blobs in Script-Tags:
  // window.__INITIAL_STATE__, __NEXT_DATA__, window.__DATA__
  static final RegExp jsonBlob = RegExp(
    r'''(?:window\.__INITIAL_STATE__|__NEXT_DATA__|window\.__DATA__)\s*=\s*(\{.*?\});''',
    multiLine: true,
    caseSensitive: false,
    dotAll: true,
  );

  // Dateiendungen für verschiedene Media-Typen
  static final Set<String> videoExts = {
    '.mp4', '.webm', '.mkv', '.mov', '.avi', '.wmv', '.flv', '.m4v',
    '.ts', '.m4s', '.mpg', '.mpeg',
  };
  static final Set<String> audioExts = {
    '.mp3', '.wav', '.ogg', '.m4a', '.flac', '.aac', '.wma',
  };
  static final Set<String> docExts = {
    '.pdf', '.epub', '.mobi', '.djvu', '.cbz', '.cb7', '.djv',
  };
  static final Set<String> hlsExts = {'.m3u8', '.m3u'};
  static final Set<String> dashExts = {'.mpd'};
}

/// Tiefe HTML-Analyse. Findet Media-URLs in Tags, Script-Blobs und Meta-Tags.
class HtmlExtractor {
  final HttpClient? _client;
  final List<String> _userAgents;
  final Duration _timeout;
  final int _maxDepth;
  int _depth = 0;

  HtmlExtractor({
    HttpClient? client,
    List<String>? userAgents,
    Duration? timeout,
    int maxDepth = 3,
  })  : _client = client,
        _userAgents = userAgents ?? _defaultUserAgents,
        _timeout = timeout ?? const Duration(seconds: 30),
        _maxDepth = maxDepth;

  static const List<String> _defaultUserAgents = [
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0',
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Mobile/15E148 Safari/604.1',
  ];

  /// Holt HTML per HTTP GET und parst alle Media-Kandidaten.
  /// Nutzt Content-Type-Header, um Non-HTML-Inhalte (JSON, XML) zu erkennen.
  Future<HtmlExtractResult> extract(String url, {Map<String, String>? extraHeaders}) async {
    final client = _client ?? HttpClient();
    final req = await client.getUrl(Uri.parse(url)).timeout(_timeout);
    req.headers.set(HttpHeaders.userAgentHeader, _userAgents[_depth % _userAgents.length]);
    req.headers.add('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
    extraHeaders?.forEach((k, v) => req.headers.add(k, v));

    final response = await req.close().timeout(_timeout);

    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'HTTP ${response.statusCode} for $url',
        uri: Uri.parse(url),
      );
    }

    // Content-Type analysieren
    final contentType = response.contentType?.mimeType ?? '';
    final body = await response.transform(utf8.decoder).join();
    final result = _parseByContentType(url, body, contentType);

    if (_client == null) {
      client.close();
    }

    return result;
  }

  /// Parsed Inhalt basierend auf Content-Type-Header.
  HtmlExtractResult _parseByContentType(String baseUrl, String body, String contentType) {
    final lower = contentType.toLowerCase();

    if (lower.contains('application/json') ||
        lower.contains('application/x-json') ||
        baseUrl.toLowerCase().endsWith('.json')) {
      return parseJson(baseUrl, body);
    }

    if (lower.contains('xml') ||
        lower.contains('application/rss') ||
        lower.contains('application/atom') ||
        baseUrl.toLowerCase().endsWith('.xml') ||
        baseUrl.toLowerCase().contains('sitemap') ||
        baseUrl.toLowerCase().contains('rss') ||
        baseUrl.toLowerCase().contains('feed')) {
      return parseXml(baseUrl, body);
    }

    // Fallback: HTML-Parsing
    return parseHtml(baseUrl, body);
  }

  /// Parsed JSON-APIs und JSON-Feeds für Media-URLs.
  HtmlExtractResult parseJson(String baseUrl, String jsonContent) {
    final candidates = <MediaCandidate>[];
    final baseUri = Uri.parse(baseUrl);

    try {
      final decoded = json.decode(jsonContent);
      // Rekursiv durch JSON-Struktur nach URLs suchen
      _scanJsonRecursive(decoded, baseUri, candidates, 'json-api');
    } catch (e) {
      // Nicht gültiges JSON — Regex-Fallback
      _extractUrlsFromString(jsonContent, baseUri, candidates, 'json-api');
    }

    // Deduplizieren
    final seen = <String>{};
    final unique = candidates.where((c) {
      if (seen.contains(c.url)) return false;
      seen.add(c.url);
      return true;
    }).toList();

    return HtmlExtractResult(candidates: unique);
  }

  /// Rekursive Suche in JSON nach URL-Strings mit Media-Endungen.
  void _scanJsonRecursive(dynamic obj, Uri baseUri, List<MediaCandidate> candidates, String source) {
    if (obj is String) {
      final lower = obj.toLowerCase();
      // Prüfe auf bekannte Media-Endungen in JSON-String-Werten
      if (_hasMediaExtension(lower) || obj.startsWith('http')) {
        _addCandidate(candidates, obj, baseUri, source);
      }
    } else if (obj is Map) {
      // Schlüsselwörter prüfen: url, src, file, href, stream, source
      for (final entry in obj.entries) {
        final key = entry.key.toString().toLowerCase();
        final value = entry.value;

        if (value is String) {
          if (key.contains('url') || key.contains('src') || key.contains('file') ||
              key.contains('href') || key.contains('stream') || key.contains('source') ||
              key.contains('link') || key.contains('media') ||
              value.toLowerCase().endsWith('.m3u8') ||
              value.toLowerCase().endsWith('.mpd') ||
              value.toLowerCase().endsWith('.mp4')) {
            _addCandidate(candidates, value, baseUri, source);
          }
        } else if (value is Map || value is List) {
          _scanJsonRecursive(value, baseUri, candidates, source);
        }
      }
    } else if (obj is List) {
      for (final v in obj) {
        _scanJsonRecursive(v, baseUri, candidates, source);
      }
    }
  }

  /// Prüft, ob eine URL eine bekannte Media-Endung hat.
  bool _hasMediaExtension(String url) {
    return url.endsWith('.mp4') || url.endsWith('.webm') || url.endsWith('.mkv') ||
           url.endsWith('.m3u8') || url.endsWith('.mpd') || url.endsWith('.mp3') ||
           url.endsWith('.wav') || url.endsWith('.pdf') || url.endsWith('.epub') ||
           url.endsWith('.mobi') || url.endsWith('.m4a') || url.endsWith('.ogg') ||
           url.contains('.m3u8') || url.contains('.mpd');
  }

  /// Parsed XML-Sitemaps und RSS/Atom-Feeds für Media-URLs.
  HtmlExtractResult parseXml(String baseUrl, String xmlContent) {
    final candidates = <MediaCandidate>[];
    final baseUri = Uri.parse(baseUrl);

    // loc-Tags in Sitemaps: <loc>https://example.com/video.mp4</loc>
    final locPattern = RegExp(
      r'''<loc\s*>([^<]+)<''',
      caseSensitive: false,
    );
    for (final match in locPattern.allMatches(xmlContent)) {
      _addCandidate(candidates, match.group(1)!, baseUri, 'sitemap');
    }

    // enclosure-Tags in RSS: <enclosure url="..." type="video/mp4" />
    final enclosurePattern = RegExp(
      r'''<enclosure\b[^>]*\burl\s*=\s*['"]([^'"]+)['"]''',
      caseSensitive: false,
    );
    for (final match in enclosurePattern.allMatches(xmlContent)) {
      _addCandidate(candidates, match.group(1)!, baseUri, 'rss-enclosure');
    }

    // content:encoded in RSS: <content:encoded>...<img src="...">...</content:encoded>
    final contentEncoded = RegExp(
      r'''<content:encoded>\s*(.*?)\s*</content:encoded>''',
      caseSensitive: false,
      dotAll: true,
    );
    for (final match in contentEncoded.allMatches(xmlContent)) {
      // Inhalt nach URLs durchsuchen
      _extractUrlsFromString(match.group(1)!, baseUri, candidates, 'rss-content');
    }

    // media:content in RSS/Atom: <media:content url="..."/>
    final mediaContentPattern = RegExp(
      r'''<media:content\b[^>]*\burl\s*=\s*['"]([^'"]+)['"]''',
      caseSensitive: false,
    );
    for (final match in mediaContentPattern.allMatches(xmlContent)) {
      _addCandidate(candidates, match.group(1)!, baseUri, 'rss-media');
    }

    // media:thumbnail: <media:thumbnail url="..."/>
    final mediaThumbnailPattern = RegExp(
      r'''<media:thumbnail\b[^>]*\burl\s*=\s*['"]([^'"]+)['"]''',
      caseSensitive: false,
    );
    for (final match in mediaThumbnailPattern.allMatches(xmlContent)) {
      _addCandidate(candidates, match.group(1)!, baseUri, 'rss-thumbnail');
    }

    // Link-Tags in XML: <link href="...">
    final linkPattern = RegExp(
      r'''<link\b[^>]*\bhref\s*=\s*['"]([^'"]+)['"]''',
      caseSensitive: false,
    );
    for (final match in linkPattern.allMatches(xmlContent)) {
      _addCandidate(candidates, match.group(1)!, baseUri, 'xml-link');
    }

    // Deduplizieren
    final seen = <String>{};
    final unique = candidates.where((c) {
      if (seen.contains(c.url)) return false;
      seen.add(c.url);
      return true;
    }).toList();

    return HtmlExtractResult(candidates: unique);
  }

  /// Parst einen HTML-String direkt (ohne HTTP-Request).
  HtmlExtractResult parseHtml(String baseUrl, String html) {
    final candidates = <MediaCandidate>[];
    final baseUri = Uri.parse(baseUrl);

    // --- 1. Standard-HTML-Tags ---
    for (final match in _Patterns.videoSrc.allMatches(html)) {
      _addCandidate(candidates, match.group(1)!, baseUri, 'video');
    }
    for (final match in _Patterns.sourceSrc.allMatches(html)) {
      _addCandidate(candidates, match.group(1)!, baseUri, 'source');
    }
    for (final match in _Patterns.audioSrc.allMatches(html)) {
      _addCandidate(candidates, match.group(1)!, baseUri, 'audio');
    }
    for (final match in _Patterns.iframeSrc.allMatches(html)) {
      _addCandidate(candidates, match.group(1)!, baseUri, 'iframe');
    }
    for (final match in _Patterns.embedSrc.allMatches(html)) {
      _addCandidate(candidates, match.group(1)!, baseUri, 'embed');
    }
    for (final match in _Patterns.objectData.allMatches(html)) {
      _addCandidate(candidates, match.group(1)!, baseUri, 'object');
    }

    // --- 2. data-* Attribute ---
    for (final match in _Patterns.dataAttr.allMatches(html)) {
      _addCandidate(candidates, match.group(1)!, baseUri, 'data-*');
    }

    // --- 3. <a href> Links (für Rekursion) ---
    for (final match in _Patterns.linkHref.allMatches(html)) {
      _addCandidate(candidates, match.group(1)!, baseUri, 'a');
    }

    // --- 4. srcset ---
    for (final match in _Patterns.srcset.allMatches(html)) {
      final raw = match.group(0)!;
      _parseSrcset(raw, baseUri, candidates);
    }

    // --- 5. JSON-LD (<script type="application/ld+json">) ---
    for (final match in _Patterns.jsonLd.allMatches(html)) {
      _extractUrlsFromJson(match.group(1)!, baseUri, candidates, 'json-ld');
    }

    // --- 6. Application JSON (<script type="application/json">) ---
    for (final match in _Patterns.appJson.allMatches(html)) {
      _extractUrlsFromJson(match.group(1)!, baseUri, candidates, 'json-blob');
    }

    // --- 7. Inline JavaScript JSON-Blobs ---
    for (final match in _Patterns.jsonBlob.allMatches(html)) {
      _extractUrlsFromJson(match.group(1)!, baseUri, candidates, 'json-blob');
    }

    // --- 8. Versteckte URLs in <script>-Blöcken (raw JS-Strings) ---
    _extractUrlsFromScript(html, baseUri, candidates);

    // --- Meta-Tags ---
    final titleMatch = _Patterns.title.firstMatch(html);
    final descMatch = _Patterns.metaDescription.firstMatch(html);
    final ogMatches = _Patterns.ogMeta.allMatches(html);
    final twMatches = _Patterns.twitterMeta.allMatches(html);

    String? ogImage, ogTitle, ogType, twCard;
    final ogMap = <String, String>{};
    for (final m in ogMatches) {
      ogMap[m.group(1)!] = m.group(2)!;
    }
    ogImage = ogMap['og:image'];
    ogTitle = ogMap['og:title'];
    ogType = ogMap['og:type'];

    for (final m in twMatches) {
      if (m.group(1) == 'twitter:card') twCard = m.group(2);
    }

    // Dedupliziere Kandidaten
    final seen = <String>{};
    final unique = candidates.where((c) {
      if (seen.contains(c.url)) return false;
      seen.add(c.url);
      return true;
    }).toList();

    return HtmlExtractResult(
      candidates: unique,
      title: titleMatch?.group(1)?.trim(),
      description: descMatch?.group(1),
      ogType: ogType,
      ogImage: ogImage,
      ogTitle: ogTitle,
      twitterCard: twCard,
    );
  }

  /// Fügt einen Media-Kandidaten hinzu, nachdem die URL aufgelöst wurde.
  void _addCandidate(
    List<MediaCandidate> candidates,
    String rawUrl,
    Uri baseUri,
    String source,
  ) {
    final trimmed = rawUrl.trim();
    final resolved = baseUri.resolve(trimmed).toString();

    // Filter: data:, javascript:, mailto:, #-Anchors
    if (trimmed.startsWith('data:') ||
        trimmed.startsWith('javascript:') ||
        trimmed.startsWith('mailto:') ||
        trimmed.startsWith('#') ||
        trimmed.isEmpty) {
      return;
    }

    final ext = _getExtension(resolved).toLowerCase();
    final type = _inferType(resolved, ext);
    if (type == 'unknown') return; // Nur Media-Dateien und Links

    candidates.add(MediaCandidate(
      url: resolved,
      type: type,
      source: source,
    ));
  }

  /// Parst srcset-Attribute: "url1 1x, url2 2x, ..."
  void _parseSrcset(String srcsetStr, Uri baseUri, List<MediaCandidate> candidates) {
    final parts = srcsetStr.split(',');
    for (final part in parts) {
      final urlMatch = RegExp(r'\s*([^,\s]+)').firstMatch(part);
      if (urlMatch != null) {
        _addCandidate(candidates, urlMatch.group(1)!, baseUri, 'srcset');
      }
    }
  }

  /// Extrahiert alle URLs aus einem JSON-String.
  void _extractUrlsFromJson(
    String jsonStr,
    Uri baseUri,
    List<MediaCandidate> candidates,
    String source,
  ) {
    // JSON parsen und rekursiv nach URL-Strings mit Media-Endungen suchen
    try {
      final decoded = json.decode(jsonStr);
      _scanJsonRecursive(decoded, baseUri, candidates, source);
    } catch (e) {
      // Nicht gültiges JSON — fallback: Regex nach URL-Mustern im String
      _extractUrlsFromString(jsonStr, baseUri, candidates, source);
    }
  }

  /// Fallback-Regex-Suche nach URLs in rohen Strings.
  void _extractUrlsFromString(
    String text,
    Uri baseUri,
    List<MediaCandidate> candidates,
    String source,
  ) {
    final urlPattern = RegExp(
      r'https?://[^\s<>"\]+',
      caseSensitive: false,
    );
    for (final match in urlPattern.allMatches(text)) {
      _addCandidate(candidates, match.group(0)!, baseUri, source);
    }
    // Auch //protokolllose URLs
    final protoPattern = RegExp(r'//(?!/)[^\s<>"\]+');
    for (final match in protoPattern.allMatches(text)) {
      _addCandidate(candidates, 'https:${match.group(0)}', baseUri, source);
    }
  }

  /// Extrahiert URLs aus <script>-Tags (raw JS-Code-Strings).
  void _extractUrlsFromScript(
    String html,
    Uri baseUri,
    List<MediaCandidate> candidates,
  ) {
    // <script type="text/javascript">...</script> und <script>...</script>
    final scriptPattern = RegExp(
      r'''<script\b[^>]*>(.*?)</script>''',
      multiLine: true,
      caseSensitive: false,
      dotAll: true,
    );

    for (final match in scriptPattern.allMatches(html)) {
      final jsCode = match.group(1)!;
      _extractUrlsFromString(jsCode, baseUri, candidates, 'script');
    }
  }

  /// Ermittelt die Dateiendung einer URL.
  String _getExtension(String url) {
    final uri = Uri.parse(url);
    final path = uri.path;
    final dotIndex = path.lastIndexOf('.');
    if (dotIndex >= 0 && dotIndex < path.length - 1) {
      return path.substring(dotIndex);
    }
    return '';
  }

  /// Inferiert den Mime/Typ einer URL basierend auf Extension und Query-Parametern.
  String _inferType(String url, String ext) {
    if (ext.isEmpty) {
      // Prüfe auf m3u8/mpd in der URL selbst
      final lower = url.toLowerCase();
      if (lower.contains('.m3u8') || lower.contains('/playlist.m3u') || lower.contains('m3u8')) {
        return 'application/vnd.apple.mpegurl';
      }
      if (lower.contains('.mpd')) {
        return 'application/dash+xml';
      }
      // Query-Parameter wie ?type=mp4
      if (lower.contains('type=video') || lower.contains('mime=video')) {
        return 'video/unknown';
      }
      return 'unknown';
    }

    if (_Patterns.videoExts.contains(ext)) return 'video/${ext.substring(1)}';
    if (_Patterns.audioExts.contains(ext)) return 'audio/${ext.substring(1)}';
    if (_Patterns.docExts.contains(ext)) {
      switch (ext) {
        case '.pdf': return 'application/pdf';
        case '.epub': return 'application/epub+zip';
        case '.mobi': return 'application/x-mobipocket-ebook';
        case '.djvu': return 'image/vnd.djvu';
        case '.cbz': return 'application/zip';
        case '.cb7': return 'application/x-cbr';
        case '.djv': return 'image/vnd.djvu';
        default: return 'application/octet-stream';
      }
    }
    if (_Patterns.hlsExts.contains(ext)) return 'application/vnd.apple.mpegurl';
    if (_Patterns.dashExts.contains(ext)) return 'application/dash+xml';

    // Andere Links (für Rekursion)
    return 'link';
  }
}