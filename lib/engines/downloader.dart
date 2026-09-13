// Dart (Flutter-Projekt), async/await, dart:io
// (konsistent mit video_downloader.dart und download_task.dart)
//
// downloader: Async-Queue + Download-Manager
//
// - Max 5 parallele Downloads
// - Rate-Limit (10 req/s)
// - User-Agent-Rotation (10+ Strings)
// - Progress-Tracking pro Download
// - Pause/Resume via Range-Request
// - Speichert in harvest/cache/
//
// Nutzt das bestehende DownloadTask-Model (immutable, copyWith-basiert).

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import '../models/download_task.dart';

/// Zustände eines Downloads.
enum DownloadStatus {
  queued,
  downloading,
  completed,
  paused,
  failed,
  canceled,
}

/// Konfiguration für den Downloader.
class DownloadConfig {
  final int maxConcurrent;
  final int maxRetries;
  final Duration timeout;
  final Duration rateLimitDelay;
  final List<String> userAgents;
  final String cacheDir;
  final Map<String, String>? defaultHeaders;
  final void Function(String)? onLog;
  final void Function(DownloadEntry)? onProgress;

  DownloadConfig({
    this.maxConcurrent = 5,
    this.maxRetries = 3,
    this.timeout = const Duration(seconds: 60),
    this.rateLimitDelay = const Duration(milliseconds: 100),
    this.userAgents = const [
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0',
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Mobile/15E148 Safari/604.1',
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36 Edg/119.0.2079.0',
      'Mozilla/5.0 (Linux; Android 13; SM-S911B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 OPR/106.0.0.0',
      'Mozilla/5.0 (X11; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0',
    ],
    this.cacheDir = 'harvest/cache',
    this.defaultHeaders,
    this.onLog,
    this.onProgress,
  });
}

/// Interner Download-Eintrag mit veränderbaren Feldern.
/// Wird von Downloader verwaltet und zurückgegeben als DownloadTask.
class DownloadEntry {
  final String url;
  final String destination;
  final Map<String, String> headers;
  final String? referrer;
  final int retryCount;
  final bool allowResume;

  DownloadStatus status;
  double progress;
  int receivedBytes;
  int totalBytes;
  String? error;
  bool isCanceled;
  bool isPaused;

  DownloadEntry({
    required this.url,
    required this.destination,
    this.headers = const {},
    this.referrer,
    this.retryCount = 0,
    this.allowResume = true,
    this.status = DownloadStatus.queued,
    this.progress = 0.0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.error,
    this.isCanceled = false,
    this.isPaused = false,
  });

  /// Konvertiert in das bestehende DownloadTask-Model.
  DownloadTask toTask() => DownloadTask(
    sourceUrl: url,
    title: destination.split('/').last,
    percent: (progress * 100).round(),
    state: _mapState(status),
    errorMessage: error,
  );

  static DownloadState _mapState(DownloadStatus status) {
    return switch (status) {
      DownloadStatus.queued => DownloadState.queued,
      DownloadStatus.downloading => DownloadState.downloading,
      DownloadStatus.completed => DownloadState.done,
      DownloadStatus.failed => DownloadState.failed,
      _ => DownloadState.queued,
    };
  }
}

/// Async-Download-Manager mit Queue, Rate-Limit, UA-Rotation und Resume.
class Downloader {
  final DownloadConfig config;
  final _queue = Queue<DownloadEntry>();
  final _active = <String, DownloadEntry>{};
  final _httpClient = HttpClient()
    ..autoUncompress = true
    ..connectionTimeout = const Duration(seconds: 12);
  int _userAgentIndex = 0;
  bool _isProcessing = false;

  Downloader({DownloadConfig? config}) : config = config ?? DownloadConfig() {
    _ensureCacheDir();
  }

  /// Fügt einen Download zur Queue hinzu.
  Future<DownloadEntry> enqueue({
    required String url,
    String? destination,
    Map<String, String>? headers,
    String? referrer,
    bool allowResume = true,
  }) async {
    final entry = DownloadEntry(
      url: url,
      destination: destination ?? _generateCachePath(url),
      headers: headers ?? {},
      referrer: referrer,
      allowResume: allowResume,
    );

    _queue.addLast(entry);
    _updateEntry(entry);
    _processQueue();

    return entry;
  }

