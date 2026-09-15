import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nexus/models/download_entry.dart';
import 'package:nexus/models/harvested_media.dart';
import 'package:nexus/screens/mediathek_screen.dart';
import 'package:nexus/services/browser_controller.dart';
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
class HarvesterPanel extends StatelessWidget {
  const HarvesterPanel({super.key});

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
          title: 'HARVESTER (${items.length})',
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
                    return _HarvesterTile(media: media);
                  },
                ),
        );
      },
    );
  }
}

class _HarvesterTile extends StatelessWidget {
  final HarvestedMedia media;
  const _HarvesterTile({required this.media});

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
      leading: Icon(_icon, size: 18, color: NexusColors.accent),
      title: Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
      subtitle: Text('$_kindLabel · via ${media.discoveredVia}',
          style: const TextStyle(fontSize: 10, color: NexusColors.textSecondary)),
      trailing: IconButton(
        icon: const Icon(Icons.download_rounded, size: 18, color: NexusColors.accent),
        onPressed: () => showDownloadQualitySheet(context, media),
      ),
      onTap: () => showDownloadQualitySheet(context, media),
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
                      controller.downloader.download(
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
              Icon(
                entry.isDone
                    ? Icons.check_circle
                    : entry.isFailed
                        ? Icons.error
                        : Icons.downloading,
                size: 16,
                color: entry.isDone ? NexusColors.success : (entry.isFailed ? NexusColors.danger : NexusColors.accent),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
              ),
              if (entry.isActive)
                IconButton(
                  icon: const Icon(Icons.close, size: 14),
                  onPressed: () => controller.downloader.cancel(entry.id),
                )
              else
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 14),
                  onPressed: () => controller.downloader.remove(entry.id),
                ),
            ],
          ),
          if (entry.status == DownloadStatus.downloading)
            LinearProgressIndicator(
              value: entry.progress >= 0 ? entry.progress : null,
              minHeight: 3,
              backgroundColor: NexusColors.divider,
              valueColor: const AlwaysStoppedAnimation(NexusColors.accent),
            ),
          Text(
            entry.isFailed
                ? 'Fehler: ${entry.error ?? "unbekannt"}'
                : '${_formatBytes(entry.receivedBytes)} / ${_formatBytes(entry.totalBytes)}',
            style: const TextStyle(fontSize: 9, color: NexusColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
