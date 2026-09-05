import '../models/harvested_video.dart';
import '../models/media_candidate.dart';
import 'video_harvester_engine.dart';

/// yt-dlp-style Orchestrierung: Extraktor-Kandidaten werden bewertet und
/// normalisiert, bevor der Downloader aufgerufen wird. Eine eigenständige
/// Implementierung, keine Kopie von yt-dlp — behandelt nur öffentlich
/// erreichbare Medien-/Player-URLs. 1:1-Verhalten zu Kotlins
/// `YtDlpStyleExtractor`.
class YtDlpStyleExtractor {
  YtDlpStyleExtractor._();

  static Future<List<MediaCandidate>> extract(String pageUrl) async {
    final harvested =
        await VideoHarvesterEngine.harvest(pageUrl, deepInspect: true);
    final byUrl = <String, MediaCandidate>{};
    for (final item in harvested) {
      byUrl[item.url] = MediaCandidate(
        url: item.url,
        type: item.type,
        score: _score(item),
        title: item.title,
      );
    }
    final list = byUrl.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return list;
  }

  static int _score(HarvestedVideo item) {
    final url = item.url.toLowerCase();
    int score = switch (item.type) {
      'MP4' => 100,
      'WEBM' => 95,
      'M3U8' => 90,
      'MEDIA' => 85,
      'PLAYER' => 55,
      _ => 0,
    };
    if (url.contains('1080')) score += 30;
    if (url.contains('720')) score += 20;
    if (url.contains('480')) score += 10;
    if (url.contains('master')) score += 8;
    if (url.contains('playlist')) score += 5;
    String query = '';
    try {
      query = Uri.parse(url).query;
    } catch (_) {
      // ignorieren, wie im Kotlin-Original
    }
    if (query.contains('token')) score -= 2;
    return score;
  }
}