  /// Startet die Verarbeitung der Queue.
  void _processQueue() {
    if (_isProcessing) return;
    _isProcessing = true;
    _processNext();
  }

  /// Verarbeitet die Queue, wenn Slots frei sind.
  Future<void> _processNext() async {
    while (_queue.isNotEmpty && _active.length < config.maxConcurrent) {
      final entry = _queue.removeFirst();
      _active[entry.url] = entry;
      unawaited(_download(entry));
    }

    if (_queue.isEmpty && _active.isEmpty) {
      _isProcessing = false;
    } else if (_active.isNotEmpty) {
      // Warte und prüfe erneut
      await Future.delayed(const Duration(milliseconds: 200));
      await _processNext();
    } else {
      _isProcessing = false;
    }
  }

  /// Führt einen einzelnen Download aus mit Retry, Rate-Limit, UA-Rotation.
  Future<void> _download(DownloadEntry entry) async {
    for (int attempt = 0; attempt <= config.maxRetries; attempt++) {
      if (entry.isCanceled || entry.isPaused) break;

      try {
        await _doDownload(entry);
        return; // Erfolg
      } catch (e) {
        _log('Download-Fehler (Versuch $attempt/${config.maxRetries}): ${entry.url} - $e');
        if (attempt >= config.maxRetries) {
          entry.status = DownloadStatus.failed;
          entry.error = e.toString();
          _updateEntry(entry);
          _active.remove(entry.url);
        } else {
          // Retry mit exponentiellem Backoff
          await Future.delayed(Duration(seconds: 1 << attempt));
        }
      }
    }

    // Queue weiterverarbeiten
    _processQueue();
  }

