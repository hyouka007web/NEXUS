/// Art der gefundenen Medien-Quelle.
enum MediaKind { hls, dash, direct, audio, unknown }

MediaKind mediaKindFromString(String s) {
  switch (s) {
    case 'hls':
      return MediaKind.hls;
    case 'dash':
      return MediaKind.dash;
    case 'audio':
      return MediaKind.audio;
    case 'video':
    case 'direct':
      return MediaKind.direct;
    default:
      return MediaKind.unknown;
  }
}

/// Eine einzelne, vom Scraper/Harvester entdeckte Medienquelle
/// (kann eine fertige Videodatei sein oder ein HLS/DASH-Manifest,
/// das erst noch in einzelne Qualitätsstufen aufgelöst werden muss).
class HarvestedMedia {
  final String url;
  final MediaKind kind;
  final String sourceUrl; // Seite, auf der es gefunden wurde
  final String sourceTitle;
  final String discoveredVia; // "dom" | "network" | "script" | "jsonld" | "iframe" | "plugin:ard"
  final DateTime discoveredAt;

  /// Falls es sich um ein Manifest handelt: aufgelöste Qualitätsstufen.
  /// Wird nachträglich befüllt (lazy), damit die Liste sofort erscheint.
  List<MediaVariant> variants;

  HarvestedMedia({
    required this.url,
    required this.kind,
    required this.sourceUrl,
    required this.sourceTitle,
    required this.discoveredVia,
    DateTime? discoveredAt,
    List<MediaVariant>? variants,
  })  : discoveredAt = discoveredAt ?? DateTime.now(),
        variants = variants ?? [];

  String get suggestedFileName {
    final base = sourceTitle.trim().isNotEmpty
        ? sourceTitle.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        : 'nexus_media_${discoveredAt.millisecondsSinceEpoch}';
    return base;
  }

  /// Eindeutigkeit für Deduplizierung in der Harvester-Liste.
  String get dedupeKey => '$url';
}

/// Eine konkrete herunterladbare Qualitätsstufe eines HarvestedMedia-Eintrags.
class MediaVariant {
  final String url;
  final String label; // z.B. "1080p", "720p", "480p", "Original"
  final int bandwidth;

  MediaVariant({required this.url, required this.label, this.bandwidth = 0});
}
