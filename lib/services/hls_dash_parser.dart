/// HLSDashParser: Parsed HLS (.m3u8) Master-/Media-Playlists und
/// DASH (.mpd) Manifeste zu einzelnen, direkt herunterladbaren
/// Qualitätsstufen.
class HLSDashParser {
  /// Löst relative Manifest-URLs gegen die Basis-URL auf.
  static String _resolve(String base, String maybeRelative) {
    if (maybeRelative.startsWith('http://') || maybeRelative.startsWith('https://')) {
      return maybeRelative;
    }
    try {
      return Uri.parse(base).resolve(maybeRelative).toString();
    } catch (_) {
      return maybeRelative;
    }
  }

  static List<StreamQuality> parseHLS(String playlist, {required String manifestUrl}) {
    final streams = <StreamQuality>[];
    final lines = playlist.split('\n');
    bool isMaster = playlist.contains('#EXT-X-STREAM-INF');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      // Master-Playlist: Verweise auf Varianten-Playlists mit Bandbreite/Auflösung.
      if (line.startsWith('#EXT-X-STREAM-INF')) {
        final bwMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
        final resMatch = RegExp(r'RESOLUTION=(\d+x\d+)').firstMatch(line);
        final bw = int.tryParse(bwMatch?.group(1) ?? '0') ?? 0;
        if (i + 1 < lines.length) {
          final next = lines[i + 1].trim();
          if (next.isNotEmpty && !next.startsWith('#')) {
            streams.add(StreamQuality(
              url: _resolve(manifestUrl, next),
              type: 'hls',
              quality: resMatch?.group(1) ?? _bwToQual(bw),
              bandwidth: bw,
            ));
          }
        }
      }

      // Media-Playlist (keine Varianten, direkte Segmente): als "Original" anbieten.
      if (!isMaster && line.startsWith('#EXTINF') && streams.isEmpty) {
        streams.add(StreamQuality(
          url: manifestUrl,
          type: 'hls',
          quality: 'Original (Segmente)',
        ));
        break;
      }
    }
    return streams;
  }

  static List<StreamQuality> parseDASH(String manifest, {required String manifestUrl}) {
    final streams = <StreamQuality>[];

    // Optionaler globaler <BaseURL> auf MPD-Ebene
    final mpdBaseMatch = RegExp(r'<BaseURL>([^<]+)</BaseURL>').firstMatch(manifest);
    final mpdBase = mpdBaseMatch != null ? _resolve(manifestUrl, mpdBaseMatch.group(1)!.trim()) : manifestUrl;

    final repRegex = RegExp(r'<Representation\b[^>]*>(.*?)</Representation>', dotAll: true);
    final repSelfClosing = RegExp(r'<Representation\b[^>]*/>');

    final matches = [...repRegex.allMatches(manifest), ...repSelfClosing.allMatches(manifest)];

    for (final match in matches) {
      final block = match.group(0)!;
      final attrsPart = block.startsWith('<Representation') ? block : block;

      final bwMatch = RegExp(r'bandwidth="(\d+)"', caseSensitive: false).firstMatch(attrsPart);
      final wMatch = RegExp(r'width="(\d+)"', caseSensitive: false).firstMatch(attrsPart);
      final hMatch = RegExp(r'height="(\d+)"', caseSensitive: false).firstMatch(attrsPart);

      // URL kann als <BaseURL> Kindelement ODER (nicht-standard) als Attribut vorliegen.
      String? url;
      final childBaseMatch = RegExp(r'<BaseURL>([^<]+)</BaseURL>').firstMatch(block);
      if (childBaseMatch != null) {
        url = childBaseMatch.group(1)!.trim();
      } else {
        final srcAttr = RegExp(r'(?:src|media)="([^"]+)"', caseSensitive: false).firstMatch(attrsPart);
        url = srcAttr?.group(1);
      }
      if (url == null || url.isEmpty) continue;

      final resolved = _resolve(mpdBase, url);
      final bw = int.tryParse(bwMatch?.group(1) ?? '0') ?? 0;
      final quality = (wMatch != null && hMatch != null)
          ? '${wMatch.group(1)}x${hMatch.group(1)}'
          : _bwToQual(bw);

      streams.add(StreamQuality(url: resolved, type: 'dash', quality: quality, bandwidth: bw));
    }

    // Fallback: keine <Representation>-Treffer, aber ein globales BaseURL vorhanden.
    if (streams.isEmpty && mpdBaseMatch != null) {
      streams.add(StreamQuality(url: mpdBase, type: 'dash', quality: 'Original'));
    }

    return streams;
  }

  static String _bwToQual(int bw) {
    if (bw <= 0) return 'Original';
    if (bw > 5000000) return '2160p';
    if (bw > 3000000) return '1440p';
    if (bw > 1500000) return '1080p';
    if (bw > 800000) return '720p';
    if (bw > 400000) return '480p';
    return '360p';
  }
}

class StreamQuality {
  final String url;
  final String type;
  final String quality;
  final int bandwidth;

  StreamQuality({
    required this.url,
    required this.type,
    this.quality = 'unknown',
    this.bandwidth = 0,
  });
}
