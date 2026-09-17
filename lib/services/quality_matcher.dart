import 'package:nexus/models/harvested_media.dart';

/// Feste Ziel-Qualitäten für Batch-Downloads (Master-Prompt Kapitel 19/20).
enum QualityTarget { best, q1080, q720, q480, q360 }

const Map<QualityTarget, String> qualityTargetLabels = {
  QualityTarget.best: 'Beste verfügbare',
  QualityTarget.q1080: '1080p',
  QualityTarget.q720: '720p',
  QualityTarget.q480: '480p',
  QualityTarget.q360: '360p',
};

/// Extrahiert eine vergleichbare Höhen-Zahl aus einem Qualitäts-Label
/// ("1080p" → 1080, "1280x720" → 720, alles andere → null).
int? _rankOf(String label) {
  final pMatch = RegExp(r'(\d+)p\b').firstMatch(label);
  if (pMatch != null) return int.tryParse(pMatch.group(1)!);
  final resMatch = RegExp(r'(\d+)x(\d+)').firstMatch(label);
  if (resMatch != null) return int.tryParse(resMatch.group(2)!);
  return null;
}

/// Wählt aus den verfügbaren Varianten eines Medien-Fundes die, die dem
/// Ziel am nächsten kommt. Kein Treffer in der Zielqualität? → die Variante
/// mit dem kleinsten Abstand nach oben ODER unten (Kapitel 20: "nearest").
MediaVariant pickNearestVariant(List<MediaVariant> variants, QualityTarget target) {
  if (variants.isEmpty) {
    throw ArgumentError('variants darf nicht leer sein');
  }
  if (variants.length == 1) return variants.first;

  final ranked = variants.map((v) => MapEntry(v, _rankOf(v.label))).toList();
  final withRank = ranked.where((e) => e.value != null).toList();

  if (withRank.isEmpty) {
    // Keine Auflösung erkennbar — Bandbreite als Näherung nutzen,
    // sonst schlicht die erste (meist schon nach Bandbreite sortierte) Variante.
    return variants.first;
  }

  if (target == QualityTarget.best) {
    withRank.sort((a, b) => b.value!.compareTo(a.value!));
    return withRank.first.key;
  }

  final targetRank = switch (target) {
    QualityTarget.q1080 => 1080,
    QualityTarget.q720 => 720,
    QualityTarget.q480 => 480,
    QualityTarget.q360 => 360,
    QualityTarget.best => 0,
  };

  withRank.sort((a, b) => (a.value! - targetRank).abs().compareTo((b.value! - targetRank).abs()));
  return withRank.first.key;
}
