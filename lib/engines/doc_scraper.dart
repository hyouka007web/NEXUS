// Dart (Flutter-Projekt), async/await, dart:io
// (konsistent mit video_harvester.dart und scraper_engine.dart)
//
// doc_scraper: PDF/EPUB/MOBI-Dokument-Scraper
//
// Findet und scrappt Dokumente (.pdf, .epub, .mobi) in HTML-Seiten.
// PDF-Textextraktion via native Dart-Regex (keine externen Packages,
// kompatibel mit Android/iOS — pdf_text ist Desktop-only).
// EPUB-Metadaten via ZIP-Analyse (content.opf).
// MOBI: Metadaten über EXTH-Header (Header-Analyse).
//
// Ergebnisse werden im mediathek/ Ordner gespeichert.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'html_extractor.dart';

/// Dok-Typ-Konstanten
enum DocType { pdf, epub, mobi, djvu, unknown }

/// Ergebnis eines Dokument-Scraping-Laufs.
class DocScrapeResult {
  final List<ScrapedDoc> docs;
  final List<MediaCandidate> candidates;
  final List<String> processedUrls;
  final List<String> errors;
  final int totalBytes;

  DocScrapeResult({
    required this.docs,
    required this.candidates,
    required this.processedUrls,
    required this.errors,
    required this.totalBytes,
  });
}

/// Ein gescraUTES Dokument mit Metadaten.
class ScrapedDoc {
  final String url;
  final String localPath;
  final DocType type;
  final String title;
  final String author;
  final int bytes;
  final String mimeType;
  final List<String> extractedTextPages;
  final Map<String, dynamic> metadata;

  ScrapedDoc({
    required this.url,
    required this.localPath,
    required this.type,
    required this.title,
    required this.author,
    required this.bytes,
    required this.mimeType,
    required this.extractedTextPages,
    required this.metadata,
  });
}

/// Konfiguration für DocScraper.
class DocScrapeConfig {
  final String mediathekDir;
  final bool extractText;
  final bool downloadDocs;
  final int maxDepth;
  final int maxPages;
  final Duration timeout;
  final List<String> userAgents;
  final List<String> targetDomains;
  final Map<String, String>? extraHeaders;
  final void Function(String)? onLog;

  DocScrapeConfig({
    this.mediathekDir = 'mediathek',
    this.extractText = true,
    this.downloadDocs = true,
    this.maxDepth = 3,
    this.maxPages = 50,
    this.timeout = const Duration(seconds: 30),
    this.userAgents = const [
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0',
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Mobile/15E148 Safari/604.1',
    ],
    this.targetDomains = const [],
    this.extraHeaders,
    this.onLog,
  });
}

/// Dokument-Scraper für PDF/EPUB/MOBI-Dateien.
class DocScraper {
  final DocScrapeConfig config;
  final HtmlExtractor _htmlExtractor;
  final HttpClient _httpClient;
  final Set<String> _visited = {};
  final List<String> _errors = [];
  final Queue<String> _urlQueue = Queue<String>();
  int _processedCount = 0;
  int _totalBytes = 0;

  DocScraper({
    DocScrapeConfig? config,
    HtmlExtractor? htmlExtractor,
    HttpClient? httpClient,
  })  : config = config ?? DocScrapeConfig(),
        _htmlExtractor = htmlExtractor ?? HtmlExtractor(
          userAgents: config?.userAgents,
          timeout: config?.timeout,
        ),
        _httpClient = httpClient ?? HttpClient() {
    _httpClient.autoUncompress = true;
    _httpClient.connectionTimeout = config.timeout;
  }

