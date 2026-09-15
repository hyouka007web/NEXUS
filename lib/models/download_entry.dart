enum DownloadStatus { queued, downloading, paused, completed, failed, canceled }

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
  }) : startedAt = startedAt ?? DateTime.now();

  bool get isActive => status == DownloadStatus.downloading || status == DownloadStatus.queued;
  bool get isDone => status == DownloadStatus.completed;
  bool get isFailed => status == DownloadStatus.failed;
}
