/// Ein fertig heruntergeladenes Video in der lokalen Mediathek-Ablage —
/// Pendant zu Kotlins `VideoEntry`.
class VideoEntry {
  final String id;
  final String title;
  final String filePath;
  final String sourceUrl;
  final String downloadedAt;
  final int sizeBytes;

  const VideoEntry({
    required this.id,
    required this.title,
    required this.filePath,
    required this.sourceUrl,
    required this.downloadedAt,
    required this.sizeBytes,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'filePath': filePath,
        'sourceUrl': sourceUrl,
        'downloadedAt': downloadedAt,
        'sizeBytes': sizeBytes,
      };

  factory VideoEntry.fromJson(Map<String, dynamic> json) => VideoEntry(
        id: json['id'] as String,
        title: json['title'] as String,
        filePath: json['filePath'] as String,
        sourceUrl: json['sourceUrl'] as String,
        downloadedAt: json['downloadedAt'] as String,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      );
}

/// Live-Fortschritt während eines laufenden Downloads — Pendant zu Kotlins
/// `DownloadProgress`. [total] ist -1, wenn die Gegenstelle keine
/// Content-Length liefert (z.B. bei manchen HLS-Quellen).
class DownloadProgress {
  final int bytes;
  final int total;
  final int percent;

  const DownloadProgress({
    required this.bytes,
    required this.total,
    required this.percent,
  });
}
