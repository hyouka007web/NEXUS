import 'dart:convert';

/// HLSDashParser: Parsed HLS (.m3u8) und DASH (.mpd) Manifeste via JS-Injection.
/// Extrahiert alle Video-Streams mit Qualitätsstufen.
class HLSDashParser {
  /// Parst HLS-M3U8-Playliste und extrahiert Stream-URLs.
  static List<StreamQuality> parseHLS(String playlistContent) {
    final List<StreamQuality> streams = [];
    final lines = playlistContent.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.startsWith('#EXTINF')) {
        // Extrahiere Dauer
        final durationMatch = RegExp(r'#EXTINF:([\d.]+)').firstMatch(line);
        final duration = double.tryParse(durationMatch?.group(1) ?? '0') ?? 0.0;

        // Nächste Zeile ist die URL
        if (i + 1 < lines.length) {
          final url = lines[i + 1].trim();
          if (url.isNotEmpty && !url.startsWith('#')) {
            streams.add(StreamQuality(
              url: url,
              type: 'hls',
              quality: _extractQualityFromUrl(url),
              duration: duration,
            ));
          }
        }
      }
      // EXT-X_STREAM-INF (Varianten-Streams)
      if (line.startsWith('#EXT-X_STREAM-INF')) {
        final bwMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
        final bandwidth = int.tryParse(bwMatch?.group(1) ?? '0') ?? 0;

        if (i + 1 < lines.length) {
          final url = lines[i + 1].trim();
          if (url.isNotEmpty && !url.startsWith('#')) {
            streams.add(StreamQuality(
              url: url,
              type: 'hls',
              quality: _bandwidthToResolution(bandwidth),
              bandwidth: bandwidth,
              duration: 0,
            ));
          }
        }
      }
    }
    return streams;
  }

  /// Parst DASH-MPD-Manifest und extrahiert Streams.
  static List<StreamQuality> parseDASH(String mpdContent) {
    final List<StreamQuality> streams = [];

    // Segment-Templates finden
    final repRegex = RegExp(r'<Representation(?:\s[^>]*?)>');
    for (final match in repRegex.allMatches(mpdContent)) {
      final repStr = match.group(0)!;
      final urlMatch = RegExp(r'src="([^"]+)"').firstMatch(repStr);
      final bandwidthMatch = RegExp(r'bandwidth="(\d+)"').firstMatch(repStr);
      final widthMatch = RegExp(r'width="(\d+)"').firstMatch(repStr);
      final heightMatch = RegExp(r'height="(\d+)"').firstMatch(repStr);

      final url = urlMatch?.group(1) ?? '';
      final bandwidth = int.tryParse(bandwidthMatch?.group(1) ?? '0') ?? 0;
      final width = int.tryParse(widthMatch?.group(1) ?? '0') ?? 0;
      final height = int.tryParse(heightMatch?.group(1) ?? '0') ?? 0;

      if (url.isNotEmpty) {
        streams.add(StreamQuality(
          url: url,
          type: 'dash',
          quality: '${width}x$height',
          bandwidth: bandwidth,
          duration: 0,
        ));
      }
    }
    return streams;
  }

  /// Extrahiert Qualität aus URL (z.B. 1080p, 720p).
  static String _extractQualityFromUrl(String url) {
    final match = RegExp(r'(\d+)p').firstMatch(url);
    if (match != null) return '${match.group(1)}p';
    return 'unknown';
  }

  /// Konvertiert Bandbreite zu typischer Auflösung.
  static String _bandwidthToResolution(int bandwidth) {
    if (bandwidth > 5000000) return '2160p';
    if (bandwidth > 3000000) return '1440p';
    if (bandwidth > 1500000) return '1080p';
    if (bandwidth > 800000) return '720p';
    if (bandwidth > 400000) return '480p';
    return '360p';
  }
}

class StreamQuality {
  final String url;
  final String type; // 'hls', 'dash', 'video'
  final String quality; // z.B. '720p'
  final int bandwidth;
  final double duration;

  StreamQuality({
    required this.url,
    required this.type,
    required this.quality,
    this.bandwidth = 0,
    this.duration = 0,
  });
}
