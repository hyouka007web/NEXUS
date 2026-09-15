import 'dart:convert';
import 'dart:io';

/// ARD-Mediathek-Scraper: Extrahiert Video-URLs, Titel, und Metadaten.
/// Nutzt Scrapling-Style Deep-Scraping (JSON-LD, API-Pfade, Regex-Fallback).
class MediathekScraper {
  /// Scrappt eine ARD-Mediathek-URL und extrahiert alle Video-Download-Links.
  static Future<MediaContent> scrapeArd(String url) async {
    final uri = Uri.parse(url);
    final client = HttpClient()
      ..userAgent = 'Mozilla/5.0 (Linux; Android 13; SM-S901B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
    
    final request = await client.getUrl(uri);
    final response = await request.close();

    if (response.statusCode != HttpStatus.ok) {
      throw Exception('Failed to load page: ${response.statusCode}');
    }

    final html = await response.transform(utf8.decoder).join();

    // JSON-LD extrahieren (ARD-Mediathek nutzt JSON-LD für Videometadaten)
    final jsonLdMatch = RegExp(
      r'<script[^>]*type="application/ld\+json"[^>]*>([^<]+)</script>',
      caseSensitive: false,
    ).firstMatch(html);

    if (jsonLdMatch != null) {
      final jsonData = jsonLdMatch.group(1)!;
      final decoded = jsonDecode(jsonData);
      
      if (decoded is Map<String, dynamic>) {
        return _parseJsonLd(decoded);
      }
      if (decoded is List) {
        for (var item in decoded) {
          if (item is Map<String, dynamic> && item.containsKey('video')) {
            return _parseJsonLd(item);
          }
        }
      }
    }

    // Fallback: JSON-API von ARD durchsuchen
    final apiMatch = RegExp(
      r'"(https://api\.ard\.mediathek\.com/[^"]+)"',
    ).firstMatch(html);
    
    if (apiMatch != null) {
      return await _scrapeArdApi(apiMatch.group(1)!);
    }

    // Regex-Fallback für .m3u8/.mpd
    final streamMatch = RegExp(
      r'(https?://[^"\s]+\.(m3u8|mpd))',
      caseSensitive: false,
    ).firstMatch(html);

    if (streamMatch != null) {
      return MediaContent(
        title: 'ARD Video',
        streamUrls: [StreamInfo(url: streamMatch.group(1)!, type: streamMatch.group(2)!)],
        thumbnailUrl: '',
        duration: 0,
      );
    }

    throw Exception('Keine Video-Quellen gefunden in: $url');
  }

  static MediaContent _parseJsonLd(Map<String, dynamic> data) {
    final title = data['name'] ?? data['headline'] ?? 'Titel unbekannt';
    final thumbnail = data['thumbnailUrl'] ?? data['image'] ?? '';
    
    final List<StreamInfo> streams = [];
    
    if (data.containsKey('video')) {
      final video = data['video'];
      if (video is Map) {
        final url = video['contentUrl'] ?? '';
        if (url.isNotEmpty) {
          streams.add(StreamInfo(url: url, type: _detectType(url)));
        }
        
        if (video.containsKey('encodingFormat') && video['encodingFormat'] == 'application/vnd.apple.mpegurl') {
          streams.add(StreamInfo(url: url, type: 'hls'));
        }
        if (video.containsKey('encodingFormat') && video['encodingFormat'] == 'application/dash+xml') {
          streams.add(StreamInfo(url: url, type: 'dash'));
        }
      }
    }

    // Weitere Streams aus 'hasPart' extrahieren
    if (data.containsKey('hasPart')) {
      final parts = data['hasPart'];
      if (parts is List) {
        for (var part in parts) {
          if (part is Map) {
            final url = part['contentUrl'] ?? '';
            if (url.isNotEmpty) {
              streams.add(StreamInfo(url: url, type: _detectType(url)));
            }
          }
        }
      }
    }

    return MediaContent(
      title: title,
      streamUrls: streams,
      thumbnailUrl: thumbnail,
      duration: int.tryParse(data["duration"].toString()) ?? 0,
    );
  }

  static Future<MediaContent> _scrapeArdApi(String apiUrl) async {
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(apiUrl));
    final response = await request.close();
    
    if (response.statusCode != HttpStatus.ok) {
      throw Exception('API-Fehler: ${response.statusCode}');
    }
    
    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body);
    
    final title = json['title'] ?? 'Titel unbekannt';
    final List<StreamInfo> streams = [];
    
    if (json.containsKey('mediaArray') && json['mediaArray'] is List) {
      for (var media in json['mediaArray']) {
        if (media is Map && media.containsKey('stream')) {
          streams.add(StreamInfo(url: media['stream'], type: media['mediaType'] ?? 'video'));
        }
      }
    }
    
    return MediaContent(
      title: title,
      streamUrls: streams,
      thumbnailUrl: json['previewImageUrl'] ?? '',
      duration: int.tryParse(json['duration'] ?? '0') ?? 0,
    );
  }

  static String _detectType(String url) {
    if (url.endsWith('.m3u8') || url.contains('.m3u8')) return 'hls';
    if (url.endsWith('.mpd') || url.contains('.mpd')) return 'dash';
    return 'video';
  }
}

/// Metadaten einer Media-Content
class MediaContent {
  final String title;
  final List<StreamInfo> streamUrls;
  final String thumbnailUrl;
  final int duration; // Sekunden

  MediaContent({
    required this.title,
    required this.streamUrls,
    required this.thumbnailUrl,
    required this.duration,
  });
}

/// Stream-Information (HLS/DASH/Video)
class StreamInfo {
  final String url;
  final String type;

  StreamInfo({required this.url, required this.type});
}
