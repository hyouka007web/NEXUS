import 'dart:convert';
import 'dart:io';
import 'package:nexus/models/harvested_media.dart';
import 'package:nexus/services/hls_dash_parser.dart';

/// DeepHarvester bündelt alles, was für "echtes" Deep-Scraping nötig ist:
///  - Iframes serverseitig nachladen und per Regex/JSON-LD erneut scannen
///    (viele Embeds liefern ihre Quelle nicht per DOM, sondern erst im
///    HTML des Iframe-Dokuments selbst)
///  - HLS/DASH-Manifeste auflösen zu konkreten Qualitätsstufen, sobald
///    ein Manifest-Link gefunden wurde (Scraper oder Netzwerk-Sniffer)
class DeepHarvester {
  static final RegExp _urlRegex = RegExp(
    'https?://[^\\s"\']+\\.(m3u8|mpd|mp4|webm|m4a|mp3)(\\?[^\\s"\']*)?',
    caseSensitive: false,
  );

  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 13; SM-S901B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  /// Lädt ein Iframe-Dokument serverseitig und sucht nach Medien-URLs.
  /// Wird aufgerufen, wenn der UniversalScraper im Haupt-DOM Iframes
  /// gefunden, aber keine direkten Medien-URLs entdeckt hat.
  static Future<List<HarvestedMedia>> scanIframe(
    String iframeUrl, {
    required String pageTitle,
  }) async {
    try {
      final client = HttpClient()..userAgent = _userAgent;
      final request = await client.getUrl(Uri.parse(iframeUrl));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) return [];
      final html = await response.transform(utf8.decoder).join();

      final found = <HarvestedMedia>[];
      for (final m in _urlRegex.allMatches(html)) {
        final url = m.group(0)!;
        final ext = m.group(1)!.toLowerCase();
        final kind = ext == 'm3u8'
            ? MediaKind.hls
            : ext == 'mpd'
                ? MediaKind.dash
                : (ext == 'mp3' || ext == 'm4a')
                    ? MediaKind.audio
                    : MediaKind.direct;
        found.add(HarvestedMedia(
          url: url,
          kind: kind,
          sourceUrl: iframeUrl,
          sourceTitle: pageTitle,
          discoveredVia: 'iframe',
        ));
      }
      return found;
    } catch (_) {
      return [];
    }
  }

  /// Löst ein HLS/DASH-Manifest zu konkreten Qualitätsstufen auf.
  static Future<List<MediaVariant>> resolveVariants(HarvestedMedia media) async {
    if (media.kind != MediaKind.hls && media.kind != MediaKind.dash) {
      return [MediaVariant(url: media.url, label: 'Original')];
    }
    try {
      final client = HttpClient()..userAgent = _userAgent;
      final request = await client.getUrl(Uri.parse(media.url));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        return [MediaVariant(url: media.url, label: 'Original (ungeprüft)')];
      }
      final body = await response.transform(utf8.decoder).join();

      final streams = media.kind == MediaKind.hls
          ? HLSDashParser.parseHLS(body, manifestUrl: media.url)
          : HLSDashParser.parseDASH(body, manifestUrl: media.url);

      if (streams.isEmpty) {
        return [MediaVariant(url: media.url, label: 'Original')];
      }

      // Nach Bandbreite absteigend sortieren (beste Qualität zuerst).
      streams.sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
      return streams
          .map((s) => MediaVariant(url: s.url, label: s.quality, bandwidth: s.bandwidth))
          .toList();
    } catch (_) {
      return [MediaVariant(url: media.url, label: 'Original (Fehler beim Auflösen)')];
    }
  }
}
