import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:nexus/models/download_entry.dart';
import 'package:nexus/services/browser_controller.dart';
import 'package:nexus/screens/video_player_screen.dart';
import 'package:nexus/theme/nexus_theme.dart';

enum _LibraryTab { inProgress, completed }
enum _SortMode { newest, oldest, nameAsc, sizeDesc }

const Map<DownloadCategory, String> _categoryLabels = {
  DownloadCategory.video: 'VIDEOS',
  DownloadCategory.audio: 'AUDIO',
  DownloadCategory.pdf: 'PDF',
  DownloadCategory.epub: 'EPUB',
  DownloadCategory.image: 'IMAGES',
  DownloadCategory.other: 'OTHER',
};

const Map<DownloadCategory, IconData> _categoryIcons = {
  DownloadCategory.video: Icons.movie_creation_outlined,
  DownloadCategory.audio: Icons.audiotrack_rounded,
  DownloadCategory.pdf: Icons.picture_as_pdf_outlined,
  DownloadCategory.epub: Icons.menu_book_outlined,
  DownloadCategory.image: Icons.image_outlined,
  DownloadCategory.other: Icons.insert_drive_file_outlined,
};

/// Die vollständige NEXUS-Mediathek (Master-Prompt Kapitel 22-23):
/// ALL/VIDEOS/AUDIO/PDF/EPUB/IMAGES/OTHER-Filter, IN PROGRESS/COMPLETED,
/// Suche, Sortierung, Mehrfachauswahl + Batch-Löschen, Datei öffnen/teilen.
class MediathekScreen extends StatefulWidget {
  const MediathekScreen({super.key});

  @override
  State<MediathekScreen> createState() => _MediathekScreenState();
}

