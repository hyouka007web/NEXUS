import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nexus/models/download_entry.dart';
import 'package:nexus/models/harvested_media.dart';

/// VideoDownloader: verwaltet alle laufenden/abgeschlossenen Downloads.
/// Als ChangeNotifier, damit die Mediathek live Fortschritt anzeigen kann.
/// Speichert in einem App-eigenen "NEXUS"-Ordner im externen Speicher
/// (kein Laufzeit-Permission-Prompt auf Android 10+ nötig).
class VideoDownloader extends ChangeNotifier {
  static final VideoDownloader _instance = VideoDownloader._internal();
  factory VideoDownloader() => _instance;
  VideoDownloader._internal();

  final List<DownloadEntry> downloads = [];
  final Map<String, StreamSubscription> _activeSubs = {};
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
    if (type == 'hls' || type == 'dash') return 'ts'; // Rohsegment/Stream-Mitschnitt
    return 'mp4';
  }

  /// Startet einen Download für eine ausgewählte Qualitätsstufe.
  Future<DownloadEntry> download(MediaVariant variant, {required String title, required String type}) async {
    _counter++;
    final id = 'dl_${DateTime.now().millisecondsSinceEpoch}_$_counter';
    final safeTitle = title.trim().isEmpty ? 'nexus_media_$_counter' : title.trim();
    final ext = _extensionFor(type, variant.url);

    final entry = DownloadEntry(
      id: id,
      url: variant.url,
      title: '$safeTitle${variant.label.isNotEmpty ? " [${variant.label}]" : ""}',
      type: type,
      status: DownloadStatus.downloading,
    );
    downloads.insert(0, entry);
    notifyListeners();

    try {
      final dir = await _targetDir();
      final filename = '${entry.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.$ext';
      final file = File('${dir.path}/$filename');
      final sink = file.openWrite();

      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(variant.url));
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        entry.status = DownloadStatus.failed;
        entry.error = 'HTTP ${response.statusCode}';
        notifyListeners();
        await sink.close();
        return entry;
      }

      final contentLength = response.contentLength;
      entry.totalBytes = contentLength;
      entry.progress = contentLength > 0 ? 0.0 : -1;
      var received = 0;

      final completer = Completer<void>();
      final sub = response.listen(
        (chunk) {
          sink.add(chunk);
          received += chunk.length;
          entry.receivedBytes = received;
          if (contentLength > 0) entry.progress = received / contentLength;
          notifyListeners();
        },
        onDone: () async {
          await sink.flush();
          await sink.close();
          entry.status = DownloadStatus.completed;
          entry.localPath = file.path;
          entry.progress = 1.0;
          notifyListeners();
          _activeSubs.remove(id);
          if (!completer.isCompleted) completer.complete();
        },
        onError: (e) async {
          entry.status = DownloadStatus.failed;
          entry.error = e.toString();
          notifyListeners();
          await sink.close();
          _activeSubs.remove(id);
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );
      _activeSubs[id] = sub;
      await completer.future;
    } catch (e) {
      entry.status = DownloadStatus.failed;
      entry.error = e.toString();
      notifyListeners();
    }
    return entry;
  }

  void cancel(String id) {
    _activeSubs[id]?.cancel();
    _activeSubs.remove(id);
    final entry = downloads.firstWhere((d) => d.id == id, orElse: () => downloads.first);
    if (entry.id == id) {
      entry.status = DownloadStatus.canceled;
      notifyListeners();
    }
  }

  void remove(String id) {
    downloads.removeWhere((d) => d.id == id);
    notifyListeners();
  }
}
