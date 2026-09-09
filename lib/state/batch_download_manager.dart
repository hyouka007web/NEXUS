import 'package:flutter/foundation.dart';

import '../engines/video_downloader.dart';
import '../models/harvested_video.dart';

enum BatchItemState { queued, downloading, paused, done, failed }

class BatchItem {
  final String id;
  final HarvestedVideo video;
  final String referer;
  BatchItemState state;
  int percent;
  String? errorMessage;
  CancelToken? cancelToken;

  BatchItem({
    required this.id,
    required this.video,
    required this.referer,
    this.state = BatchItemState.queued,
    this.percent = 0,
    this.errorMessage,
    this.cancelToken,
  });
}

/// Lädt mehrere, bereits vom Harvester gefundene Videos parallel herunter
/// (konfigurierbare Nebenläufigkeit), statt dass der Nutzer jedes einzeln
/// antippen muss. Arbeitet ausschließlich mit dem Ergebnis EINES bereits
/// abgeschlossenen, vom Nutzer selbst ausgelösten Harvest-Laufs — kein
/// eigenständiges Nachladen oder Crawlen weiterer Seiten.
class BatchDownloadManager extends ChangeNotifier {
  BatchDownloadManager._();
  static final BatchDownloadManager instance = BatchDownloadManager._();

  final List<BatchItem> items = [];
  int concurrency = 3;

  int get activeCount => items.where((i) => i.state == BatchItemState.downloading).length;
  int get doneCount => items.where((i) => i.state == BatchItemState.done).length;

  void enqueueAll(List<HarvestedVideo> videos, String referer) {
    for (final v in videos) {
      if (items.any((i) => i.video.url == v.url)) continue;
      items.add(BatchItem(id: v.url, video: v, referer: referer));
    }
    notifyListeners();
    _pump();
  }

  void setConcurrency(int value) {
    concurrency = value.clamp(1, 8);
    notifyListeners();
    _pump();
  }

  void pause(BatchItem item) {
    if (item.state != BatchItemState.downloading) return;
    item.cancelToken?.cancel();
    item.state = BatchItemState.paused;
    notifyListeners();
  }

  void resume(BatchItem item) {
    if (item.state != BatchItemState.paused && item.state != BatchItemState.failed) return;
    item.state = BatchItemState.queued;
    item.errorMessage = null;
    notifyListeners();
    _pump();
  }

  void remove(BatchItem item) {
    if (item.state == BatchItemState.downloading) item.cancelToken?.cancel();
    items.removeWhere((i) => i.id == item.id);
    notifyListeners();
  }

  void clearFinished() {
    items.removeWhere((i) => i.state == BatchItemState.done);
    notifyListeners();
  }

  void _pump() {
    while (activeCount < concurrency) {
      final next = items.where((i) => i.state == BatchItemState.queued).firstOrNull;
      if (next == null) break;
      _runItem(next);
    }
  }

  Future<void> _runItem(BatchItem item) async {
    item.state = BatchItemState.downloading;
    item.cancelToken = CancelToken();
    notifyListeners();
    try {
      await VideoDownloader.download(
        item.video.url,
        item.video.title,
        referer: item.referer,
        headers: {
          ...item.video.headers,
          if (item.video.cookies.isNotEmpty) 'Cookie': item.video.cookies,
          if (item.video.userAgent.isNotEmpty) 'User-Agent': item.video.userAgent,
        },
        cancelToken: item.cancelToken,
        onProgress: (progress) {
          if (progress.percent >= 0) {
            item.percent = progress.percent;
            notifyListeners();
          }
        },
      );
      item.state = BatchItemState.done;
    } on DownloadCancelledException {
      // Zustand wurde von pause() bereits auf "paused" gesetzt — hier
      // nichts überschreiben.
    } catch (e) {
      item.state = BatchItemState.failed;
      item.errorMessage = '$e';
    } finally {
      notifyListeners();
      _pump();
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
