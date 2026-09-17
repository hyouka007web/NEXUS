import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nexus/models/download_entry.dart';
import 'package:nexus/models/harvested_media.dart';
import 'package:nexus/screens/mediathek_screen.dart';
import 'package:nexus/services/browser_controller.dart';
import 'package:nexus/services/deep_harvester.dart';
import 'package:nexus/services/quality_matcher.dart';
import 'package:nexus/theme/nexus_theme.dart';

/// Panel-Container mit einheitlicher Breite/Überschrift für alle
/// ausklappbaren Sidebar-Panels.
class SidebarPanelShell extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  const SidebarPanelShell({super.key, required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      color: NexusColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1, color: NexusColors.textSecondary)),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          const Divider(height: 1, color: NexusColors.divider),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// TABS-PANEL
class TabsPanel extends StatelessWidget {
  const TabsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BrowserController>();
    return SidebarPanelShell(
      title: 'TABS (${controller.tabs.length})',
      child: ListView.builder(
        itemCount: controller.tabs.length,
        itemBuilder: (context, index) {
          final tab = controller.tabs[index];
          final active = tab.id == controller.activeTabId;
          return ListTile(
            dense: true,
            selected: active,
            selectedTileColor: NexusColors.accent.withOpacity(0.1),
            leading: Icon(Icons.circle, size: 9, color: NexusColors.tabAccentFor(tab.id)),
            title: Text(tab.title.isEmpty ? 'Neuer Tab' : tab.title,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
            subtitle: tab.isHome
                ? null
                : Text(tab.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
            trailing: IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: () => controller.closeTab(tab.id),
            ),
            onTap: () => controller.switchTab(tab.id),
          );
        },
      ),
    );
  }
}

/// HARVESTER-PANEL — zeigt alle im aktiven Tab gefundenen Medien.
class HarvesterPanel extends StatefulWidget {
  const HarvesterPanel({super.key});

  @override
  State<HarvesterPanel> createState() => _HarvesterPanelState();
}

class _HarvesterPanelState extends State<HarvesterPanel> {
  bool _selectMode = false;
  final Set<String> _selected = {};

