import 'dart:convert';
import 'package:nexus/models/harvested_media.dart';

/// UniversalScraper: seitenunabhängiger Deep-Scraper.
/// Läuft als JS-Injection im WebView-Kontext und deckt ab:
///  - <video>/<source>/<audio>-Tags (auch verschachtelt in Shadow-DOM-fähigen Fällen, soweit zugreifbar)
///  - Inline-<script>-Inhalte: Regex auf m3u8/mpd/mp4/webm-URLs (deckt viele
///    Player-Konfigurationen ab, die ihre Quelle per JS-Objekt setzen)
///  - JSON-LD (schema.org VideoObject) — von vielen Streaming-/Mediatheken-Seiten genutzt
///  - <iframe>-Quellen werden gesammelt, damit der Aufrufer sie bei Bedarf
///    einzeln nachladen und erneut scannen kann (typisch für eingebettete Player)
///  - MediaSource/Blob-URLs werden erkannt und als Hinweis markiert (Blob-URLs
///    selbst sind nicht extern abrufbar, aber der Fund zeigt: hier läuft ein
///    Player, der über MSE streamt — meist zusätzlich zu einem Netzwerk-Manifest,
///    das der NetworkSniffer separat einfängt)
class UniversalScraper {
  static const String _injectedJs = r'''
(function() {
  try {
    var entries = [];
    var seen = {};
    function push(url, kind, via) {
      if (!url || seen[url]) return;
      seen[url] = true;
      entries.push({url: url, kind: kind, via: via});
    }

    // 1) <video>/<audio>/<source>
    document.querySelectorAll('video, audio, source').forEach(function(el) {
      var src = el.currentSrc || el.src || el.getAttribute('src');
      if (src && src.indexOf('http') === 0) push(src, 'direct', 'dom');
      if (el.tagName === 'VIDEO' || el.tagName === 'AUDIO') {
        if (src && src.indexOf('blob:') === 0) push(location.href, 'blob-hint', 'dom');
      }
    });

    // 2) Inline <script>-Inhalte nach Manifest-/Datei-URLs durchsuchen
    var urlRegex = /https?:\/\/[^\s"'()<>\\]+\.(m3u8|mpd|mp4|webm|m4a|mp3)(\?[^\s"'()<>\\]*)?/gi;
    document.querySelectorAll('script:not([src])').forEach(function(script) {
      var text = script.textContent || '';
      var m;
      while ((m = urlRegex.exec(text)) !== null) {
        var ext = m[1].toLowerCase();
        var kind = ext === 'm3u8' ? 'hls' : (ext === 'mpd' ? 'dash' : (ext === 'mp3' || ext === 'm4a' ? 'audio' : 'direct'));
        push(m[0], kind, 'script');
      }
    });

    // 3) JSON-LD (schema.org VideoObject / hasPart)
    document.querySelectorAll('script[type="application/ld+json"]').forEach(function(script) {
      try {
        var data = JSON.parse(script.textContent);
        var list = Array.isArray(data) ? data : [data];
        list.forEach(function(item) {
          collectFromJsonLd(item);
        });
      } catch (e) {}
    });
    function collectFromJsonLd(item) {
      if (!item || typeof item !== 'object') return;
      if (item.contentUrl) push(item.contentUrl, guessKind(item.contentUrl), 'jsonld');
      if (item.embedUrl) push(item.embedUrl, 'direct', 'jsonld');
      if (item.video) collectFromJsonLd(item.video);
      if (Array.isArray(item.hasPart)) item.hasPart.forEach(collectFromJsonLd);
    }
    function guessKind(u) {
      if (/\.m3u8/i.test(u)) return 'hls';
      if (/\.mpd/i.test(u)) return 'dash';
      if (/\.(mp3|m4a|aac|ogg)/i.test(u)) return 'audio';
      return 'direct';
    }

    // 4) Meta-Tags (og:video, twitter:player)
    document.querySelectorAll('meta[property="og:video"], meta[property="og:video:url"], meta[property="og:video:secure_url"], meta[name="twitter:player:stream"]').forEach(function(m) {
      var c = m.getAttribute('content');
      if (c && c.indexOf('http') === 0) push(c, guessKind(c), 'meta');
    });

    // 5) Iframes sammeln (werden separat nachgeladen, falls nötig)
    var iframes = [];
    document.querySelectorAll('iframe').forEach(function(f) {
      var src = f.src;
      if (src && src.indexOf('http') === 0) iframes.push(src);
    });

    return JSON.stringify({entries: entries, iframes: iframes});
  } catch (e) {
    return JSON.stringify({entries: [], iframes: [], error: String(e)});
  }
})();
''';

  static String get injectedJs => _injectedJs;

  /// Parst das Ergebnis der Injection zu HarvestedMedia-Objekten.
  static ScraperResult parseResult(String raw, {required String pageUrl, required String pageTitle}) {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['entries'] as List? ?? [])
          .map((e) {
            final kindStr = e['kind'] as String? ?? 'direct';
            if (kindStr == 'blob-hint') return null; // kein herunterladbarer Link, nur Hinweis
            return HarvestedMedia(
              url: e['url'] as String,
              kind: mediaKindFromString(kindStr),
              sourceUrl: pageUrl,
              sourceTitle: pageTitle,
              discoveredVia: e['via'] as String? ?? 'dom',
            );
          })
          .whereType<HarvestedMedia>()
          .toList();
      final iframes = (decoded['iframes'] as List? ?? []).cast<String>();
      final hasBlobHint = (decoded['entries'] as List? ?? [])
          .any((e) => e['kind'] == 'blob-hint');
      return ScraperResult(entries: entries, iframeUrls: iframes, hasBlobPlayer: hasBlobHint);
    } catch (_) {
      return ScraperResult(entries: const [], iframeUrls: const [], hasBlobPlayer: false);
    }
  }
}

class ScraperResult {
  final List<HarvestedMedia> entries;
  final List<String> iframeUrls;
  final bool hasBlobPlayer;

  ScraperResult({required this.entries, required this.iframeUrls, required this.hasBlobPlayer});
}
