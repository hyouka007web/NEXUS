import 'ytdlp_style_extractor.dart';

/// Pendant zu Kotlins `MediaLinkFinder` — filtert aus den Extraktor-
/// Kandidaten nur die direkt abspielbaren Medien-URLs heraus.
class MediaLinkFinder {
  MediaLinkFinder._();

  static const _mediaTypes = {'MP4', 'WEBM', 'M3U8', 'MEDIA'};

  static Future<List<String>> findVideoUrls(String pageUrl) async {
    final candidates = await YtDlpStyleExtractor.extract(pageUrl);
    final urls = candidates
        .where((c) => _mediaTypes.contains(c.type))
        .map((c) => c.url)
        .toSet()
        .toList();
    return urls;
  }
}