class _MediathekScreenState extends State<MediathekScreen> {
  _LibraryTab _tab = _LibraryTab.inProgress;
  DownloadCategory? _category; // null = ALL
  _SortMode _sort = _SortMode.newest;
  String _query = '';
  bool _selectMode = false;
  final Set<String> _selected = {};

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '?';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
  }

  List<DownloadEntry> _filtered(List<DownloadEntry> all) {
    var list = all.where((e) {
      // "In Progress" = alles, wo noch etwas zu tun ist (auch fehlgeschlagene
      // Downloads — die will man direkt retry-en, nicht in "Completed" suchen).
      // "Completed" = wirklich abgeschlossene Vorgänge (fertig oder abgebrochen).
      final matchesTab = _tab == _LibraryTab.inProgress
          ? (e.isActive || e.isPaused || e.isFailed)
          : (e.isDone || e.status == DownloadStatus.canceled);
      if (!matchesTab) return false;
      if (_category != null && e.category != _category) return false;
      if (_query.trim().isNotEmpty && !e.title.toLowerCase().contains(_query.trim().toLowerCase())) return false;
      return true;
    }).toList();

    switch (_sort) {
      case _SortMode.newest:
        list.sort((a, b) => b.startedAt.compareTo(a.startedAt));
        break;
      case _SortMode.oldest:
        list.sort((a, b) => a.startedAt.compareTo(b.startedAt));
        break;
      case _SortMode.nameAsc:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case _SortMode.sizeDesc:
        list.sort((a, b) => b.totalBytes.compareTo(a.totalBytes));
        break;
    }
    return list;
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
      if (_selected.isEmpty) _selectMode = false;
    });
  }

  Future<void> _batchDelete(BrowserController controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexusColors.raised,
        title: const Text('Löschen?'),
        content: Text('${_selected.length} Datei(en) endgültig löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen', style: TextStyle(color: NexusColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await controller.downloader.removeMany(_selected);
    setState(() {
      _selected.clear();
      _selectMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BrowserController>();

    return Scaffold(
      backgroundColor: NexusColors.background,
      appBar: AppBar(
        title: Text(_selectMode ? '${_selected.length} ausgewählt' : 'NEXUS Mediathek'),
        actions: [
          if (_selectMode)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Ausgewählte löschen',
              onPressed: _selected.isEmpty ? null : () => _batchDelete(controller),
            )
          else
            PopupMenuButton<_SortMode>(
              icon: const Icon(Icons.sort_rounded),
              onSelected: (mode) => setState(() => _sort = mode),
              itemBuilder: (_) => const [
                PopupMenuItem(value: _SortMode.newest, child: Text('Neueste zuerst')),
                PopupMenuItem(value: _SortMode.oldest, child: Text('Älteste zuerst')),
                PopupMenuItem(value: _SortMode.nameAsc, child: Text('Name A-Z')),
                PopupMenuItem(value: _SortMode.sizeDesc, child: Text('Größe')),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Mediathek durchsuchen…',
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _CategoryChip(label: 'ALL', selected: _category == null, onTap: () => setState(() => _category = null)),
                const SizedBox(width: 6),
                for (final cat in DownloadCategory.values) ...[
                  _CategoryChip(
                    label: _categoryLabels[cat]!,
                    icon: _categoryIcons[cat],
                    selected: _category == cat,
                    onTap: () => setState(() => _category = cat),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: _TabPill(
                    label: 'IN PROGRESS',
                    selected: _tab == _LibraryTab.inProgress,
                    onTap: () => setState(() => _tab = _LibraryTab.inProgress),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TabPill(
                    label: 'COMPLETED',
                    selected: _tab == _LibraryTab.completed,
                    onTap: () => setState(() => _tab = _LibraryTab.completed),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: controller.downloader,
              builder: (context, _) {
                final items = _filtered(controller.downloader.downloads);
                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      _tab == _LibraryTab.inProgress ? 'Keine laufenden Downloads.' : 'Noch nichts abgeschlossen.',
                      style: const TextStyle(color: NexusColors.textSecondary),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final entry = items[index];
                    final selected = _selected.contains(entry.id);
                    return _MediaCard(
                      entry: entry,
                      selectMode: _selectMode,
                      selected: selected,
                      formatBytes: _formatBytes,
                      onLongPress: () => setState(() {
                        _selectMode = true;
                        _selected.add(entry.id);
                      }),
                      onTapSelect: () => _toggleSelect(entry.id),
                      onOpen: () async {
                        if (entry.localPath == null) return;
                        // Video/Audio: eigener NEXUS-Player mit Resume-Funktion.
                        // Alles andere (PDF/EPUB/Bilder/Sonstiges): Systemapp,
                        // bis es einen eigenen Reader gibt (Phase 5).
                        if (entry.category == DownloadCategory.video || entry.category == DownloadCategory.audio) {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => NexusVideoPlayerScreen(path: entry.localPath!, title: entry.title)),
                          );
                          return;
                        }
                        final result = await OpenFilex.open(entry.localPath!);
                        if (result.type != ResultType.done && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Konnte Datei nicht öffnen: ${result.message}')),
                          );
                        }
                      },
                      onShare: () {
                        if (entry.localPath == null) return;
                        Share.shareXFiles([XFile(entry.localPath!)], text: entry.title);
                      },
                      onOpenFolder: () async {
                        if (entry.localPath == null) return;
                        final dir = entry.localPath!.substring(0, entry.localPath!.lastIndexOf('/'));
                        await OpenFilex.open(dir);
                      },
                      onDelete: () => controller.downloader.remove(entry.id),
                      onPause: () => controller.downloader.pause(entry.id),
                      onResume: () => controller.downloader.resume(entry.id),
                      onRetry: () => controller.downloader.retry(entry.id),
                      onCancel: () => controller.downloader.cancel(entry.id),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryChip({required this.label, this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: selected ? NexusColors.energyGradientCompact : null,
          color: selected ? null : NexusColors.surface,
          border: selected ? null : Border.all(color: NexusColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) Icon(icon, size: 13, color: selected ? Colors.black : NexusColors.textSecondary),
            if (icon != null) const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, color: selected ? Colors.black : NexusColors.textSecondary, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabPill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? NexusColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border(bottom: BorderSide(color: selected ? NexusColors.accent : Colors.transparent, width: 2)),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: selected ? NexusColors.textPrimary : NexusColors.textSecondary)),
      ),
    );
  }
}

class _MediaCard extends StatelessWidget {
  final DownloadEntry entry;
  final bool selectMode;
  final bool selected;
  final String Function(int) formatBytes;
  final VoidCallback onLongPress;
  final VoidCallback onTapSelect;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback onOpenFolder;
  final VoidCallback onDelete;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  const _MediaCard({
    required this.entry,
    required this.selectMode,
    required this.selected,
    required this.formatBytes,
    required this.onLongPress,
    required this.onTapSelect,
    required this.onOpen,
    required this.onShare,
    required this.onOpenFolder,
    required this.onDelete,
    required this.onPause,
    required this.onResume,
    required this.onRetry,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: selected ? NexusColors.raised : NexusColors.surface,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: selected ? const BorderSide(color: NexusColors.accent) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onLongPress: onLongPress,
        onTap: selectMode ? onTapSelect : (entry.isDone ? onOpen : null),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              if (selectMode)
                Checkbox(value: selected, onChanged: (_) => onTapSelect())
              else
                CircleAvatar(
                  backgroundColor: NexusColors.accent,
                  child: Icon(_categoryIcons[entry.category] ?? Icons.insert_drive_file_outlined, color: Colors.black, size: 18),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 2),
                    if (entry.isActive || entry.isPaused)
                      LinearProgressIndicator(
                        value: entry.progress >= 0 ? entry.progress : null,
                        minHeight: 3,
                        backgroundColor: NexusColors.divider,
                        valueColor: AlwaysStoppedAnimation(entry.isPaused ? NexusColors.textSecondary : NexusColors.accent),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      entry.isFailed
                          ? 'Fehler: ${entry.error ?? "unbekannt"}${entry.retryCount > 0 ? " (Versuch ${entry.retryCount + 1})" : ""}'
                          : '${formatBytes(entry.receivedBytes)} / ${formatBytes(entry.totalBytes)} · ${entry.type.toUpperCase()}',
                      style: const TextStyle(fontSize: 10, color: NexusColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (!selectMode) _actions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions() {
    switch (entry.status) {
      case DownloadStatus.downloading:
        return Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.pause, size: 18), onPressed: onPause),
          IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onCancel),
        ]);
      case DownloadStatus.queued:
        return IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onCancel);
      case DownloadStatus.paused:
        return Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            icon: Icon(entry.canResume ? Icons.play_arrow : Icons.replay, size: 18, color: NexusColors.accent),
            onPressed: entry.canResume ? onResume : onRetry,
          ),
          IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onCancel),
        ]);
      case DownloadStatus.failed:
        return Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            icon: Icon(entry.canResume ? Icons.play_arrow : Icons.refresh, size: 18, color: NexusColors.accent),
            onPressed: entry.canResume ? onResume : onRetry,
          ),
          IconButton(icon: const Icon(Icons.delete_outline, size: 18), onPressed: onDelete),
        ]);
      case DownloadStatus.completed:
        return PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 18),
          onSelected: (v) {
            switch (v) {
              case 'open':
                onOpen();
                break;
              case 'share':
                onShare();
                break;
              case 'folder':
                onOpenFolder();
                break;
              case 'delete':
                onDelete();
                break;
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'open', child: Text('Öffnen')),
            PopupMenuItem(value: 'share', child: Text('Teilen')),
            PopupMenuItem(value: 'folder', child: Text('Ordner öffnen')),
            PopupMenuItem(value: 'delete', child: Text('Löschen')),
          ],
        );
      case DownloadStatus.canceled:
        return IconButton(icon: const Icon(Icons.delete_outline, size: 18), onPressed: onDelete);
    }
  }
}
