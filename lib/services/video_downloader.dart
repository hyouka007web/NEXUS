import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nexus/models/download_entry.dart';
import 'package:nexus/models/harvested_media.dart';

/// VideoDownloader: verwaltet Queue, parallele Downloads, Pause/Resume
/// (via HTTP Range-Requests), Geschwindigkeit/ETA und Retry
/// (Master-Prompt Kapitel 22). Als ChangeNotifier, damit Mediathek/Panel
/// live Fortschritt anzeigen.
class VideoDownloader extends ChangeNotifier {
  static final VideoDownloader _instance = VideoDownloader._internal();
  factory VideoDownloader() => _instance;
  VideoDownloader._internal();

  static const int maxConcurrent = 3;

  final List<DownloadEntry> downloads = [];
  final Map<String, StreamSubscription> _activeSubs = {};
  final Map<String, IOSink> _activeSinks = {};
  final Map<String, _SpeedTracker> _speedTrackers = {};
  final HttpClient _httpClient = HttpClient();
  int _counter = 0;

  Future<Directory> _targetDir() async {
    Directory base;
    try {
      base = (await getExternalStorageDirectory())!;
    } catch (_) {
      base = await getApplicationDocumentsDirectory();
    }
    final dir = Directory('${base.path}/NEXUS_Downloads');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _extensionFor(String type, String url) {
    if (url.contains('.mp3')) return 'mp3';
    if (url.contains('.m4a')) return 'm4a';
    if (url.contains('.webm')) return 'webm';
    if (url.contains('.pdf')) return 'pdf';
    if (url.contains('.epub')) return 'epub';
    if (type == 'hls' || type == 'dash') return 'ts';
    return 'mp4';
  }

  int get _activeCount => downloads.where((d) => d.status == DownloadStatus.downloading).length;

  /// Reiht einen neuen Download ein (startet sofort, falls ein Slot frei
  /// ist, sonst wartet er als `queued` in der Warteschlange).
  DownloadEntry enqueue(MediaVariant variant, {required String title, required String type}) {
    _counter++;
    final id = 'dl_${DateTime.now().millisecondsSinceEpoch}_$_counter';
    final safeTitle = title.trim().isEmpty ? 'nexus_media_$_counter' : title.trim();

    final entry = DownloadEntry(
      id: id,
      url: variant.url,
      title: '$safeTitle${variant.label.isNotEmpty ? " [${variant.label}]" : ""}',
      type: type,
      status: DownloadStatus.queued,
    );
    downloads.insert(0, entry);
    notifyListeners();
    _processQueue();
    return entry;
  }

  // Rückwärtskompatibler Alias (Phase 1/2 riefen download() direkt auf).
  Future<DownloadEntry> download(MediaVariant variant, {required String title, required String type}) async {
    return enqueue(variant, title: title, type: type);
  }

  void _processQueue() {
    if (_activeCount >= maxConcurrent) return;
    final next = downloads.where((d) => d.status == DownloadStatus.queued).toList();
    for (final entry in next) {
      if (_activeCount >= maxConcurrent) break;
      // Ein Eintrag ist ein Resume-Fortsetzer, wenn bereits Bytes + eine
      // Zieldatei von einem vorherigen Versuch existieren — nicht anhand
      // eines separaten Flags, das beim Requeuen sonst verloren geht.
      final isResume = entry.receivedBytes > 0 && entry.localPath != null;
      _start(entry, resume: isResume);
    }
  }

  Future<void> _start(DownloadEntry entry, {required bool resume}) async {
    entry.status = DownloadStatus.downloading;
    notifyListeners();

    try {
      final dir = await _targetDir();
      File file;
      if (resume && entry.localPath != null) {
        file = File(entry.localPath!);
      } else {
        final ext = _extensionFor(entry.type, entry.url);
        final filename = '${entry.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.$ext';
        file = File('${dir.path}/$filename');
        entry.localPath = file.path;
        entry.receivedBytes = 0;
      }

      final sink = file.openWrite(mode: resume ? FileMode.append : FileMode.write);
      _activeSinks[entry.id] = sink;

      final client = _httpClient;
      final request = await client.getUrl(Uri.parse(entry.url));
      if (resume && entry.receivedBytes > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=${entry.receivedBytes}-');
      }
      final response = await request.close();

      final isPartial = response.statusCode == HttpStatus.partialContent;
      if (response.statusCode != HttpStatus.ok && !isPartial) {
        entry.status = DownloadStatus.failed;
        entry.error = 'HTTP ${response.statusCode}';
        notifyListeners();
        await sink.close();
        _activeSinks.remove(entry.id);
        _processQueue();
        return;
      }

      // Wenn ein Resume angefragt wurde, der Server aber trotzdem mit 200
      // (volle Datei statt 206 Partial) antwortet, ignoriert er den
      // Range-Header — würde er jetzt an die Teildatei angehängt, wäre
      // die Datei doppelt/korrupt. Stattdessen sauber neu aufsetzen.
      var effectiveResume = resume;
      if (resume && !isPartial) {
        await sink.flush();
        await sink.close();
        _activeSinks.remove(entry.id);
        final freshSink = file.openWrite(mode: FileMode.write);
        _activeSinks[entry.id] = freshSink;
        entry.receivedBytes = 0;
        effectiveResume = false;
      }
      final activeSink = _activeSinks[entry.id]!;

      entry.supportsResume = isPartial || (response.headers.value(HttpHeaders.acceptRangesHeader) == 'bytes');

      final contentLength = response.contentLength;
      if (!effectiveResume) {
        entry.totalBytes = contentLength;
        entry.progress = contentLength > 0 ? 0.0 : -1;
      } else if (contentLength > 0) {
        entry.totalBytes = entry.receivedBytes + contentLength;
      }

      _speedTrackers[entry.id] = _SpeedTracker(entry.receivedBytes);

      final completer = Completer<void>();
      final sub = response.listen(
        (chunk) {
          activeSink.add(chunk);
          entry.receivedBytes += chunk.length;
          if (entry.totalBytes > 0) entry.progress = entry.receivedBytes / entry.totalBytes;

          final tracker = _speedTrackers[entry.id];
          if (tracker != null) {
            final sample = tracker.sample(entry.receivedBytes);
            if (sample != null) {
              entry.speedBytesPerSec = sample;
              entry.etaSeconds = (entry.totalBytes > 0 && sample > 0)
                  ? ((entry.totalBytes - entry.receivedBytes) / sample).round()
                  : null;
              notifyListeners();
            }
          }
        },
        onDone: () async {
          await activeSink.flush();
          await activeSink.close();
          _activeSinks.remove(entry.id);
          entry.status = DownloadStatus.completed;
          entry.progress = 1.0;
          entry.speedBytesPerSec = 0;
          entry.etaSeconds = 0;
          notifyListeners();
          _activeSubs.remove(entry.id);
          _speedTrackers.remove(entry.id);
          if (!completer.isCompleted) completer.complete();
          _processQueue();
        },
        onError: (e) async {
          await activeSink.close();
          _activeSinks.remove(entry.id);
          entry.status = DownloadStatus.failed;
          entry.error = e.toString();
          entry.speedBytesPerSec = 0;
          notifyListeners();
          _activeSubs.remove(entry.id);
          _speedTrackers.remove(entry.id);
          if (!completer.isCompleted) completer.complete();
          _processQueue();
        },
        cancelOnError: true,
      );
      _activeSubs[entry.id] = sub;
      await completer.future;
    } catch (e) {
      entry.status = DownloadStatus.failed;
      entry.error = e.toString();
      notifyListeners();
      _processQueue();
    }
  }

  /// Pausiert einen laufenden Download — die Teildatei bleibt erhalten,
  /// damit resume() später an derselben Stelle weitermachen kann.
  Future<void> pause(String id) async {
    final entry = _find(id);
    if (entry == null || entry.status != DownloadStatus.downloading) return;
    await _activeSubs[id]?.cancel();
    _activeSubs.remove(id);
    await _activeSinks[id]?.flush();
    await _activeSinks[id]?.close();
    _activeSinks.remove(id);
    _speedTrackers.remove(id);
    entry.status = DownloadStatus.paused;
    entry.speedBytesPerSec = 0;
    notifyListeners();
    _processQueue();
  }

  /// Setzt einen pausierten oder fehlgeschlagenen Download fort, sofern
  /// der Server Range-Requests unterstützt hat — sonst kompletter Neustart.
  void resume(String id) {
    final entry = _find(id);
    if (entry == null) return;
    if (entry.canResume) {
      entry.status = DownloadStatus.queued;
      notifyListeners();
      _processQueue();
    } else {
      retry(id);
    }
  }

  /// Startet einen fehlgeschlagenen/abgebrochenen Download komplett neu.
  void retry(String id) {
    final entry = _find(id);
    if (entry == null) return;
    entry.retryCount++;
    entry.receivedBytes = 0;
    entry.totalBytes = 0;
    entry.progress = 0;
    entry.error = null;
    entry.status = DownloadStatus.queued;
    notifyListeners();
    _processQueue();
  }

  Future<void> cancel(String id) async {
    final entry = _find(id);
    await _activeSubs[id]?.cancel();
    _activeSubs.remove(id);
    await _activeSinks[id]?.close();
    _activeSinks.remove(id);
    _speedTrackers.remove(id);
    if (entry != null) {
      entry.status = DownloadStatus.canceled;
      entry.speedBytesPerSec = 0;
      notifyListeners();
    }
    _processQueue();
  }

  /// Entfernt einen Eintrag aus der Liste inkl. bereits geladener Teildatei.
  Future<void> remove(String id) async {
    final entry = _find(id);
    if (entry?.localPath != null && entry!.status != DownloadStatus.completed) {
      try {
        final f = File(entry.localPath!);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    downloads.removeWhere((d) => d.id == id);
    notifyListeners();
  }

  Future<void> removeMany(Iterable<String> ids) async {
    for (final id in ids) {
      await remove(id);
    }
  }

  DownloadEntry? _find(String id) {
    try {
      return downloads.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }
}

/// Berechnet eine geglättete Momentangeschwindigkeit — misst nicht bei
/// jedem einzelnen Chunk (zu ruckelig), sondern max. alle 500ms.
class _SpeedTracker {
  DateTime _lastTick = DateTime.now();
  int _lastBytes;

  _SpeedTracker(this._lastBytes);

  double? sample(int currentBytes) {
    final now = DateTime.now();
    final elapsed = now.difference(_lastTick).inMilliseconds;
    if (elapsed < 500) return null;
    final deltaBytes = currentBytes - _lastBytes;
    final speed = deltaBytes / (elapsed / 1000);
    _lastTick = now;
    _lastBytes = currentBytes;
    return speed;
  }
}