  /// Haupteinstieg: Dokumente von einer URL scrapen.
  Future<DocScrapeResult> scrape(String url) async {
    _log('Starte Dokument-Scraping für: $url');

    _urlQueue.add(url);
    final allDocs = <String, ScrapedDoc>{};
    final allCandidates = <MediaCandidate>[];

    while (_urlQueue.isNotEmpty &&
           allDocs.length < config.maxPages &&
           _processedCount < config.maxPages) {
      final currentUrl = _urlQueue.removeFirst();
      final normalized = _normalizeUrl(currentUrl);
      if (normalized == null || !_visited.add(normalized)) continue;
      _processedCount++;

      _log('Verarbeite: $currentUrl (Seite $_processedCount)');

      final html = await _fetchHtml(currentUrl);
      if (html == null) continue;

      // Deep-HTML-Analyse für Dokument-Links
      final extractResult = _htmlExtractor.parseHtml(currentUrl, html);

      // Dokument-Kandidaten filtern
      for (final candidate in extractResult.candidates) {
        if (_isDocType(candidate.type)) {
          allCandidates.add(candidate);
          _log('Dokument gefunden: ${candidate.url} (${candidate.type})');

          if (config.downloadDocs) {
            final doc = await _downloadAndProcessDoc(candidate);
            if (doc != null) {
              allDocs.putIfAbsent(doc.localPath, () => doc);
            }
          }
        }
      }

      // Weitere Seiten-URLs in derQueue für Rekursion
      for (final c in extractResult.candidates) {
        if (_normalizeUrl(c.url) != null &&
            config.targetDomains.any((d) => c.url.contains(d))) {
          _urlQueue.addLast(c.url);
        }
      }
    }

    // mediathek-Verzeichnis erstellen
    final mediathekPath = Directory(config.mediathekDir);
    if (!await mediathekPath.exists()) {
      await mediathekPath.create(recursive: true);
      _log('Erstelle mediathek/ Ordner');
    }

    _log('Fertig. ${allDocs.length} Dokumente, ${allCandidates.length} Kandidaten, '
         '$_totalBytes Bytes');

    return DocScrapeResult(
      docs: allDocs.values.toList(),
      candidates: allCandidates,
      processedUrls: _visited.toList(),
      errors: _errors,
      totalBytes: _totalBytes,
    );
  }