  void _toggle(String key) {
    setState(() {
      if (_selected.contains(key)) {
        _selected.remove(key);
      } else {
        _selected.add(key);
      }
      if (_selected.isEmpty) _selectMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BrowserController>();
    final tab = controller.activeTab;
    if (tab == null) return const SidebarPanelShell(title: 'HARVESTER', child: SizedBox());

    return AnimatedBuilder(
      animation: tab,
      builder: (context, _) {
        final items = tab.harvestedMedia;
        return SidebarPanelShell(
          title: _selectMode ? '${_selected.length} AUSGEWÄHLT' : 'HARVESTER (${items.length})',
          trailing: _selectMode
              ? IconButton(
                  icon: const Icon(Icons.close, size: 16, color: NexusColors.textSecondary),
                  tooltip: 'Auswahl beenden',
                  onPressed: () => setState(() {
                    _selectMode = false;
                    _selected.clear();
                  }),
                )
              : null,
          child: Column(
            children: [
              Expanded(
                child: items.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Noch keine Medien gefunden. Lade eine Seite mit Video/Audio — der Scraper läuft automatisch bei jedem Seitenaufruf.',
                          style: TextStyle(fontSize: 11, color: NexusColors.textSecondary),
                        ),
                      )
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final media = items[index];
                          final key = media.dedupeKey;
                          return _HarvesterTile(
                            media: media,
                            selectMode: _selectMode,
                            selected: _selected.contains(key),
                            onLongPress: () => setState(() {
                              _selectMode = true;
                              _selected.add(key);
                            }),
                            onToggle: () => _toggle(key),
                          );
                        },
                      ),
              ),
              if (_selectMode)
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: ElevatedButton.icon(
                    onPressed: _selected.isEmpty
                        ? null
                        : () async {
                            final chosen = items.where((m) => _selected.contains(m.dedupeKey)).toList();
                            await showBatchQualitySheet(context, chosen);
                            setState(() {
                              _selectMode = false;
                              _selected.clear();
                            });
                          },
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: Text('${_selected.length} herunterladen'),
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 40)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _HarvesterTile extends StatelessWidget {
  final HarvestedMedia media;
  final bool selectMode;
  final bool selected;
  final VoidCallback onLongPress;
  final VoidCallback onToggle;

  const _HarvesterTile({
    required this.media,
    required this.selectMode,
    required this.selected,
    required this.onLongPress,
    required this.onToggle,
  });

  IconData get _icon {
    switch (media.kind) {
      case MediaKind.hls:
      case MediaKind.dash:
        return Icons.live_tv_rounded;
      case MediaKind.audio:
        return Icons.audiotrack_rounded;
      default:
        return Icons.movie_creation_outlined;
    }
  }

  String get _kindLabel {
    switch (media.kind) {
      case MediaKind.hls:
        return 'HLS-Stream';
      case MediaKind.dash:
        return 'DASH-Stream';
      case MediaKind.audio:
        return 'Audio';
      default:
        return 'Video';
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileName = Uri.tryParse(media.url)?.pathSegments.lastOrNullOrEmpty() ?? media.url;
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: NexusColors.accent.withOpacity(0.1),
      onLongPress: selectMode ? null : onLongPress,
      leading: selectMode
          ? Checkbox(value: selected, onChanged: (_) => onToggle())
          : Icon(_icon, size: 18, color: NexusColors.accent),
      title: Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
      subtitle: Text('$_kindLabel · via ${media.discoveredVia}',
          style: const TextStyle(fontSize: 10, color: NexusColors.textSecondary)),
      trailing: selectMode
          ? null
          : IconButton(
              icon: const Icon(Icons.download_rounded, size: 18, color: NexusColors.accent),
              onPressed: () => showDownloadQualitySheet(context, media),
            ),
      onTap: selectMode ? onToggle : () => showDownloadQualitySheet(context, media),
    );
  }
}

extension _LastOrEmpty on List<String> {
  String lastOrNullOrEmpty() => isEmpty ? '' : last;
}

/// Bottom-Sheet zur Qualitätsauswahl vor dem Download.
Future<void> showDownloadQualitySheet(BuildContext context, HarvestedMedia media) async {
  final controller = context.read<BrowserController>();
  final variants = media.variants.isNotEmpty
      ? media.variants
      : [MediaVariant(url: media.url, label: 'Original')];

  await showModalBottomSheet(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(media.suggestedFileName,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              const Text('Qualität wählen', style: TextStyle(fontSize: 11, color: NexusColors.textSecondary)),
              const SizedBox(height: 8),
              ...variants.map((v) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.high_quality_outlined, size: 18, color: NexusColors.accent),
                    title: Text(v.label),
                    subtitle: v.bandwidth > 0 ? Text('${(v.bandwidth / 1000).round()} kbps') : null,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      controller.downloader.enqueue(
                        v,
                        title: media.suggestedFileName,
                        type: media.kind.name,
                      );
                      controller.showPanel(SidebarPanel.downloads);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Download gestartet — siehe Mediathek')),
                      );
                    },
                  )),
            ],
          ),
        ),
      );
    },
  );
}

/// Batch-Download-Sheet (Master-Prompt Kapitel 20): eine Zielqualität für
/// mehrere ausgewählte Funde auf einmal. Für Medien ohne exakten Treffer
/// wird automatisch die nächstgelegene verfügbare Qualität verwendet.
Future<void> showBatchQualitySheet(BuildContext context, List<HarvestedMedia> items) async {
  final controller = context.read<BrowserController>();

  await showModalBottomSheet(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${items.length} Videos ausgewählt', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text(
                'Zielqualität — falls ein Video sie nicht hat, wird automatisch die nächstgelegene verfügbare Qualität gewählt.',
                style: TextStyle(fontSize: 11, color: NexusColors.textSecondary),
              ),
              const SizedBox(height: 8),
              ...QualityTarget.values.map((target) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.high_quality_outlined, size: 18, color: NexusColors.accent),
                    title: Text(qualityTargetLabels[target]!),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await _runBatchDownload(context, controller, items, target);
                    },
                  )),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> _runBatchDownload(
  BuildContext context,
  BrowserController controller,
  List<HarvestedMedia> items,
  QualityTarget target,
) async {
  controller.showPanel(SidebarPanel.downloads);
  int started = 0;
  for (final media in items) {
    // Für HLS/DASH-Funde, die noch nicht aufgelöst wurden (z.B. gerade erst
    // entdeckt), die Qualitätsstufen jetzt nachträglich auflösen.
    var variants = media.variants;
    if (variants.isEmpty && (media.kind == MediaKind.hls || media.kind == MediaKind.dash)) {
      variants = await DeepHarvester.resolveVariants(media);
    }
    if (variants.isEmpty) {
      variants = [MediaVariant(url: media.url, label: 'Original')];
    }
    final chosen = pickNearestVariant(variants, target);
    controller.downloader.enqueue(chosen, title: media.suggestedFileName, type: media.kind.name);
    started++;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$started Download(s) gestartet — siehe Mediathek')),
    );
  }
}

