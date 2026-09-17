enum DownloadStatus { queued, downloading, paused, completed, failed, canceled }

/// Grobe Medien-Kategorie für die Mediathek-Filter (Kapitel 23:
/// ALL / VIDEOS / AUDIO / PDF / EPUB / IMAGES / OTHER).
enum DownloadCategory { video, audio, pdf, epub, image, other }

DownloadCategory categoryForPath(String pathOrUrl) {
  final lower = pathOrUrl.toLowerCase();
  if (lower.endsWith('.pdf')) return DownloadCategory.pdf;
  if (lower.endsWith('.epub')) return DownloadCategory.epub;
  if (RegExp(r'\.(mp4|webm|mkv|m4v|ts|mov|avi)(\?|$)').hasMatch(lower)) return DownloadCategory.video;
  if (RegExp(r'\.(mp3|m4a|aac|ogg|wav|flac)(\?|$)').hasMatch(lower)) return DownloadCategory.audio;
  if (RegExp(r'\.(jpg|jpeg|png|gif|webp|bmp|svg)(\?|$)').hasMatch(lower)) return DownloadCategory.image;
  return DownloadCategory.other;
}

class DownloadEntry {
  final String id;
  final String url;
  String title;
  final String type; // hls | dash | direct | audio
  DownloadStatus status;
  double progress; // 0..1, -1 = unbekannt (kein Content-Length)
  int totalBytes;
  int receivedBytes;
  String? localPath;
  String? error;
  final DateTime startedAt;

  /// Aktuelle Geschwindigkeit in Bytes/s und geschätzte Restzeit in Sekunden
  /// (null = nicht ermittelbar, z.B. bei unbekannter Gesamtgröße).
  double speedBytesPerSec;
  int? etaSeconds;

  /// Ob der Server Range-Requests unterstützt hat (nötig für Pause/Resume).
  bool supportsResume;
  int retryCount;

  bool selected; // für Mehrfachauswahl in der Mediathek

  DownloadEntry({
    required this.id,
    required this.url,
    required this.title,
    required this.type,
    this.status = DownloadStatus.queued,
    this.progress = 0.0,
    this.totalBytes = 0,
    this.receivedBytes = 0,
    this.localPath,
    this.error,
    DateTime? startedAt,
    this.speedBytesPerSec = 0,
    this.etaSeconds,
    this.supportsResume = false,
    this.retryCount = 0,
    this.selected = false,
  }) : startedAt = startedAt ?? DateTime.now();

  bool get isActive => status == DownloadStatus.downloading || status == DownloadStatus.queued;
  bool get isDone => status == DownloadStatus.completed;
  bool get isFailed => status == DownloadStatus.failed;
  bool get isPaused => status == DownloadStatus.paused;
  bool get canResume => (isPaused || isFailed) && supportsResume && receivedBytes > 0;

  DownloadCategory get category => categoryForPath(localPath ?? url);
}
