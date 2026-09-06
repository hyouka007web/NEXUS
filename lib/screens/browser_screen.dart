import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../engines/scraper_engine.dart';
import '../engines/video_downloader.dart';
import '../engines/video_harvester_engine.dart';
import '../models/block_event.dart';
import '../models/harvested_video.dart';
import '../models/scrape_result.dart';
import '../models/tab_model.dart';
import '../state/download_repository.dart';
import '../state/tab_manager.dart';
import '../theme/nexus_theme.dart';
import 'mediathek_screen.dart';
import 'start_page.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final _tabManager = TabManager();
  final _urlController = TextEditingController();
  bool _sidebarExpanded = false;
  String? _notification;
  VoidCallback? _notificationAction;
  String? _notificationActionLabel;

  @override
  void initState() {
    super.initState();
    _tabManager.addListener(_onTabManagerChanged);
    _syncUrlField();
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
      final ScrapeResult result = await ScraperEngine.scrape(tab.url);
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
    _showNotification('Durchsuche verlinkte Seiten…',
        duration: const Duration(seconds: 30));
    try {
      final results = await VideoHarvesterEngine.harvest(tab.url);
      if (!mounted) return;
      if (results.isEmpty) {
        _showNotification('Keine Videos gefunden');
        return;
      }
      setState(() => _notification = null);
      _showHarvesterSheet(results, referer: tab.url);
    } catch (e) {
      _showNotification('Video Harvester fehlgeschlagen: $e');
    }
  }

  void _showHarvesterSheet(List<HarvestedVideo> results, {required String referer}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NexusColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(NexusRadii.panel)),
      ),
      builder: (context) => DraggableScrollableSheet(
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
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: results.length,
                  itemBuilder: (context, i) {
                    final v = results[i];
                    return ListTile(
                      title: Text(v.title.isEmpty ? v.host : v.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${v.type} · ${v.status}',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                        icon: const Icon(Icons.download,
                            color: NexusColors.accentPrimary),
                        onPressed: () => _downloadVideo(v, referer),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
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
    } catch (e) {
      DownloadRepository.instance.fail(task, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: NexusColors.textPrimary),
            color: NexusColors.bgSurfaceRaised,
            onSelected: (value) {
              if (value == 'mediathek') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MediathekScreen()),
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'mediathek', child: Text('Mediathek')),
            ],
          ),
        ],
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
      return StartPage(onSubmit: (query) => _tabManager.navigateInput(query));
    }
    return WebViewWidget(controller: tab.controller);
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
