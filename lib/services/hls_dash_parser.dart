import 'dart:convert';

/// HLSDashParser: Parsed HLS (.m3u8) und DASH (.mpd) Manifeste.
/// Extrahiert alle Video-Streams mit Qualitätsstufen.
class HLSDashParser {
  static List<StreamQuality> parseHLS(String playlist) {
    final streams = <StreamQuality>[];
    final lines = playlist.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.startsWith('#EXTINF')) {
        final durMatch = RegExp(r'#EXTINF:([\d.]+)').firstMatch(line);
        final dur = double.tryParse(durMatch?.group(1) ?? '0') ?? 0.0;
        if (i + 1 < lines.length) {
          final url = lines[i + 1].trim();
          if (url.isNotEmpty && !url.startsWith('#')) {
            streams.add(StreamQuality(url: url, type: 'hls', quality: _getQuality(url), duration: dur));
          }
        }
      }
      if (line.startsWith('#EXT-X_STREAM-INF')) {
        final bwMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
        final bw = int.tryParse(bwMatch?.group(1) ?? '0') ?? 0;
        if (i + 1 < lines.length) {
          final url = lines[i + 1].trim();
          if (url.isNotEmpty && !url.startsWith('#')) {
            streams.add(StreamQuality(url: url, type: 'hls', quality: _bwToQual(bw), bandwidth: bw));
          }
        }
      }
    }
    return streams;
  }

  static List<StreamQuality> parseDASH(String manifest) {
    final streams = <StreamQuality>[];
    final repRegex = RegExp(r'<Representation[^>]*>');
    for (final match in repRegex.allMatches(manifest)) {
      final repStr = match.group(0)!;
      final urlMatch = RegExp(r'src="([^"]+)"').firstMatch(repStr);
      final bwMatch = RegExp(r'bandwidth="(\d+)"').firstMatch(repStr);
      final wMatch = RegExp(r'width="(\d+)"').firstMatch(repStr);
      final hMatch = RegExp(r'height="(\d+)"').firstMatch(repStr);
      final url = urlMatch?.group(1) ?? '';
      if (url.isNotEmpty) {
        streams.add(StreamQuality(
          url: url,
          type: 'dash',
          quality: '${wMatch?.group(1) ?? '?' }x${hMatch?.group(1) ?? '?'}',
          bandwidth: int.tryParse(bwMatch?.group(1) ?? '0') ?? 0,
        ));
      }
    }
    return streams;
  }

  static String _getQuality(String url) {
    final idx = url.indexOf('index-DVR-');
    if (idx >= 0) {
      final chunk = url.substring(idx + 8, idx + 15);
      final digits = chunk.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isNotEmpty) return '${digits}p';
    }
    return 'unknown';
  }

  static String _bwToQual(int bw) {
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
  final double duration;

  StreamQuality({
    required this.url,
    required this.type,
    this.quality = 'unknown',
    this.bandwidth = 0,
    this.duration = 0.0,
  });
}
