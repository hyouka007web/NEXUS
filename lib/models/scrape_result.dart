/// Ergebnis von [ScraperEngine.scrape] — 1:1-Pendant zu Kotlins `ScrapeResult`.
class ScrapeResult {
  final String title;
  final List<String> links;
  final List<String> media;
  final int htmlSize;

  const ScrapeResult({
    required this.title,
    required this.links,
    required this.media,
    required this.htmlSize,
  });
}
