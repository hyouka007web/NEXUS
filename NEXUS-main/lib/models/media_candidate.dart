/// Bewerteter Medien-Kandidat aus [YtDlpStyleExtractor] — Pendant zu Kotlins
/// `MediaCandidate`.
class MediaCandidate {
  final String url;
  final String type;
  final int score;
  final String title;

  const MediaCandidate({
    required this.url,
    required this.type,
    required this.score,
    required this.title,
  });
}