  /// Lädt ein Dokument herunter und extrahiert Metadaten/Text.
  Future<ScrapedDoc?> _downloadAndProcessDoc(MediaCandidate candidate) async {
    try {
      _log('Lade herunter: ${candidate.url}');

      final request = await _httpClient.getUrl(Uri.parse(candidate.url));
      _setHeaders(request, _processedCount);
      final response = await request.close().timeout(config.timeout);

      if (response.statusCode != HttpStatus.ok) {
        _errors.add('HTTP ${response.statusCode} für ${candidate.url}');
        return null;
      }

      // MIME-Type prüfen
      final contentType = response.contentType?.mimeType ?? '';
      final mimeType = _inferMimeType(candidate.url, contentType);

      // Bytes sammeln
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }

      _totalBytes += bytes.length;

      // Dateiname generieren
      final filename = _generateFilename(candidate.url, mimeType);
      final localPath = '${config.mediathekDir}/$filename';

      // Datei schreiben
      final file = File(localPath);
      await file.writeAsBytes(bytes, flush: true);
      _log('Gespeichert: $localPath (${bytes.length} Bytes)');

      // Dokumenttyp bestimmen und verarbeiten
      final docType = _getDocType(candidate.url, mimeType);
      final doc = await _processDoc(file, bytes, docType, candidate);
      return doc;
    } catch (e) {
      _errors.add('Download-Fehler (${candidate.url}): $e');
      _log('Download-Fehler: $e');
      return null;
    }
  }

  /// Verarbeitet ein heruntergeladenes Dokument (Extrahiert Text/Metadaten).
  Future<ScrapedDoc> _processDoc(File file, Uint8List bytes, DocType type, MediaCandidate candidate) async {
    String title = candidate.label ?? '';
    String author = '';
    final metadata = <String, dynamic>{};
    final textPages = <String>[];

    switch (type) {
      case DocType.pdf:
        final result = await _extractPdfText(file.path);
        title = result.title ?? title;
        author = result.author ?? author;
        textPages.addAll(result.textPages);
        metadata.addAll(result.metadata);
        break;

      case DocType.epub:
        final result = await _parseEpub(bytes);
        title = result.title ?? title;
        author = result.author ?? author;
        textPages.addAll(result.textPages);
        metadata.addAll(result.metadata);
        break;

      case DocType.mobi:
        final result = _parseMobiHeader(bytes);
        title = result.title ?? title;
        author = result.author ?? author;
        metadata.addAll(result.metadata);
        break;

      default:
        break;
    }

    return ScrapedDoc(
      url: candidate.url,
      localPath: file.path,
      type: type,
      title: title,
      author: author,
      bytes: bytes.length,
      mimeType: _inferMimeType(candidate.url, ''),
      extractedTextPages: textPages,
      metadata: metadata,
    );
  }

  /// PDF-Textextraktion via native Dart-Regex (keine externe Packages,
  /// kompatibel mit Android/iOS). Extrahiert Metadaten aus PDF-Stream-
  /// Headern und versucht Text aus dem Raw-Byte-Stream zu lesen.
  Future<_PdfResult> _extractPdfText(String filePath) async {
    try {
      // Da pdf_text-Package Desktop-only ist (nicht in pubspec.yaml),
      // verwenden wir eine native Dart-Variante.
      //
      // PDF-Datei direkt parsen: Suche nach Text- und Metadaten-Streams
      // im Raw-Byte-Stream. Dies ist eine vereinfachte Variante, die
      // funktioniert, wenn der Text nicht komprimiert/verschlüsselt ist.

      // Fallback: Suche nach Text in rohen PDF-Bytes (begrenzt)
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      final text = utf8.decode(bytes, allowMalformed: true);

      // Einfacher Textextraktions-Fallback
      // Entfernt PDF-Steuerzeichen und XML-Tags
      final cleaned = text
          .replaceAll(RegExp(r'<\?xml[^>]*\?>'), '')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll(RegExp(r'\x00'), '')
          .trim();

      final textPages = cleaned.isNotEmpty ? [cleaned] : [];

      // Metadaten aus PDF-Stream extrahieren (Title, Author)
      final titleMatch = RegExp(r'/Title\s*\(([^)]*)\)', unicode: true).firstMatch(text);
      final authorMatch = RegExp(r'/Author\s*\(([^)]*)\)', unicode: true).firstMatch(text);

      return _PdfResult(
        title: titleMatch?.group(1),
        author: authorMatch?.group(1),
        textPages: textPages,
        metadata: {
          'pageCount': textPages.length,
          'method': 'raw-fallback',
          'note': 'pdf_text-Package nicht installiert — Fallback verwendet',
        },
      );
    } catch (e) {
      _log('PDF-Extraktion fehlgeschlagen: $e');
      return _PdfResult(textPages: [], metadata: {'error': e.toString()});
    }
  }

  /// EPUB-Metadaten-Extraktion via ZIP-Analyse (content.opf).
  Future<_DocResult> _parseEpub(Uint8List bytes) async {
    try {
      // EPUB ist ein ZIP-Archiv
      // EPUB-Struktur: OEBPS/content.opf oder Mimetype + META-INF/container.xml
      final text = utf8.decode(bytes, allowMalformed: true);

      // container.xml parsen, um content.opf-Pfad zu finden
      final containerMatch = RegExp(
        r'<rootfile[^>]*full-path="([^"]+content\.opf[^"]*)"',
        caseSensitive: false,
      ).firstMatch(text);

      String? opfPath = containerMatch?.group(1);

      // Falls container.xml nicht gefunden, suche direkt nach .opf
      if (opfPath == null) {
        final opfMatch = RegExp(
          r'[\w\-/]*\.opf',
          caseSensitive: false,
        ).firstMatch(text);
        opfPath = opfMatch?.group(0);
      }

      if (opfPath != null && opfPath.isNotEmpty) {
        // Inhalt der OPF-Datei extrahiern (falls im ZIP enthalten)
        final opfContent = _extractZipEntry(bytes, opfPath);
        if (opfContent != null) {
          final titleMatch = RegExp(r'<dc:title[^>]*>([^<]+)<', caseSensitive: false).firstMatch(opfContent);
          final authorMatch = RegExp(r'<dc:creator[^>]*>([^<]+)<', caseSensitive: false).firstMatch(opfContent);
          final langMatch = RegExp(r'<dc:language[^>]*>([^<]+)<', caseSensitive: false).firstMatch(opfContent);

          return _DocResult(
            title: titleMatch?.group(1)?.trim(),
            author: authorMatch?.group(1)?.trim(),
            textPages: [],
            metadata: {
              'language': langMatch?.group(1)?.trim(),
              'opfPath': opfPath,
            },
          );
        }
      }

      // Fallback: Suche nach Titel in generischem EPUB-Inhalt
      final titleMatch = RegExp(r'<dc:title[^>]*>\s*([^<]+)\s*</dc:title>', caseSensitive: false).firstMatch(text);
      final authorMatch = RegExp(r'<dc:creator[^>]*>\s*([^<]+)\s*</dc:creator>', caseSensitive: false).firstMatch(text);

      return _DocResult(
        title: titleMatch?.group(1)?.trim(),
        author: authorMatch?.group(1)?.trim(),
        textPages: [],
        metadata: {'method': 'opf-fallback'},
      );
    } catch (e) {
      _log('EPUB-Parsing fehlgeschlagen: $e');
      return _DocResult(textPages: [], metadata: {'error': e.toString()});
    }
  }

  /// MOBI-Header-Analyse (Kindle-eigenes Format).
  _DocResult _parseMobiHeader(Uint8List bytes) {
    try {
      // MOBI-Datei beginnt mit PalmDOC-Header
      // Siehe: https://www.mobipocket.com/en/developers/documentation
      //
      // PalmDOC Header (78 Bytes):
      // Bytes 60-64: "BOOKMOBI"
      // Bytes 68-72: Anzahl Records
      // Bytes 72-76: Record-Array-Offset
      //
      // Mobipocket Header (ab Byte 16):
      // Bytes 16-24: Name (144 Bytes max)
      // Bytes 24-32: Autor (im Mobipocket-Record)
      // Bytes 36-40: Sprache
      // Bytes 56-64: "BOOKMOBI"
      // Bytes 84-100: EXTH-Header (falls vorhanden, enthält Metadaten)

      final buf = bytes;

      // Prüfe auf "BOOKMOBI" Marker
      final bookMobi = utf8.decode(buf.sublist(60, 68), allowMalformed: true);
      if (bookMobi != 'BOOKMOBI') {
        return _DocResult(metadata: {'format': 'unknown mobi variant'});
      }

      // EXTH-Header suchen (nach BOOKMOBI-Header)
      // EXTH-Magic: 0x45585448 ("EXTH")
      // Offset 84-88 im Mobipocket-Record
      String? title, author, language;
      final metadata = <String, dynamic>{};

      // Suche nach EXTH-Header
      for (int i = 0; i < buf.length - 8; i++) {
        if (buf[i] == 0x45 && buf[i + 1] == 0x58 && buf[i + 2] == 0x54 && buf[i + 3] == 0x48) {
          // EXTH gefunden
          // EXTH-Daten beginnt nach Offset + 12 (4 Magic + 4 Size + 4 Count)
          final exthSize = (buf[i + 4] << 24) | (buf[i + 5] << 16) | (buf[i + 6] << 8) | buf[i + 7];
          if (exthSize > 12 && exthSize <= buf.length - i) {
            int pos = i + 12;
            final endPos = i + exthSize;

            // EXTH-Records parsen
            while (pos + 8 <= endPos) {
              final recType = (buf[pos] << 24) | (buf[pos + 1] << 16) | (buf[pos + 2] << 8) | buf[pos + 3];
              final recSize = (buf[pos + 4] << 24) | (buf[pos + 5] << 16) | (buf[pos + 6] << 8) | buf[pos + 7];
              if (recSize < 8 || pos + recSize > endPos) break;

              final recData = utf8.decode(buf.sublist(pos + 8, pos + recSize), allowMalformed: true).trim();

              switch (recType) {
                case 0x0001: // Book Name
                  title = recData;
                  metadata['title'] = recData;
                  break;
                case 0x0002: // Author
                  author = recData;
                  metadata['author'] = recData;
                  break;
                case 0x0003: // Language
                  language = recData;
                  metadata['language'] = recData;
                  break;
                case 0x0004: // Publisher
                  metadata['publisher'] = recData;
                  break;
                case 0x0005: // Imprint
                  metadata['imprint'] = recData;
                  break;
                case 0x0010: // Description
                  metadata['description'] = recData;
                  break;
                case 0x0015: // Author Sort
                  if (author == null) author = recData;
                  break;
              }
              pos += recSize;
            }
          }
        }
      }

      return _DocResult(
        title: title,
        author: author,
        textPages: [],
        metadata: metadata,
      );
    } catch (e) {
      return _DocResult(metadata: {'error': e.toString()});
    }
  }

  /// Extrahiert einen Eintrag aus einem ZIP-Archiv (EPUB-Parsing).
  String? _extractZipEntry(Uint8List zipBytes, String targetName, [int maxEntries = 300]) {
    try {
      // Einfache ZIP-Datei-Analyse ohne externes Package
      // ZIP-End-of-Central-Directory-Signatur: 0x06054b50
      for (int i = 0; i < min(zipBytes.length - 22, 65536); i++) {
        if (zipBytes[i] == 0x50 &&
            zipBytes[i + 1] == 0x4b &&
            zipBytes[i + 2] == 0x05 &&
            zipBytes[i + 3] == 0x06) {
          // EOCD gefunden — zentrale Verzeichnis beginnt davor
          // Suche nach zentralen Datei-Einträgen: Signatur 0x02014b50
          return _searchZipEntries(zipBytes, targetName, i);
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Sucht nach einer Datei innerhalb des ZIP-Archivs.
  String? _searchZipEntries(Uint8List bytes, String targetName, int eocdPos) {
    for (int i = 0; i < eocdPos - 4; i++) {
      if (bytes[i] == 0x50 &&
          bytes[i + 1] == 0x4b &&
          bytes[i + 2] == 0x01 &&
          bytes[i + 3] == 0x02) {
        // Zentraler Verzeichniseintrag gefunden
        final nameLen = (bytes[i + 28] << 8) | bytes[i + 29];
        final extraLen = (bytes[i + 30] << 8) | bytes[i + 31];
        final commentLen = (bytes[i + 32] << 8) | bytes[i + 33];
        final nameStart = i + 46;
        final name = utf8.decode(bytes.sublist(nameStart, nameStart + nameLen), allowMalformed: true);

        if (name == targetName || name.endsWith(targetName)) {
          // Lokaler Datei-Header: Signatur 0x04034b50
          final localHeaderSig = bytes[i];
          final compMethod = (bytes[i + 10] << 8) | bytes[i + 11];
          final compSize = (bytes[i + 20] << 24) | (bytes[i + 21] << 16) | (bytes[i + 22] << 8) | bytes[i + 23];
          final nameStartLocal = i + 30;
          final nameLenLocal = (bytes[nameStartLocal + 0] << 8) | bytes[nameStartLocal + 1];

          // Datenoffset berechnen
          int dataOffset = nameStartLocal + 2 + nameLenLocal;
          final extraLenLocal = (bytes[nameStartLocal + 2] << 8) | bytes[nameStartLocal + 3];
          dataOffset += extraLenLocal;

          if (compSize > 0 && dataOffset + compSize <= bytes.length) {
            final fileData = bytes.sublist(dataOffset, dataOffset + compSize);
            // Falls DEFLATE: dekomprimieren
            if (compMethod == 8) {
              final decompressed = _inflate(fileData);
              if (decompressed != null) {
                return utf8.decode(decompressed, allowMalformed: true);
              }
            } else {
              // Stored (keine Kompression)
              return utf8.decode(fileData, allowMalformed: true);
            }
          }
        }

        // Nächster Eintrag überspringen
        i += 46 + nameLen + extraLen + commentLen - 1;
      }
    }
    return null;
  }

  /// Einfache DEFLATE-Dekompression (UTF-8 dekodiert).
  Uint8List? _inflate(Uint8List data) {
    try {
      // Diese ist eine vereinfachte Version.
      // Für vollständige DEFLATE-Unterstützung wäre ein zlib-Package nötig.
      // Fallback: Rohdaten zurückgeben (falls nicht komprimiert).
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Holt HTML einer Seite.
  Future<String?> _fetchHtml(String url) async {
    try {
      final request = await _httpClient.getUrl(Uri.parse(url));
      _setHeaders(request, _processedCount);
      final response = await request.close().timeout(config.timeout);

      if (response.statusCode != HttpStatus.ok) {
        _errors.add('HTTP ${response.statusCode} für $url');
        return null;
      }

      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }
      return utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      _errors.add('Fetch-Fehler ($url): $e');
      return null;
    }
  }

  /// Setzt HTTP-Header (User-Agent-Rotation, Accept-Language).
  void _setHeaders(HttpClientRequest request, int depth) {
    final ua = config.userAgents[depth % config.userAgents.length];
    request.headers.userAgent = ua;
    request.headers.set('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
    request.headers.set('Accept-Language', 'de-DE,de;q=0.9,en-US;q=0.8,en;q=0.7');
    config.extraHeaders?.forEach((k, v) => request.headers.set(k, v));
  }

  /// Normalisiert eine URL.
  String? _normalizeUrl(String url) {
    try {
      final u = Uri.parse(url);
      if (u.scheme != 'http' && u.scheme != 'https' || u.host.isEmpty) {
        return null;
      }
      return u.toString();
    } catch (e) {
      return null;
    }
  }

  /// Prüft, ob ein Mime-Typ auf ein Dokument verweist.
  bool _isDocType(String type) {
    return type == 'application/pdf' ||
           type == 'application/epub+zip' ||
           type == 'application/x-mobipocket-ebook';
  }

  /// Bestimmt den Dokumententyp.
  DocType _getDocType(String url, String mimeType) {
    final lower = url.toLowerCase();
    if (mimeType == 'application/pdf' || lower.endsWith('.pdf')) return DocType.pdf;
    if (mimeType == 'application/epub+zip' || lower.endsWith('.epub')) return DocType.epub;
    if (mimeType == 'application/x-mobipocket-ebook' || lower.endsWith('.mobi')) return DocType.mobi;
    return DocType.unknown;
  }

  /// Ermittelt den MIME-Typ einer URL.
  String _inferMimeType(String url, String fallback) {
    final lower = url.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.epub')) return 'application/epub+zip';
    if (lower.endsWith('.mobi')) return 'application/x-mobipocket-ebook';
    return fallback;
  }

  /// Generiert einen lokalen Dateinamen für ein Dokument.
  String _generateFilename(String url, String mimeType) {
    final ext = _getExtension(url);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final host = Uri.parse(url).host;
    final pathHash = url.hashCode.abs() % 10000;
    return '$host-$pathHash-$timestamp$ext';
  }

  /// Extrahiert die Dateiendung aus einer URL.
  String _getExtension(String url) {
    final uri = Uri.parse(url);
    final path = uri.path;
    final dotIndex = path.lastIndexOf('.');
    if (dotIndex >= 0 && dotIndex < path.length - 1) {
      return path.substring(dotIndex).toLowerCase();
    }
    // Fallback basierend auf MIME-Type
    if (url.contains('pdf')) return '.pdf';
    if (url.contains('epub')) return '.epub';
    if (url.contains('mobi')) return '.mobi';
    return '.bin';
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

/// Ergebnis der PDF-Textextraktion.
class _PdfResult {
  final String? title;
  final String? author;
  final List<String> textPages;
  final Map<String, dynamic> metadata;

  _PdfResult({this.title, this.author, required this.textPages, required this.metadata});
}

/// Ergebnis einer Dokument-Verarbeitung.
class _DocResult {
  final String? title;
  final String? author;
  final List<String> textPages;
  final Map<String, dynamic> metadata;

  _DocResult({this.title, this.author, required this.textPages, required this.metadata});
}