/// DOWNLOADS-PANEL
class DownloadsPanel extends StatelessWidget {
  const DownloadsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BrowserController>();
    return AnimatedBuilder(
      animation: controller.downloader,
      builder: (context, _) {
        final items = controller.downloader.downloads;
        return SidebarPanelShell(
          title: 'DOWNLOADS (${items.length})',
          trailing: IconButton(
            icon: const Icon(Icons.open_in_full, size: 16, color: NexusColors.textSecondary),
            tooltip: 'Vollbild öffnen',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MediathekScreen()),
            ),
          ),
          child: items.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Noch keine Downloads.', style: TextStyle(fontSize: 11, color: NexusColors.textSecondary)),
                )
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) => _DownloadTile(entry: items[index]),
                ),
        );
      },
    );
  }
}

class _DownloadTile extends StatelessWidget {
  final DownloadEntry entry;
  const _DownloadTile({required this.entry});

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '?';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
  }

  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '';
    return '${_formatBytes(bytesPerSec.round())}/s';
  }

  String _formatEta(int? seconds) {
    if (seconds == null || seconds <= 0) return '';
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${(seconds / 60).round()}min';
    return '${(seconds / 3600).toStringAsFixed(1)}h';
  }

  IconData get _statusIcon {
    switch (entry.status) {
      case DownloadStatus.completed:
        return Icons.check_circle;
      case DownloadStatus.failed:
        return Icons.error;
      case DownloadStatus.paused:
        return Icons.pause_circle_outline;
      case DownloadStatus.queued:
        return Icons.schedule;
      case DownloadStatus.canceled:
        return Icons.cancel_outlined;
      case DownloadStatus.downloading:
        return Icons.downloading;
    }
  }

  Color get _statusColor {
    switch (entry.status) {
      case DownloadStatus.completed:
        return NexusColors.success;
      case DownloadStatus.failed:
        return NexusColors.danger;
      case DownloadStatus.paused:
      case DownloadStatus.queued:
      case DownloadStatus.canceled:
        return NexusColors.textSecondary;
      case DownloadStatus.downloading:
        return NexusColors.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<BrowserController>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_statusIcon, size: 16, color: _statusColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
              ),
              if (entry.status == DownloadStatus.downloading)
                IconButton(
                  icon: const Icon(Icons.pause, size: 14),
                  tooltip: 'Pausieren',
                  onPressed: () => controller.downloader.pause(entry.id),
                )
              else if (entry.canResume)
                IconButton(
                  icon: const Icon(Icons.play_arrow, size: 14, color: NexusColors.accent),
                  tooltip: 'Fortsetzen',
                  onPressed: () => controller.downloader.resume(entry.id),
                )
              else if (entry.isPaused)
                IconButton(
                  icon: const Icon(Icons.replay, size: 14),
                  tooltip: 'Server unterstützt kein Fortsetzen — neu starten',
                  onPressed: () => controller.downloader.retry(entry.id),
                )
              else if (entry.isFailed)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 14),
                  tooltip: 'Erneut versuchen',
                  onPressed: () => controller.downloader.retry(entry.id),
                ),
              if (entry.isActive || entry.isPaused)
                IconButton(
                  icon: const Icon(Icons.close, size: 14),
                  tooltip: 'Abbrechen',
                  onPressed: () => controller.downloader.cancel(entry.id),
                )
              else if (!entry.isActive)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 14),
                  tooltip: 'Entfernen',
                  onPressed: () => controller.downloader.remove(entry.id),
                ),
            ],
          ),
          if (entry.status == DownloadStatus.downloading || entry.status == DownloadStatus.paused)
            LinearProgressIndicator(
              value: entry.progress >= 0 ? entry.progress : null,
              minHeight: 3,
              backgroundColor: NexusColors.divider,
              valueColor: AlwaysStoppedAnimation(entry.isPaused ? NexusColors.textSecondary : NexusColors.accent),
            ),
          Text(
            entry.isFailed
                ? 'Fehler: ${entry.error ?? "unbekannt"}${entry.retryCount > 0 ? " (Versuch ${entry.retryCount + 1})" : ""}'
                : entry.status == DownloadStatus.queued
                    ? 'In Warteschlange…'
                    : [
                        '${_formatBytes(entry.receivedBytes)} / ${_formatBytes(entry.totalBytes)}',
                        if (entry.status == DownloadStatus.downloading && entry.speedBytesPerSec > 0) _formatSpeed(entry.speedBytesPerSec),
                        if (entry.status == DownloadStatus.downloading && entry.etaSeconds != null) 'ETA ${_formatEta(entry.etaSeconds)}',
                      ].join(' · '),
            style: const TextStyle(fontSize: 9, color: NexusColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