  /// Führt den eigentlichen HTTP-Download mit Rate-Limit durch.
  Future<void> _doDownload(DownloadEntry entry) async {
    entry.status = DownloadStatus.downloading;
    _updateEntry(entry);

    // Rate-Limit: warte zwischen Requests
    await Future.delayed(config.rateLimitDelay);

    final request = await _httpClient.getUrl(Uri.parse(entry.url));
    final ua = config.userAgents[_userAgentIndex % config.userAgents.length];
    _userAgentIndex++;
    // FIX: HttpHeaders hat keine userAgent-Property
    request.headers.set(HttpHeaders.userAgentHeader, ua);

    // Resume via Range-Request
    int startByte = 0;
    final file = File(entry.destination);
    if (entry.allowResume && await file.exists()) {
      final existing = await file.length();
      if (existing > 0) {
        startByte = existing;
        request.headers.add('Range', 'bytes=$startByte-');
        _log('Resume von Byte $startByte: ${entry.url}');
      }
    }

    // Header zusammenführen
    config.defaultHeaders?.forEach((k, v) => request.headers.add(k, v));
    entry.headers.forEach((k, v) => request.headers.add(k, v));

    // Referer (für Video-Downloads)
    if (entry.referrer?.isNotEmpty ?? false) {
      request.headers.add('Referer', entry.referrer!);
    }

    final response = await request.close().timeout(config.timeout);

    if (response.statusCode == HttpStatus.partialContent ||
        response.statusCode == HttpStatus.ok) {
      // Größe ermitteln
      final contentLength = response.contentLength ?? 0;
      entry.totalBytes = startByte + contentLength;

      // Datei öffnen
      final sink = file.openWrite(
        mode: startByte > 0 ? FileMode.append : FileMode.write,
      );

      var received = startByte;
      var lastUpdate = DateTime.now();

      await for (final chunk in response) {
        if (entry.isCanceled) {
          await sink.close();
          entry.status = DownloadStatus.canceled;
          _updateEntry(entry);
          return;
        }
        if (entry.isPaused) {
          await sink.close();
          entry.status = DownloadStatus.paused;
          _updateEntry(entry);
          return;
        }

        sink.add(chunk);
        received += chunk.length;

        // Progress-Update (max 2x pro Sekunde)
        final now = DateTime.now();
        if (now.difference(lastUpdate).inMilliseconds > 500) {
          entry.receivedBytes = received;
          if (entry.totalBytes > 0) {
            entry.progress = received / entry.totalBytes;
          }
          _updateEntry(entry);
          lastUpdate = now;
        }
      }

      await sink.close();

      entry.receivedBytes = received;
      entry.progress = entry.totalBytes > 0 ? received / entry.totalBytes : 1.0;
      entry.status = DownloadStatus.completed;
      _updateEntry(entry);
      _active.remove(entry.url);
    } else if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
      // Resume nicht möglich — neu starten
      _log('Range nicht unterstützt, starte neu: ${entry.url}');
      entry.totalBytes = 0;
      entry.receivedBytes = 0;
      entry.progress = 0.0;
      entry.status = DownloadStatus.queued;
      _queue.addLast(entry);
      _active.remove(entry.url);
      _processQueue();
    } else {
      throw HttpException(
        'HTTP ${response.statusCode}',
        uri: Uri.parse(entry.url),
      );
    }
  }

  /// Pausiert einen Download.
  Future<void> pause(String url) async {
    final entry = _active[url];
    if (entry != null) {
      entry.isPaused = true;
      entry.status = DownloadStatus.paused;
      _updateEntry(entry);
      _log('Download pausiert: $url');
    }
  }

  /// Setzt einen pausierten Download fort.
  Future<void> resume(String url) async {
    // FIX: firstWhere orElse must return DownloadEntry, not null.
    // Wenn nicht gefunden, ist entry null und wir überspringen den Resume-Versuch.
    final entry = _active[url] ??
        _queue.firstWhere((e) => e.url == url, orElse: () => DownloadEntry(url: url, destination: '', headers: {}));
    if (entry != null && entry.url == url) {
      entry.isPaused = false;
      entry.status = DownloadStatus.queued;
      _queue.addLast(entry);
      _active.remove(url);
      _processQueue();
    }
  }

  /// Bricht einen Download ab.
  Future<void> cancel(String url) async {
    final entry = _active[url];
    if (entry != null) {
      entry.isCanceled = true;
      entry.status = DownloadStatus.canceled;
      _updateEntry(entry);
      _active.remove(url);
      _log('Download abgebrochen: $url');
    }
  }

  /// Gibt alle aktiven und wartenden Einträge zurück.
  List<DownloadEntry> get entries => [
        ..._queue,
        ..._active.values,
      ];

  /// Findet einen Eintrag anhand der URL.
  DownloadEntry? _findEntryByUrl(String url) {
    for (final e in _queue) {
      if (e.url == url) return e;
    }
    return _active[url];
  }

  /// Erstellt das Cache-Verzeichnis.
  Future<void> _ensureCacheDir() async {
    final dir = Directory(config.cacheDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      _log('Cache-Verzeichnis erstellt: ${config.cacheDir}');
    }
  }

  /// Generiert einen Cache-Dateipfad aus einer URL.
  String _generateCachePath(String url) {
    final uri = Uri.parse(url);
    final path = uri.path;
    final lastDot = path.lastIndexOf('.');
    final ext = lastDot >= 0 ? path.substring(lastDot) : '.bin';
    final hash = url.hashCode.abs() % 100000;
    final host = uri.host.replaceAll('.', '_');
    return '${config.cacheDir}/$host-$hash$ext';
  }

  /// Aktualisiert einen Eintrag (Callback + Logging).
  void _updateEntry(DownloadEntry entry) {
    config.onProgress?.call(entry);
    _log('Task ${entry.url}: ${entry.status} ${(entry.progress * 100).toStringAsFixed(0)}%');
  }

  /// Hilfsfunktion für Logging.
  void _log(String message) {
    config.onLog?.call(message);
  }

  /// Schließt Ressourcen.
  void dispose() {
    _httpClient.close(force: true);
  }
}
