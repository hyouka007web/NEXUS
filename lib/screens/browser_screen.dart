import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../engines/doc_scraper.dart';
import '../engines/harvest_logger.dart';
import '../engines/html_extractor.dart';
import '../engines/network_sniffer.dart';
import '../engines/scraper_engine.dart';
import '../engines/video_downloader.dart';
import '../engines/video_harvester.dart';
import '../engines/video_harvester_engine.dart';
import '../models/block_event.dart';
import '../models/download_task.dart';
import '../models/harvested_video.dart';
import '../models/quick_link.dart';
import '../models/scrape_result.dart';
import '../models/tab_model.dart';
import '../state/batch_download_manager.dart';
import '../state/dev_settings.dart';
import '../state/download_repository.dart';
import '../state/tab_manager.dart';
import '../state/pane_manager.dart';
import '../state/workspace_manager.dart';
import '../state/keybinding_engine.dart';
import '../state/command_registry.dart';
import '../state/theme_config.dart';
import '../ui/command_palette.dart';
import '../ui/terminal_pane.dart';
import '../theme/nexus_theme.dart';
import 'devtools_screen.dart';
import 'harvest_debug_panel.dart';
import 'harvest_test_cases_screen.dart';
import 'downloads_panel.dart';
import 'mediathek_screen.dart';
import 'start_page.dart';

/// `compute()` verlangt eine Top-Level- oder statische Funktion (kein
/// Closure, keine Instanzmethode) — sie wird in einen eigenen Isolate
/// verschickt und muss daher eigenständig aufrufbar sein. Damit läuft die
/// regex-lastige Auswertung von potenziell großem HTML (Scraper,
/// Netzwerk-Crawl des Harvesters) nicht mehr auf dem UI-Isolate und kann
/// die Bildwiederholung nicht mehr blockieren — siehe Performance-Hinweis
/// weiter unten in dieser Datei.
/// Top-Level-Funktion für compute()-Isolate:
/// Führt Deep-Analyse aus (HTML-Extractor + Video-Harvester + Doc-Scraper).
Future<DeepScrapeResult> _deepScrapeIsolate(String url) async {
  return await ScraperEngine.deepScrape(
    url,
    useYtDlp: true,
    mediathekDir: 'mediathek',
  );
}

Future<ScrapeResult> _scrapeIsolate(String url) => ScraperEngine.scrape(url);

Future<List<HarvestedVideo>> _harvestIsolate(String url) =>
    VideoHarvesterEngine.harvest(url);

