import 'package:nexus/models/harvested_media.dart';

/// NetworkSniffer: passiver Mitschnitt aller Requests, die durch die
/// WebView laufen (via shouldInterceptRequest). Erkennt Medien-URLs
/// unabhängig davon, ob sie im DOM stehen — auch nachgeladene
/// XHR/fetch-Requests (z.B. HLS-Segment-Requests, versteckte APIs)
/// werden hier erfasst. Das ist der Teil, der "echtes" Netzwerk-Sniffing
/// leistet statt nur den sichtbaren HTML-Quelltext zu durchsuchen.
class NetworkSniffer {
  static final RegExp _mediaExt = RegExp(
    r'\.(m3u8|mpd|mp4|webm|mkv|m4v|m4a|mp3|aac|ogg|ts)(\?|$)',
    caseSensitive: false,
  );

  // Wird bewusst nicht bei jedem .ts-Request gefeuert (das sind meist
  // normale HLS-Segmente einer bereits erkannten Playlist) — nur bei
  // Manifesten und eigenständigen Mediendateien.
  static final RegExp _manifestOrFileExt = RegExp(
    r'\.(m3u8|mpd|mp4|webm|mkv|m4v|m4a|mp3|aac|ogg)(\?|$)',
    caseSensitive: false,
  );

  final Set<String> _seen = {};

  /// Prüft einen abgefangenen Request. Gibt einen HarvestedMedia-Eintrag
  /// zurück, falls es sich erkennbar um eine Mediendatei/ein Manifest handelt.
  HarvestedMedia? inspect({
    required String requestUrl,
    required String pageUrl,
    required String pageTitle,
    String? contentType,
  }) {
    if (_seen.contains(requestUrl)) return null;

    final byExt = _manifestOrFileExt.hasMatch(requestUrl);
    final byContentType = contentType != null &&
        (contentType.startsWith('video/') ||
            contentType.startsWith('audio/') ||
            contentType.contains('mpegurl') ||
            contentType.contains('dash+xml'));

    if (!byExt && !byContentType) return null;
    _seen.add(requestUrl);

    MediaKind kind;
    final lower = requestUrl.toLowerCase();
    if (lower.contains('.m3u8') || (contentType?.contains('mpegurl') ?? false)) {
      kind = MediaKind.hls;
    } else if (lower.contains('.mpd') || (contentType?.contains('dash+xml') ?? false)) {
      kind = MediaKind.dash;
    } else if (lower.contains('.mp3') || lower.contains('.aac') || lower.contains('.ogg') ||
        lower.contains('.m4a') || (contentType?.startsWith('audio/') ?? false)) {
      kind = MediaKind.audio;
    } else {
      kind = MediaKind.direct;
    }

    return HarvestedMedia(
      url: requestUrl,
      kind: kind,
      sourceUrl: pageUrl,
      sourceTitle: pageTitle,
      discoveredVia: 'network',
    );
  }

  void reset() => _seen.clear();
}
