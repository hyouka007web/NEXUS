import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../engines/network_sniffer.dart';
import '../engines/scraper_engine.dart';
import '../engines/video_downloader.dart';
import '../engines/video_harvester_engine.dart';
import '../models/block_event.dart';
import '../models/download_task.dart';
import '../models/harvested_video.dart';
import '../models/quick_link.dart';
import '../models/scrape_result.dart';
import '../models/tab_model.dart';
import '../state/dev_settings.dart';
import '../state/download_repository.dart';
import '../state/tab_manager.dart';
import '../theme/nexus_theme.dart';
import 'devtools_screen.dart';
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
Future<ScrapeResult> _scrapeIsolate(String url) => ScraperEngine.scrape(url);

Future<List<HarvestedVideo>> _harvestIsolate(String url) =>
    VideoHarvesterEngine.harvest(url);

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final _tabManager = TabManager();
  final _urlController = TextEditingController();
  bool _sidebarExpanded = false;
  bool _restoring = true;
  String? _notification;
  VoidCallback? _notificationAction;
  String? _notificationActionLabel;

  @override
  void initState() {
    super.initState();
    _tabManager.addListener(_onTabManagerChanged);
    _restoreTabs();
  }

  Future<void> _restoreTabs() async {
    await Future.wait([_tabManager.restore(), DevSettings.instance.restore()]);
    _syncUrlField();
    if (mounted) setState(() => _restoring = false);
  }

  @override
  void dispose() {
    _tabManager.removeListener(_onTabManagerChanged);
    _urlController.dispose();
    super.dispose();
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
    final tab = _tabManager.activeTab;
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
    tab.controller.loadRequest(Uri.parse(event.url));
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
    _showNotification('Analysiere…', duration: const Duration(seconds: 30));
    try {
      final ScrapeResult result = await compute(_scrapeIsolate, tab.url);
      _showNotification(
        '${result.links.length} Links · ${result.media.length} Medien gefunden',
        actionLabel: 'DETAILS',
        onAction: () => _showScrapeDetails(result),
      );
    } catch (e) {
      _showNotification('Analyse fehlgeschlagen: $e');
    }
  }

  void _showScrapeDetails(ScrapeResult result) {
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
            Text(result.title, style: Theme.of(context).textTheme.titleMedium),
            Text('${result.links.length} Links · ${result.media.length} Medien'),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: result.media
                    .take(50)
                    .map((m) => Text(m, style: const TextStyle(fontSize: 12)))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runHarvester() async {
    final tab = _tabManager.activeTab;
    if (tab == null || tab.isHome) {
      _showNotification('Erst eine Seite öffnen');
      return;
    }
    _showNotification(
      'Durchsuche Seite… (Tipp: Video vorher kurz anspielen, findet mehr)',
      duration: const Duration(seconds: 30),
    );
    try {
      final merged = <String, HarvestedVideo>{};

      // Ebene 1: Netzwerk-Sniffer — liest zurück, welche URLs die Seite
      // selbst per fetch()/XHR angefragt hat (Skript läuft seit
      // onPageStarted mit, siehe redirect_shield.dart). Das ist die
      // einzige Ebene, die auch Player findet, die ihre Stream-URL NIE ins
      // DOM schreiben, sondern nur intern an MediaSource/<video> weiterreichen.
      try {
        final raw = await tab.controller.runJavaScriptReturningResult(
          'JSON.stringify(window.__nexusSniffed || [])',
        );
        for (final v in VideoHarvesterEngine.classifyUrls(
          NetworkSniffer.parseResult(raw),
          tab.title,
        )) {
          merged[v.url] = v;
        }
      } catch (_) {
        // Sniffer nicht verfügbar (z.B. CSP blockt eval) — weiter mit den
        // übrigen Ebenen.
      }

      // Ebene 2: das tatsächlich gerenderte DOM der offenen WebView —
      // NACH JavaScript-Ausführung. Findet Player, deren Quelle zwar per JS
      // gesetzt wird, aber am Ende doch als Attribut/JSON im DOM landet.
      try {
        final raw = await tab.controller.runJavaScriptReturningResult(
          'document.documentElement.outerHTML',
        );
        String renderedHtml;
        try {
          renderedHtml = jsonDecode(raw.toString()) as String;
        } catch (_) {
          renderedHtml = raw.toString();
        }
        for (final v in VideoHarvesterEngine.extractFromRenderedHtml(
          renderedHtml,
          tab.url,
          titleHint: tab.title,
        )) {
          merged.putIfAbsent(v.url, () => v);
        }
      } catch (_) {
        // JS-Auswertung kann z.B. bei restriktiver Content-Security-Policy
        // fehlschlagen — dann bleiben wenigstens die anderen Ebenen.
      }

      // Ebene 3: der bisherige Netzwerk-Crawl — findet Treffer auf
      // verlinkten Seiten (Embeds, weiterführende Player-Seiten), die im
      // aktuell offenen Tab selbst gar nicht sichtbar sind.
      for (final v in await compute(_harvestIsolate, tab.url)) {
        merged.putIfAbsent(v.url, () => v);
      }

      if (!mounted) return;
      if (merged.isEmpty) {
        _showNotification('Keine Videos gefunden');
        return;
      }
      setState(() => _notification = null);
      _showHarvesterSheet(merged.values.toList(), referer: tab.url);
    } catch (e) {
      _showNotification('Video Harvester fehlgeschlagen: $e');
    }
  }

  void _showHarvesterSheet(List<HarvestedVideo> results, {required String referer}) {
    String query = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NexusColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(NexusRadii.panel)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final filtered = query.trim().isEmpty
              ? results
              : results.where((v) {
                  final q = query.toLowerCase();
                  return v.title.toLowerCase().contains(q) ||
                      v.host.toLowerCase().contains(q) ||
                      v.url.toLowerCase().contains(q);
                }).toList();
          return DraggableScrollableSheet(
            initialChildSize: 0.6,
            expand: false,
            builder: (context, scrollController) => Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${results.length} Treffer',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    style: const TextStyle(color: NexusColors.textPrimary),
                    onChanged: (value) =>
                        setSheetState(() => query = value),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Filtern, z.B. nach Titel…',
                      hintStyle:
                          const TextStyle(color: NexusColors.textMuted),
                      prefixIcon: const Icon(Icons.search,
                          size: 20, color: NexusColors.textMuted),
                      filled: true,
                      fillColor: NexusColors.bgPill,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(NexusRadii.button),
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
                        const downloadable = {'MP4', 'WEBM', 'M3U8', 'MEDIA'};
                        final canDownload = downloadable.contains(v.type);
                        return ListTile(
                          title: Text(v.title.isEmpty ? v.host : v.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            canDownload
                                ? '${v.type} · ${v.status}'
                                : v.type == 'DASH'
                                    ? 'DASH erkannt — Download noch nicht unterstützt'
                                    : 'Nur Player-/Einbettungsseite — keine direkte '
                                        'Videodatei gefunden (z.B. YouTube-Links '
                                        'lassen sich so generell nicht extrahieren)',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: canDownload
                                ? null
                                : const TextStyle(color: NexusColors.textMuted),
                          ),
                          isThreeLine: !canDownload,
                          trailing: canDownload
                              ? IconButton(
                                  icon: const Icon(Icons.download,
                                      color: NexusColors.accentPrimary),
                                  onPressed: () => _downloadVideo(v, referer),
                                )
                              : const Icon(Icons.block,
                                  color: NexusColors.textMuted, size: 20),
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

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return const Scaffold(
        backgroundColor: NexusColors.bgBase,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final tab = _tabManager.activeTab;
    return Scaffold(
      backgroundColor: NexusColors.bgBase,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBarRow1(),
            _buildAddressBar(tab),
            _buildTabStrip(),
            Expanded(
              child: Stack(
                children: [
                  Row(
                    children: [
                      _buildSidebar(),
                      Expanded(child: _buildContent(tab)),
                    ],
                  ),
                  if (_notification != null) _buildBottomNotification(),
                ],
              ),
            ),
          ],
        ),
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
      child: WebViewWidget(controller: tab.controller),
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