/// Neuer Isolates-basierter Deep-Harvest:
/// Verwendet VideoHarvester (rekursive iFrames + yt-dlp + Deep-HTML).
Future<HarvestResult> _deepHarvestIsolate(String url) async {
  final harvester = VideoHarvester(
    config: HarvestConfig(
      useYtDlp: true,
      maxDepth: 3,
      timeout: const Duration(seconds: 30),
      onLog: (msg) => print('[VideoHarvester] $msg'),
    ),
  );
  return await harvester.harvest(url);
}

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final _tabManager = TabManager();
  final _paneManager = PaneManager();
  final _addressFocus = FocusNode();
  final _urlController = TextEditingController();
  bool _sidebarExpanded = false;
  bool _frameless = false;
  bool _revealChrome = false;
  bool _restoring = true;
  String? _notification;
  VoidCallback? _notificationAction;
  String? _notificationActionLabel;

  @override
  void initState() {
    super.initState();
    _tabManager.addListener(_onTabManagerChanged);
    _paneManager.addListener(_onPaneChanged);
    _restoreTabs();
  }

  Future<void> _restoreTabs() async {
    await Future.wait([_tabManager.restore(), DevSettings.instance.restore(), WorkspaceManager.instance.restore(), KeybindingEngine.instance.restore()]);
    _paneManager.ensureActive();
    for (final t in _tabManager.tabs) { if (!_paneManager.leaves.any((p) => p.tabIds.contains(t.id))) { _paneManager.leaves.first.tabIds.add(t.id); _paneManager.leaves.first.activeTabId ??= t.id; } }
    _syncUrlField();
    if (mounted) setState(() => _restoring = false);
  }

  @override
  void dispose() {
    _tabManager.removeListener(_onTabManagerChanged);
    _paneManager.removeListener(_onPaneChanged);
    _urlController.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  void _onPaneChanged() {
    _syncUrlField();
    if (mounted) setState(() {});
  }

  void _onTabManagerChanged() {
    _syncUrlField();
    final event = _tabManager.lastBlockEvent;
    if (event != null) {
      _showNotification(
        event.label,
        actionLabel: 'ÖFFNEN',
        onAction: () => _forceOpen(event),
      );
      // Einmal konsumiert, damit dasselbe Ereignis nicht bei jedem
      // weiteren notifyListeners() erneut das Panel aufreißt.
      _tabManager.lastBlockEvent = null;
    }
    setState(() {});
  }

  void _syncUrlField() {
    _paneManager.ensureActive();
    final paneTabId = _paneManager.activePane.activeTabId;
    final tab = paneTabId == null ? _tabManager.activeTab : _tabManager.tabs.where((t) => t.id == paneTabId).cast<NexusTab?>().firstWhere((t) => t != null, orElse: () => _tabManager.activeTab);
    if (tab == null) return;
    final text = tab.isHome ? '' : tab.url;
    if (_urlController.text != text) {
      _urlController.text = text;
    }
  }

  void _forceOpen(BlockEvent event) {
    final tab = _tabManager.activeTab;
    if (tab == null) return;
    tab.pendingAppNavigation = true;
    _tabManager.activeTab?.controller.loadRequest(Uri.parse(event.url));
  }

  void _showNotification(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(milliseconds: 4200),
  }) {
    setState(() {
      _notification = message;
      _notificationActionLabel = actionLabel;
      _notificationAction = onAction;
    });
    Future.delayed(duration, () {
      if (mounted && _notification == message) {
        setState(() => _notification = null);
      }
    });
  }

  Future<void> _runScraper() async {
    final tab = _tabManager.activeTab;
    if (tab == null || tab.isHome) {
      _showNotification('Erst eine Seite öffnen');
      return;
    }
    _showNotification('Tiefe Analyse…', duration: const Duration(seconds: 60));
    try {
      // Deep-Scrape: findet Videos, Dokumente und Media-URLs in HTML, JSON, XML
      final DeepScrapeResult result = await compute(_deepScrapeIsolate, tab.url);

      final videoCount = result.videos.length;
      final docCount = result.docs.length;
      final mediaCount = result.links.length;

      _showNotification(
        '$videoCount Videos · $docCount Dokumente · $mediaCount Medien gefunden',
        actionLabel: 'DETAILS',
        onAction: () => _showScrapeDetails(result),
      );
    } catch (e) {
      _showNotification('Analyse fehlgeschlagen: $e');
    }
  }

  void _showScrapeDetails(DeepScrapeResult result) {
    showModalBottomSheet(
      context: context,
      backgroundColor: NexusColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(NexusRadii.panel)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(result.title ?? 'NEXUS', style: Theme.of(context).textTheme.titleMedium),
            Text('${result.videos.length} Videos · ${result.docs.length} Dokumente · ${result.links.length} Medien'),
            const SizedBox(height: 12),
            if (result.videos.isNotEmpty) ...[
              const Text('Videos:', style: TextStyle(fontWeight: FontWeight.bold)),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: result.videos.take(30).map((v) => ListTile(
                    title: Text(v.title.isEmpty ? v.host : v.title, style: const TextStyle(fontSize: 12)),
                    subtitle: Text('${v.type} · ${v.url}', style: const TextStyle(fontSize: 10)),
                    trailing: IconButton(
                      icon: const Icon(Icons.download, size: 16),
                      onPressed: () => _downloadVideo(v, v.pageUrl),
                    ),
                  )).toList(),
                ),
              ),
            ],
            if (result.docs.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Dokumente:', style: TextStyle(fontWeight: FontWeight.bold)),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: result.docs.take(20).map((d) => ListTile(
                    title: Text(d.title, style: const TextStyle(fontSize: 12)),
                    subtitle: Text('${d.type} · ${_formatBytes(d.bytes)}', style: const TextStyle(fontSize: 10)),
                    trailing: IconButton(
                      icon: const Icon(Icons.folder_open, size: 16),
                      onPressed: () => _openDoc(d.localPath),
                    ),
                  )).toList(),
                ),
              ),
            ],
            if (result.errors.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Fehler (${result.errors.length}):', style: TextStyle(color: Colors.red[300])),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: result.errors.map((e) => Text(e, style: const TextStyle(fontSize: 10, color: Colors.red))).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _openDoc(String path) {
    // Öffnet eine lokale Dokument-Datei
    _showNotification('Dokument gespeichert: $path');
  }

  Future<void> _runHarvester() async {
    final tab = _tabManager.activeTab;
    if (tab == null || tab.isHome) {
      _showNotification('Erst eine Seite öffnen');
      return;
    }
    HarvestLogger.instance.start(tab.url);
    _showNotification(
      'Durchsuche Seite… (Tipp: Video vorher kurz anspielen, findet mehr)',
      duration: const Duration(seconds: 30),
    );
    try {
      final merged = <String, HarvestedVideo>{};

      // Diagnose-Schritt (nicht Teil der eigentlichen Erkennung): rohes
      // HTML separat holen, um <video>-Tags VOR JS-Ausführung zu zählen —
      // zeigt im Debug-Log direkt, ob eine Seite ihre Player erst per JS
      // nachlädt (dann ist die Rendering-Zahl unten deutlich höher).
      unawaited(VideoHarvesterEngine.fetchHtmlForDebug(tab.url).then((raw) {
        if (raw == null) {
          HarvestLogger.instance.log('raw-html', 'Roh-HTML nicht abrufbar (Fetch fehlgeschlagen)',
              level: HarvestLogLevel.warning);
          return;
        }
        final videoTags = RegExp(r'<video\b', caseSensitive: false).allMatches(raw).length;
        final iframeTagsRaw = RegExp(r'<iframe\b', caseSensitive: false).allMatches(raw).length;
        HarvestLogger.instance.log(
          'raw-html',
          '${raw.length} Bytes, $videoTags <video>-Tag(s), $iframeTagsRaw <iframe>-Tag(s) im rohen HTML',
          data: {'bytes': raw.length, 'videoTags': videoTags, 'iframeTags': iframeTagsRaw},
        );
      }));

      // Ebene 1: Netzwerk-Sniffer — liest zurück, welche URLs die Seite
      // selbst per fetch()/XHR angefragt hat (Skript läuft seit
      // onPageStarted mit, siehe redirect_shield.dart). Das ist die
      // einzige Ebene, die auch Player findet, die ihre Stream-URL NIE ins
      // DOM schreiben, sondern nur intern an MediaSource/<video> weiterreichen.
      try {
        HarvestLogger.instance.log('sniffer', 'Injiziere Netzwerk-Sniffer + Discovery-Skript…');
        await _tabManager.activeTab?.controller.runJavaScript(NetworkSniffer.injectionScript);
        await _tabManager.activeTab?.controller.runJavaScript(NetworkSniffer.discoveryScript);
        await Future<void>.delayed(const Duration(seconds: 8));
        final raw = await _tabManager.activeTab?.controller.runJavaScriptReturningResult(
          'JSON.stringify(window.__nexusMedia || [])',
        );
        final captures = NetworkSniffer.parseCaptures(raw!);
        final bySource = <String, int>{};
        for (final c in captures) {
          bySource[c.source] = (bySource[c.source] ?? 0) + 1;
        }
        HarvestLogger.instance.log(
          'sniffer',
          '${captures.length} Netzwerk-Treffer (${bySource.entries.map((e) => '${e.key}: ${e.value}').join(', ')})',
          data: {'count': captures.length, 'bySource': bySource},
        );
        for (final v in VideoHarvesterEngine.classifyCaptures(captures, tab.title)) {
          merged[v.url] = v;
        }
      } catch (e) {
        HarvestLogger.instance.log('sniffer', 'Sniffer fehlgeschlagen: $e', level: HarvestLogLevel.error);
      }

      // Ebene 2: das tatsächlich gerenderte DOM der offenen WebView —
      // NACH JavaScript-Ausführung. Findet Player, deren Quelle zwar per JS
      // gesetzt wird, aber am Ende doch als Attribut/JSON im DOM landet.
      try {
        final raw = await _tabManager.activeTab?.controller.runJavaScriptReturningResult(
          'document.documentElement.outerHTML',
        );
        String renderedHtml;
        try {
          renderedHtml = jsonDecode(raw.toString()) as String;
        } catch (_) {
          renderedHtml = raw.toString();
        }
        final videoTagsRendered = RegExp(r'<video\b', caseSensitive: false).allMatches(renderedHtml).length;
        final iframeTagsRendered = RegExp(r'<iframe\b', caseSensitive: false).allMatches(renderedHtml).length;
        final beforeCount = merged.length;
        for (final v in VideoHarvesterEngine.extractFromRenderedHtml(
          renderedHtml,
          tab.url,
          titleHint: tab.title,
        )) {
          merged.putIfAbsent(v.url, () => v);
        }
        HarvestLogger.instance.log(
          'dom-render',
          '${renderedHtml.length} Bytes gerendert, $videoTagsRendered <video>-Tag(s), '
              '$iframeTagsRendered <iframe>-Tag(s), ${merged.length - beforeCount} neue Treffer',
          data: {
            'bytes': renderedHtml.length,
            'videoTags': videoTagsRendered,
            'iframeTags': iframeTagsRendered,
            'newHits': merged.length - beforeCount,
          },
        );

        // DOM-Snapshot: nur die für die Erkennung relevanten Tags,
        // fürs Debug-Panel zum Nachschauen, was tatsächlich im DOM stand.
        final snapshotRaw = await _tabManager.activeTab?.controller
            .runJavaScriptReturningResult(NetworkSniffer.domSnapshotScript);
        if (snapshotRaw != null) {
          HarvestLogger.instance.setDomSnapshot(NetworkSniffer.parseDomSnapshot(snapshotRaw));
        }
      } catch (e) {
        HarvestLogger.instance.log('dom-render', 'DOM-Auswertung fehlgeschlagen: $e', level: HarvestLogLevel.error);
      }

      // Ebene 3: Tiefe Video-Suche via VideoHarvester (rekursive iFrames + yt-dlp)
      // Läuft parallel zum webView-Sniffer in einem Isolate.
      HarvestLogger.instance.log('deep-harvest', 'Tiefe Video-Suche starten (Isolate)…');
      final deepResult = await compute(_deepHarvestIsolate, tab.url);

      if (deepResult.videos.isNotEmpty) {
        final beforeDeep = merged.length;
        for (final v in deepResult.videos) {
          merged.putIfAbsent(v.url, () => v);
        }
        HarvestLogger.instance.log(
          'deep-harvest',
          '${deepResult.videos.length} Videos aus tiefer Suche, ${merged.length - beforeDeep} davon neu',
          data: {
            'deepVideos': deepResult.videos.length,
            'newHits': merged.length - beforeDeep,
            'ytDlpUsed': deepResult.ytDlpFallbackUsed,
            'iframeCount': deepResult.iframeUrls.length,
          },
        );
      }

      // Ebene 3 (original): der bisherige Netzwerk-Crawl —
      // findet Treffer auf verlinkten Seiten (Embeds, Player-Seiten).
      HarvestLogger.instance.log('crawl', 'Durchsuche verlinkte Seiten (eigener Isolate)…');
      final beforeCrawl = merged.length;
      final crawlResults = await compute(_harvestIsolate, tab.url);
      for (final v in crawlResults) {
        merged.putIfAbsent(v.url, () => v);
      }
      HarvestLogger.instance.log(
        'crawl',
        '${crawlResults.length} Treffer aus verlinkten Seiten, '
            '${merged.length - beforeCrawl} davon neu',
        data: {'crawlHits': crawlResults.length, 'newHits': merged.length - beforeCrawl},
      );

      // Manifest pass: inspect the first bounded set of HLS/DASH candidates
      // and attach quality variants without blocking the UI isolate.
      final keys = merged.keys.toList();
      var enriched = 0;
      for (final key in keys.take(24)) {
        final current = merged[key];
        if (current == null || (current.type != 'M3U8' && current.type != 'DASH')) continue;
        merged[key] = await VideoHarvesterEngine.enrichManifest(current);
        enriched++;
      }
      if (enriched > 0) {
        HarvestLogger.instance.log('manifest', '$enriched M3U8/DASH-Manifest(e) auf Qualitätsstufen geprüft');
      }

      if (!mounted) return;
      if (merged.isEmpty) {
        HarvestLogger.instance.log('ergebnis', 'Keine Videos gefunden', level: HarvestLogLevel.warning);
        HarvestLogger.instance.finish(success: false);
        _showNotification('Keine Videos gefunden');
        return;
      }
      HarvestLogger.instance.log('ergebnis', '${merged.length} Video(s) insgesamt gefunden');
      HarvestLogger.instance.finish(success: true);
      setState(() => _notification = null);
      _showHarvesterSheet(merged.values.toList(), referer: tab.url);
    } catch (e) {
      HarvestLogger.instance.log('fehler', '$e', level: HarvestLogLevel.error);
      HarvestLogger.instance.finish(success: false);
      _showNotification('Video Harvester fehlgeschlagen: $e');
    }
  }

  void _showHarvesterSheet(List<HarvestedVideo> results, {required String referer}) {
    String query = '';
    String excludeDomain = '';
    final activeTypes = <String>{'MP4', 'WEBM', 'M3U8', 'MEDIA'};
    final selected = <String>{};
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NexusColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(NexusRadii.panel)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final filtered = results.where((v) {
            if (!activeTypes.contains(v.type)) return false;
            if (excludeDomain.trim().isNotEmpty &&
                v.host.toLowerCase().contains(excludeDomain.trim().toLowerCase())) {
              return false;
            }
            if (query.trim().isEmpty) return true;
            final q = query.toLowerCase();
            return v.title.toLowerCase().contains(q) ||
                v.host.toLowerCase().contains(q) ||
                v.url.toLowerCase().contains(q);
          }).toList();
          const downloadable = {'MP4', 'WEBM', 'M3U8', 'MEDIA'};

          return DraggableScrollableSheet(
            initialChildSize: 0.7,
            expand: false,
            builder: (context, scrollController) => Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('${results.length} Treffer',
                          style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      if (selected.isNotEmpty)
                        FilledButton.icon(
                          icon: const Icon(Icons.download, size: 18),
                          label: Text('${selected.length} herunterladen'),
                          onPressed: () {
                            final chosen = results.where((v) => selected.contains(v.url)).toList();
                            BatchDownloadManager.instance.enqueueAll(chosen, referer);
                            Navigator.pop(context);
                            _showNotification('${chosen.length} Videos in die Warteschlange gestellt');
                            _openDownloadsPanel();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Typ-Filter: reine UI-Filterung auf dem bereits
                  // vorliegenden Ergebnis dieses einen Harvest-Laufs.
                  Wrap(
                    spacing: 6,
                    children: downloadable.map((type) {
                      final active = activeTypes.contains(type);
                      return FilterChip(
                        label: Text(type, style: const TextStyle(fontSize: 11)),
                        selected: active,
                        onSelected: (v) => setSheetState(
                            () => v ? activeTypes.add(type) : activeTypes.remove(type)),
                        selectedColor: NexusColors.accentPrimarySoft,
                        backgroundColor: NexusColors.bgPill,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    style: const TextStyle(color: NexusColors.textPrimary),
                    onChanged: (value) => setSheetState(() => query = value),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Filtern, z.B. nach Titel…',
                      hintStyle: const TextStyle(color: NexusColors.textMuted),
                      prefixIcon: const Icon(Icons.search, size: 20, color: NexusColors.textMuted),
                      filled: true,
                      fillColor: NexusColors.bgPill,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(NexusRadii.button),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    style: const TextStyle(color: NexusColors.textPrimary, fontSize: 12),
                    onChanged: (value) => setSheetState(() => excludeDomain = value),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Domain ausschließen (optional)',
                      hintStyle: const TextStyle(color: NexusColors.textMuted, fontSize: 12),
                      prefixIcon: const Icon(Icons.block, size: 18, color: NexusColors.textMuted),
                      filled: true,
                      fillColor: NexusColors.bgPill,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(NexusRadii.button),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (filtered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('Keine Treffer für diesen Filter.',
                          style: TextStyle(color: NexusColors.textMuted)),
                    ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final v = filtered[i];
                        final canDownload = downloadable.contains(v.type);
                        final quality = v.quality.isEmpty ? '' : ' · ${v.quality}';
                        return ListTile(
                          leading: canDownload
                              ? Checkbox(
                                  value: selected.contains(v.url),
                                  activeColor: NexusColors.accentPrimary,
                                  onChanged: (checked) => setSheetState(() {
                                    if (checked == true) {
                                      selected.add(v.url);
                                    } else {
                                      selected.remove(v.url);
                                    }
                                  }),
                                )
                              : const SizedBox(width: 24),
                          title: Text(v.title.isEmpty ? v.host : v.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '${v.type}$quality · ${v.status}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: canDownload ? null : const TextStyle(color: NexusColors.textMuted),
                          ),
                          isThreeLine: true,
                          trailing: Wrap(
                            spacing: 0,
                            children: [
                              IconButton(
                                tooltip: 'Stream öffnen',
                                icon: const Icon(Icons.play_arrow, color: NexusColors.accentPrimary),
                                onPressed: () => _tabManager.activeTab?.controller.loadRequest(Uri.parse(v.url)),
                              ),
                              if (canDownload)
                                IconButton(
                                  tooltip: 'Download',
                                  icon: const Icon(Icons.download, color: NexusColors.accentPrimary),
                                  onPressed: () => _downloadVideo(v, referer),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _downloadVideo(HarvestedVideo video, String referer) async {
    final task = DownloadRepository.instance.start(video.title, video.url);
    _showNotification('Download gestartet: ${video.title}');
    try {
      await VideoDownloader.download(
        video.url,
        video.title,
        referer: referer,
        headers: {
          ...video.headers,
          if (video.cookies.isNotEmpty) 'Cookie': video.cookies,
          if (video.userAgent.isNotEmpty) 'User-Agent': video.userAgent,
        },
        onProgress: (progress) {
          if (progress.percent >= 0) {
            DownloadRepository.instance.update(task, progress.percent);
          }
        },
      );
      DownloadRepository.instance.finish(task);
      _showNotification('Fertig: ${video.title}');
    } catch (e) {
      DownloadRepository.instance.fail(task, '$e');
      // Vorher wurde ein Fehlschlag nirgends angezeigt — die Mediathek
      // blendet FAILED-Einträge sogar bewusst aus (siehe dortiger Filter),
      // und ohne diese Meldung hier sah ein Fehlschlag identisch zu einem
      // erfolgreichen, nur unsichtbaren Download aus.
      _showNotification(
        'Download fehlgeschlagen: $e',
        duration: const Duration(seconds: 8),
      );
    }
  }

  /// Zentrale Zuordnung Command-ID → tatsächlicher Callback. Sowohl die
  /// Command Palette als auch die Tastenkürzel-Ebene greifen auf dieselbe
  /// Map zu, damit ein Befehl nur an einer Stelle gepflegt werden muss.
  Map<String, VoidCallback> _commandCallbacks() => {
        NexusCommands.palette: _openCommandPalette,
        NexusCommands.focusAddress: _focusAddress,
        NexusCommands.newTab: _newTabInPane,
        NexusCommands.closeTab: _closeActivePaneTab,
        NexusCommands.back: _tabManager.goBack,
        NexusCommands.forward: _tabManager.goForward,
        NexusCommands.reload: _tabManager.reload,
        NexusCommands.harvest: _runHarvester,
        NexusCommands.splitVertical: _splitVertical,
        NexusCommands.splitHorizontal: _splitHorizontal,
        NexusCommands.terminal: () => _paneManager.setKind(PaneKind.terminal),
        NexusCommands.devtools: () => _paneManager.setKind(PaneKind.devtools),
        NexusCommands.harvesterDebug: () => _paneManager.setKind(PaneKind.harvesterDebug),
        NexusCommands.browserPane: () => _paneManager.setKind(PaneKind.browser),
        NexusCommands.frameless: () => setState(() => _frameless = !_frameless),
        NexusCommands.workspaceSave: _saveWorkspace,
      };

  Map<ShortcutActivator, VoidCallback> _buildShortcuts() {
    final callbacks = _commandCallbacks();
    final out = <ShortcutActivator, VoidCallback>{};
    for (final entry in KeybindingEngine.instance.bindings.entries) {
      final callback = callbacks[entry.key];
      final activator = parseShortcut(entry.value);
      if (callback != null && activator != null) {
        out[activator] = callback;
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) return const Scaffold(backgroundColor: NexusColors.bgBase, body: Center(child: CircularProgressIndicator()));
    final tab = _tabForPane(_paneManager.activePane);
    return ListenableBuilder(
      listenable: KeybindingEngine.instance,
      builder: (context, _) => CallbackShortcuts(
      bindings: _buildShortcuts(),
      child: Focus(autofocus:true,child:Scaffold(backgroundColor:NexusColors.bgBase,body:SafeArea(
        child: _frameless
          ? Stack(children:[
              Positioned.fill(child:_buildPaneTree(_paneManager.root)),
              Positioned(top:0,left:0,right:0,height:18,child:MouseRegion(onEnter:(_)=>setState(()=>_revealChrome=true),child:const SizedBox())),
              if(_revealChrome) Positioned(top:0,left:0,right:0,child:Material(color:NexusColors.bgBase,elevation:6,child:Column(children:[_buildTopBarRow1(),_buildAddressBar(tab)]))),
              if(_notification!=null) _buildBottomNotification(),
            ])
          : Column(children:[
              _buildTopBarRow1(),
              _buildAddressBar(tab),
              Expanded(child:Row(children:[
                _buildSidebar(),
                Expanded(child:_buildPaneTree(_paneManager.root)),
              ])),
              if(_notification!=null) _buildBottomNotification(),
            ]),
      )))
    ),
    );
  }

  Widget _buildTopBarRow1() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Image.asset('assets/nexus_logo.png', width: 28, height: 28),
          const SizedBox(width: 8),
          const Text(
            'NEXUS',
            style: TextStyle(
              color: NexusColors.accentPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 18,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: NexusColors.bgSurfaceRaised,
              borderRadius: BorderRadius.circular(NexusRadii.button),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.shield_outlined,
                    size: 16, color: NexusColors.accentSuccess),
                const SizedBox(width: 4),
                Text('${_tabManager.blockedCount}',
                    style: const TextStyle(color: NexusColors.textPrimary)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: NexusColors.textPrimary),
            tooltip: 'Menü',
            onPressed: _openCommandCenter,
          ),
        ],
      ),
    );
  }

  void _openCommandCenter() {
    final tab = _tabManager.activeTab;
    showModalBottomSheet(
      context: context,
      backgroundColor: NexusColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(NexusRadii.panel)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 12, bottom: 4),
              child: Text('NEXUS',
                  style: TextStyle(
                      color: NexusColors.accentPrimary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2)),
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined,
                  color: NexusColors.textPrimary),
              title: const Text('Downloads'),
              subtitle: ListenableBuilder(
                listenable: DownloadRepository.instance,
                builder: (context, _) {
                  final active = DownloadRepository.instance
                      .activeAndRecent()
                      .where((t) => t.state == DownloadState.downloading)
                      .length;
                  return Text(active > 0
                      ? '$active läuft gerade'
                      : 'Nichts läuft gerade');
                },
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _openDownloadsPanel();
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined,
                  color: NexusColors.textPrimary),
              title: const Text('Mediathek'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MediathekScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.terminal, color: NexusColors.textPrimary),
              title: const Text('DevTools'),
              subtitle: tab == null
                  ? const Text('Erst eine Seite öffnen')
                  : null,
              enabled: tab != null,
              onTap: tab == null
                  ? null
                  : () {
                      Navigator.pop(sheetContext);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DevToolsScreen(tab: tab),
                        ),
                      );
                    },
            ),
            ListTile(
              leading: const Icon(Icons.push_pin_outlined,
                  color: NexusColors.textPrimary),
              title: const Text('Aktuelle Seite als Quick-Link speichern'),
              enabled: tab != null && !tab.isHome,
              onTap: tab == null || tab.isHome
                  ? null
                  : () {
                      Navigator.pop(sheetContext);
                      DevSettings.instance.addQuickLink(
                        QuickLink(label: tab.title, url: tab.url),
                      );
                      _showNotification('Zur Startseite hinzugefügt');
                    },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _openDownloadsPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NexusColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(NexusRadii.panel)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(12),
          child: const DownloadsSection(),
        ),
      ),
    );
  }


  void _activatePane(PaneState pane) {
    _paneManager.activePaneId = pane.id;
    final id = pane.activeTabId;
    if (id != null) _tabManager.switchTab(id);
    _syncUrlField(); setState(() {});
  }

  NexusTab? _tabForPane(PaneState pane) {
    final id = pane.activeTabId ?? (pane.tabIds.isEmpty ? null : pane.tabIds.first);
    if (id == null) return null;
    for (final t in _tabManager.tabs) { if (t.id == id) return t; }
    return null;
  }

  void _newTabInPane() {
    _paneManager.ensureActive();
    final t = _tabManager.addTab();
    final p = _paneManager.activePane; p.tabIds.add(t.id); p.activeTabId=t.id;
    setState(() {});
  }

  void _closeActivePaneTab() {
    _paneManager.ensureActive(); final p=_paneManager.activePane; final id=p.activeTabId;
    if(id==null)return; _tabManager.closeTab(id); p.tabIds.remove(id); p.activeTabId=p.tabIds.isEmpty?null:p.tabIds.last; if(p.tabIds.isEmpty){final t=_tabManager.addTab();p.tabIds.add(t.id);p.activeTabId=t.id;} setState(() {});
  }

  void _openCommandPalette() {
    showDialog(context: context, barrierColor: Colors.black54, builder: (_) => CommandPalette(tabManager: _tabManager, items: _paletteItems()));
  }

  List<PaletteItem> _paletteItems() => [
    PaletteItem('Video Harvester starten','Actions',Icons.video_collection_outlined,_runHarvester,commandId:NexusCommands.harvest),
    PaletteItem('Komplett-Analyse starten','Actions',Icons.travel_explore,_runScraper,commandId:'scraper.run'),
    PaletteItem('Neuer Tab','Actions',Icons.add,_newTabInPane,commandId:NexusCommands.newTab),
    PaletteItem('Zurück','Actions',Icons.arrow_back,_tabManager.goBack,commandId:NexusCommands.back),
    PaletteItem('Vor','Actions',Icons.arrow_forward,_tabManager.goForward,commandId:NexusCommands.forward),
    PaletteItem('Reload','Actions',Icons.refresh,_tabManager.reload,commandId:NexusCommands.reload),
    PaletteItem('Vertikal splitten','Actions',Icons.view_column,_splitVertical,commandId:NexusCommands.splitVertical),
    PaletteItem('Horizontal splitten','Actions',Icons.view_agenda,_splitHorizontal,commandId:NexusCommands.splitHorizontal),
    PaletteItem('Terminal-Pane','Actions',Icons.terminal,()=>_paneManager.setKind(PaneKind.terminal),commandId:NexusCommands.terminal),
    PaletteItem('DevTools-Pane','Actions',Icons.developer_mode,()=>_paneManager.setKind(PaneKind.devtools),commandId:NexusCommands.devtools),
    PaletteItem('Harvester-Debug-Pane','Actions',Icons.bug_report,()=>_paneManager.setKind(PaneKind.harvesterDebug),commandId:NexusCommands.harvesterDebug),
    PaletteItem('Harvester-Testfälle','Actions',Icons.science,()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>const HarvestTestCasesScreen()))),
    PaletteItem('Browser-Pane','Actions',Icons.public,()=>_paneManager.setKind(PaneKind.browser),commandId:NexusCommands.browserPane),
    PaletteItem('Frameless Mode umschalten','Actions',Icons.fullscreen,()=>setState(()=>_frameless=!_frameless),commandId:NexusCommands.frameless),
    PaletteItem('Workspace speichern','Actions',Icons.save,_saveWorkspace,commandId:NexusCommands.workspaceSave),
    ...WorkspaceManager.instance.workspaces.map((w)=>PaletteItem('Workspace: ${w.name}','Actions',Icons.workspaces,()=>_loadWorkspace(w))),
    ...DevSettings.instance.quickLinks.map((q)=>PaletteItem(q.label,'Bookmarks',Icons.bookmark,(){_tabManager.navigateInput(q.url);} ,hint:q.url)),
    ..._tabManager.tabs.map((t)=>PaletteItem(t.title,'History',Icons.history,(){_tabManager.navigateInput(t.url);},hint:t.url)),
    PaletteItem('Auto-Dark für Webseiten: ${ThemeConfig.instance.autoDarkWeb ? 'AN' : 'AUS'}','Settings',Icons.dark_mode,()async{ThemeConfig.instance.autoDarkWeb=!ThemeConfig.instance.autoDarkWeb;await ThemeConfig.instance.save();setState((){});}),
    PaletteItem('Keybindings / Vim / Emacs / Gaming','Settings',Icons.keyboard, _openKeybindings),
    PaletteItem('Downloads','Actions',Icons.download_outlined,_openDownloadsPanel,commandId:NexusCommands.downloads),
    PaletteItem('Mediathek','Actions',Icons.video_library_outlined,()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>const MediathekScreen())),commandId:NexusCommands.mediathek),
    PaletteItem('Adressleiste fokussieren','Actions',Icons.search,()=>_focusAddress(),commandId:NexusCommands.focusAddress),
  ];

  void _openKeybindings() {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Keybinding Engine'),
      content: SizedBox(width: 520, child: ListView(shrinkWrap: true, children: [
        DropdownButtonFormField<String>(value: KeybindingEngine.instance.mode, decoration: const InputDecoration(labelText:'Profil'), items: const ['Custom','Vim','Emacs','Gaming'].map((m)=>DropdownMenuItem(value:m,child:Text(m))).toList(), onChanged:(m){if(m!=null)KeybindingEngine.instance.applyMode(m);}),
        const SizedBox(height: 10),
        ...KeybindingEngine.instance.bindings.entries.map((e)=>ListTile(dense:true,title:Text(e.key,style:const TextStyle(fontSize:12)),trailing:Text(e.value,style:const TextStyle(color:NexusColors.accentPrimary)),onTap:(){final c=TextEditingController(text:e.value);showDialog(context:context,builder:(_)=>AlertDialog(title:Text(e.key),content:TextField(controller:c,autofocus:true,decoration:const InputDecoration(hintText:'z.B. Ctrl+K')),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Abbrechen')),FilledButton(onPressed:(){KeybindingEngine.instance.set(e.key,c.text.trim());Navigator.pop(context);},child:const Text('Setzen'))]));})),
      ])),
      actions: [TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Schließen'))],
    ));
  }

  void _focusAddress(){ setState(()=>_revealChrome=true); WidgetsBinding.instance.addPostFrameCallback((_){_addressFocus.requestFocus();_urlController.selection=TextSelection(baseOffset:0,extentOffset:_urlController.text.length);}); }
  void _splitVertical(){_paneManager.splitActive(PaneOrientation.vertical,_newTabInSplit());}
  void _splitHorizontal(){_paneManager.splitActive(PaneOrientation.horizontal,_newTabInSplit());}
  String? _newTabInSplit(){ final t=_tabManager.addTab(); return t.id; }

  Future<void> _saveWorkspace(){
    final c=TextEditingController();
    return showDialog<void>(context:context,builder:(_)=>AlertDialog(title:const Text('Workspace speichern'),content:TextField(controller:c,autofocus:true,decoration:const InputDecoration(hintText:'z.B. Projekt Alpha')),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Abbrechen')),FilledButton(onPressed:()async{if(c.text.trim().isNotEmpty){await WorkspaceManager.instance.save(c.text,_tabManager.exportSnapshot(),_paneManager);}if(mounted)Navigator.pop(context);},child:const Text('Speichern'))])).whenComplete(c.dispose);
  }
  Future<void> _loadWorkspace(WorkspaceSnapshot w) async { await _tabManager.restoreSnapshot(w.tabs); _paneManager.restore(w.panes); if(mounted)setState((){}); }

  Widget _buildPaneTree(PaneNode node) {
    if(node.isLeaf){ final pane=node.pane!; final active=pane.id==_paneManager.activePaneId; return GestureDetector(onTap:()=>_activatePane(pane),child:Container(decoration:BoxDecoration(border:Border.all(color:active?NexusColors.accentPrimary:NexusColors.border,width:active?2:1)),child:_buildPaneBody(pane))); }
    final first=Expanded(flex:(node.ratio*1000).round(),child:_buildPaneTree(node.first!));
    final second=Expanded(flex:((1-node.ratio)*1000).round(),child:_buildPaneTree(node.second!));
    final splitter=GestureDetector(onHorizontalDragUpdate:node.orientation==PaneOrientation.vertical?(d){node.ratio=(node.ratio+d.delta.dx/800).clamp(.2,.8);setState((){});}:null,onVerticalDragUpdate:node.orientation==PaneOrientation.horizontal?(d){node.ratio=(node.ratio+d.delta.dy/600).clamp(.2,.8);setState((){});}:null,child:Container(width:node.orientation==PaneOrientation.vertical?5:double.infinity,height:node.orientation==PaneOrientation.horizontal?5:double.infinity,color:NexusColors.accentPrimary));
    return Flex(direction:node.orientation==PaneOrientation.vertical?Axis.horizontal:Axis.vertical,children:[first,splitter,second]);
  }

  Widget _buildPaneBody(PaneState pane){
    final tab=_tabForPane(pane);
    switch(pane.kind){
      case PaneKind.terminal: return TerminalPane(initialText:pane.terminalText,onTextChanged:_paneManager.setTerminalText);
      case PaneKind.devtools: return tab==null?const Center(child:Text('Kein Tab in diesem Pane')):DevToolsScreen(tab:tab);
      case PaneKind.harvesterDebug: return const HarvestDebugPanel();
      case PaneKind.browser:
        if(tab==null)return Center(child:TextButton.icon(onPressed:_newTabInPane,icon:const Icon(Icons.add),label:const Text('Tab öffnen')));
        return Column(children:[_buildPaneTabStrip(pane),Expanded(child:_buildContent(tab))]);
    }
  }

    Widget _buildPaneTabStrip(PaneState pane) {
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              children: pane.tabIds.map((id) {
                NexusTab? t;
                for (final candidate in _tabManager.tabs) {
                  if (candidate.id == id) { t = candidate; break; }
                }
                if (t == null) return const SizedBox.shrink();
                final a = id == pane.activeTabId;
                return GestureDetector(
                  onTap: () {
                    pane.activeTabId = id;
                    _tabManager.switchTab(id);
                    _activatePane(pane);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: a ? NexusColors.accentPrimarySoft : NexusColors.bgSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: a ? NexusColors.accentPrimary : NexusColors.border),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      children: [
                        Text(t.isHome ? 'Neuer Tab' : t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                        const SizedBox(width: 5),
                        GestureDetector(
                          onTap: () {
                            _tabManager.closeTab(id);
                          },
                          child: const Icon(Icons.close, size: 12),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFramelessContent(NexusTab? tab){ return Stack(children:[Positioned.fill(child:_buildPaneTree(_paneManager.root)),if(_frameless&&!_revealChrome)const Positioned(top:0,left:0,right:0,height:12,child:MouseRegion(cursor:SystemMouseCursors.basic,child:SizedBox()))]); }

  Widget _buildAddressBar(NexusTab? tab) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: NexusColors.bgPill,
          borderRadius: BorderRadius.circular(NexusRadii.pill),
          border: Border.all(color: NexusColors.border),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: _urlController,
                focusNode: _addressFocus,
                style: const TextStyle(color: NexusColors.textPrimary),
                textInputAction: TextInputAction.go,
                onSubmitted: (value) => _tabManager.navigateInput(value),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Suchen oder Adresse eingeben',
                  hintStyle: TextStyle(color: NexusColors.textMuted),
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                tab?.isLoading == true ? Icons.close : Icons.refresh,
                color: NexusColors.textMuted,
              ),
              onPressed: () => _tabManager.reload(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabStrip() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          ..._tabManager.tabs.map((t) {
            final active = t.id == _tabManager.activeTab?.id;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _tabManager.switchTab(t.id)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: active
                        ? NexusColors.accentPrimarySoft
                        : NexusColors.bgSurface,
                    borderRadius: BorderRadius.circular(NexusRadii.pill),
                    border: Border.all(
                      color: active
                          ? NexusColors.accentPrimary
                          : NexusColors.border,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 100),
                        child: Text(
                          t.isHome ? 'Neuer Tab' : t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: NexusColors.textPrimary, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => setState(() => _tabManager.closeTab(t.id)),
                        child: const Icon(Icons.close,
                            size: 14, color: NexusColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          IconButton(
            icon: const Icon(Icons.add, color: NexusColors.accentPrimary),
            onPressed: () => setState(() => _tabManager.addTab()),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    final width =
        _sidebarExpanded ? 180.0 : NexusRadii.sidebarCollapsedWidth;
    return AnimatedContainer(
      duration: NexusMotion.sidebar,
      width: width,
      color: NexusColors.bgSurface,
      child: Column(
        children: [
          IconButton(
            icon: Icon(
              _sidebarExpanded ? Icons.chevron_left : Icons.chevron_right,
              color: NexusColors.accentPrimary,
            ),
            onPressed: () =>
                setState(() => _sidebarExpanded = !_sidebarExpanded),
          ),
          if (_sidebarExpanded) ...[
            _sidebarItem(Icons.home, 'Start', () => _tabManager.goHome()),
            _sidebarItem(Icons.arrow_back, 'Zurück', () => _tabManager.goBack()),
            _sidebarItem(
                Icons.arrow_forward, 'Vor', () => _tabManager.goForward()),
            const Divider(color: NexusColors.border),
            _sidebarItem(
                Icons.travel_explore, 'Komplett-Analyse', _runScraper),
            _sidebarItem(
                Icons.video_collection_outlined, 'Video Harvester', _runHarvester),
            const Divider(color: NexusColors.border),
            _sidebarItem(Icons.video_library_outlined, 'Mediathek', () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MediathekScreen()),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _sidebarItem(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: NexusColors.textPrimary, size: 20),
      title: Text(label,
          style: const TextStyle(color: NexusColors.textPrimary, fontSize: 13)),
      onTap: onTap,
    );
  }

  Widget _buildContent(NexusTab? tab) {
    if (tab == null) return const SizedBox.shrink();
    if (tab.isHome) {
      return StartPage(
        onSubmit: (query) => _tabManager.navigateInput(query),
        tabCount: _tabManager.tabs.length,
        blockedCount: _tabManager.blockedCount,
      );
    }
    return RepaintBoundary(
      child: _tabManager.activeTab?.controller != null ? WebViewWidget(controller: _tabManager.activeTab!.controller) : const SizedBox.shrink(),
    );
  }

  Widget _buildBottomNotification() {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: AnimatedOpacity(
        opacity: _notification == null ? 0 : 1,
        duration: NexusMotion.bottomPanel,
        child: Material(
          color: NexusColors.bgSurfaceRaised,
          borderRadius: BorderRadius.circular(NexusRadii.panel),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(_notification ?? '',
                      style: const TextStyle(color: NexusColors.textPrimary)),
                ),
                if (_notificationActionLabel != null)
                  TextButton(
                    onPressed: () {
                      _notificationAction?.call();
                      setState(() => _notification = null);
                    },
                    child: Text(_notificationActionLabel!,
                        style:
                            const TextStyle(color: NexusColors.accentPrimary)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
