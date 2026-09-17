import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:nexus/models/start_page_widget.dart';
import 'package:nexus/models/workspace.dart';
import 'package:nexus/theme/nexus_theme.dart';

/// Start-Page eines Workspace (Master-Prompt Kapitel 11): frei
/// konfigurierbares Widget-System mit Website-Shortcuts, echten
/// eingebetteten Web-Panels, Uhr und Notizen. Drag & Drop zum Neuordnen,
/// "+"-Kachel zum Hinzufügen, Layout wird pro Workspace gespeichert.
class StartPage extends StatefulWidget {
  final Workspace workspace;
  final void Function(String url) onOpenUrl;
  final void Function(List<StartPageWidgetConfig> widgets) onLayoutChanged;

  const StartPage({
    super.key,
    required this.workspace,
    required this.onOpenUrl,
    required this.onLayoutChanged,
  });

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> {
  bool _editMode = false;

  List<StartPageWidgetConfig> get _all => widget.workspace.startPageWidgets;
  List<StartPageWidgetConfig> get _tiles =>
      _all.where((w) => w.type != StartPageWidgetType.webPanel).toList();
  List<StartPageWidgetConfig> get _panels =>
      _all.where((w) => w.type == StartPageWidgetType.webPanel).toList();

  void _commit(List<StartPageWidgetConfig> merged) {
    setState(() {}); // lokale Reihenfolge in widget.workspace.startPageWidgets ist bereits mutiert
    widget.onLayoutChanged(merged);
  }

  void _reorderTiles(int oldIndex, int newIndex) {
    final tiles = List<StartPageWidgetConfig>.from(_tiles);
    if (newIndex > oldIndex) newIndex--;
    final item = tiles.removeAt(oldIndex);
    tiles.insert(newIndex, item);
    _commit([...tiles, ..._panels]);
  }

  void _reorderPanels(int oldIndex, int newIndex) {
    final panels = List<StartPageWidgetConfig>.from(_panels);
    // Schutz: der "+"-Button ist ein zusätzliches Listenelement ohne
    // eigenen Eintrag in _panels — Indizes außerhalb der Panel-Liste
    // (z.B. weil der Button selbst gezogen wurde) einfach ignorieren.
    if (oldIndex < 0 || oldIndex >= panels.length) return;
    if (newIndex > oldIndex) newIndex--;
    if (newIndex < 0) newIndex = 0;
    if (newIndex > panels.length) newIndex = panels.length;
    final item = panels.removeAt(oldIndex);
    panels.insert(newIndex, item);
    _commit([..._tiles, ...panels]);
  }

  void _remove(StartPageWidgetConfig config) {
    final updated = _all.where((w) => w.id != config.id).toList();
    _commit(updated);
  }

  void _add(StartPageWidgetConfig config) {
    _commit([..._all, config]);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: NexusColors.background,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Row(
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => NexusColors.energyGradient.createShader(bounds),
                    child: Text(widget.workspace.name, style: NexusFonts.heading(size: 22)),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(_editMode ? Icons.check_rounded : Icons.edit_outlined, color: NexusColors.accent),
                    tooltip: _editMode ? 'Fertig' : 'Layout bearbeiten',
                    onPressed: () => setState(() => _editMode = !_editMode),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverToBoxAdapter(
              child: _TileWrapReorder(
                tiles: _tiles,
                editMode: _editMode,
                onReorder: _reorderTiles,
                onOpen: (c) => c.type == StartPageWidgetType.shortcut && c.url != null ? widget.onOpenUrl(c.url!) : null,
                onRemove: _remove,
              ),
            ),
          ),
          if (_editMode)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              sliver: SliverToBoxAdapter(
                child: _AddTileButton(onAdd: _add),
              ),
            ),
          if (_panels.isNotEmpty || _editMode)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              sliver: SliverToBoxAdapter(
                child: Text('WEB PANELS', style: NexusFonts.uiMuted(size: 11)),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            sliver: SliverToBoxAdapter(
              child: ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                onReorder: _reorderPanels,
                children: [
                  for (final panel in _panels)
                    _WebPanelCard(key: ValueKey(panel.id), config: panel, editMode: _editMode, onRemove: () => _remove(panel)),
                  if (_editMode)
                    Padding(
                      key: const ValueKey('add_panel'),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _AddWebPanelButton(onAdd: _add),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Eigene, leichtgewichtige Drag&Drop-Implementierung für die
/// Shortcut-/Widget-Kacheln (Wrap statt GridView, damit sie natürlich
/// umbrechen — kein externes Grid-Paket nötig).
class _TileWrapReorder extends StatelessWidget {
  final List<StartPageWidgetConfig> tiles;
  final bool editMode;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(StartPageWidgetConfig) onOpen;
  final void Function(StartPageWidgetConfig) onRemove;

  const _TileWrapReorder({
    required this.tiles,
    required this.editMode,
    required this.onReorder,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: List.generate(tiles.length, (index) {
        final config = tiles[index];
        final tile = _StartTile(config: config, editMode: editMode, onOpen: () => onOpen(config), onRemove: () => onRemove(config));

        if (!editMode) return tile;

        return DragTarget<int>(
          onWillAcceptWithDetails: (details) => details.data != index,
          onAcceptWithDetails: (details) => onReorder(details.data, index),
          builder: (context, candidateData, rejectedData) {
            return LongPressDraggable<int>(
              data: index,
              feedback: Opacity(opacity: 0.85, child: SizedBox(width: 92, height: 92, child: tile)),
              childWhenDragging: Opacity(opacity: 0.3, child: tile),
              child: AnimatedScale(
                scale: candidateData.isNotEmpty ? 1.06 : 1.0,
                duration: const Duration(milliseconds: 120),
                child: tile,
              ),
            );
          },
        );
      }),
    );
  }
}

class _StartTile extends StatelessWidget {
  final StartPageWidgetConfig config;
  final bool editMode;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  const _StartTile({required this.config, required this.editMode, required this.onOpen, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: editMode ? null : onOpen,
      child: Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          color: NexusColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NexusColors.divider),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (config.type == StartPageWidgetType.clock)
                    const _ClockFace()
                  else if (config.type == StartPageWidgetType.note)
                    Icon(Icons.sticky_note_2_outlined, color: NexusColors.energyGold, size: 22)
                  else
                    Icon(iconForKey(config.iconKey), color: NexusColors.accent, size: 22),
                  const SizedBox(height: 6),
                  Text(
                    config.title,
                    style: NexusFonts.uiMuted(size: 10.5),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (editMode)
              Positioned(
                right: 2,
                top: 2,
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(color: NexusColors.danger, shape: BoxShape.circle),
                    child: const Icon(Icons.close, size: 11, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ClockFace extends StatefulWidget {
  const _ClockFace();
  @override
  State<_ClockFace> createState() => _ClockFaceState();
}

class _ClockFaceState extends State<_ClockFace> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return Text('${_two(_now.hour)}:${_two(_now.minute)}', style: NexusFonts.mono(size: 17, color: NexusColors.energyGreen, weight: FontWeight.w600));
  }
}

class _AddTileButton extends StatelessWidget {
  final void Function(StartPageWidgetConfig) onAdd;
  const _AddTileButton({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showAddSheet(context, onAdd),
      child: Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NexusColors.divider, style: BorderStyle.solid),
        ),
        child: const Icon(Icons.add_rounded, color: NexusColors.textMuted),
      ),
    );
  }
}

class _AddWebPanelButton extends StatelessWidget {
  final void Function(StartPageWidgetConfig) onAdd;
  const _AddWebPanelButton({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => _showAddSheet(context, onAdd, forcePanel: true),
      icon: const Icon(Icons.add_rounded, size: 16),
      label: const Text('Web Panel hinzufügen'),
      style: OutlinedButton.styleFrom(
        foregroundColor: NexusColors.accent,
        side: const BorderSide(color: NexusColors.divider),
        minimumSize: const Size(double.infinity, 46),
      ),
    );
  }
}

Future<void> _showAddSheet(BuildContext context, void Function(StartPageWidgetConfig) onAdd, {bool forcePanel = false}) async {
  StartPageWidgetType type = forcePanel ? StartPageWidgetType.webPanel : StartPageWidgetType.shortcut;
  final titleCtrl = TextEditingController();
  final urlCtrl = TextEditingController();
  String iconKey = 'web';

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return StatefulBuilder(builder: (sheetContext, setSheetState) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Widget hinzufügen', style: NexusFonts.ui(size: 15, weight: FontWeight.w700)),
              const SizedBox(height: 12),
              if (!forcePanel)
                Wrap(
                  spacing: 6,
                  children: [
                    ChoiceChip(
                      label: const Text('Shortcut'),
                      selected: type == StartPageWidgetType.shortcut,
                      onSelected: (_) => setSheetState(() => type = StartPageWidgetType.shortcut),
                    ),
                    ChoiceChip(
                      label: const Text('Web Panel'),
                      selected: type == StartPageWidgetType.webPanel,
                      onSelected: (_) => setSheetState(() => type = StartPageWidgetType.webPanel),
                    ),
                    ChoiceChip(
                      label: const Text('Uhr'),
                      selected: type == StartPageWidgetType.clock,
                      onSelected: (_) => setSheetState(() => type = StartPageWidgetType.clock),
                    ),
                    ChoiceChip(
                      label: const Text('Notiz'),
                      selected: type == StartPageWidgetType.note,
                      onSelected: (_) => setSheetState(() => type = StartPageWidgetType.note),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              if (type != StartPageWidgetType.clock)
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(hintText: 'Titel'),
                ),
              if (type == StartPageWidgetType.shortcut || type == StartPageWidgetType.webPanel) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(hintText: 'https://...'),
                  keyboardType: TextInputType.url,
                ),
              ],
              if (type == StartPageWidgetType.shortcut) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  children: startPageIconSet.entries.map((e) {
                    final selected = iconKey == e.key;
                    return GestureDetector(
                      onTap: () => setSheetState(() => iconKey = e.key),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          gradient: selected ? NexusColors.energyGradientCompact : null,
                          border: Border.all(color: NexusColors.divider),
                        ),
                        child: Icon(e.value, size: 16, color: selected ? Colors.black : NexusColors.textMuted),
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  final id = 'sp_${DateTime.now().millisecondsSinceEpoch}';
                  StartPageWidgetConfig config;
                  switch (type) {
                    case StartPageWidgetType.clock:
                      config = StartPageWidgetConfig(id: id, type: type, title: 'Uhr');
                      break;
                    case StartPageWidgetType.note:
                      config = StartPageWidgetConfig(id: id, type: type, title: titleCtrl.text.trim().isEmpty ? 'Notiz' : titleCtrl.text.trim());
                      break;
                    case StartPageWidgetType.webPanel:
                      if (urlCtrl.text.trim().isEmpty) return;
                      config = StartPageWidgetConfig(
                        id: id,
                        type: type,
                        title: titleCtrl.text.trim().isEmpty ? urlCtrl.text.trim() : titleCtrl.text.trim(),
                        url: _normalizeUrl(urlCtrl.text.trim()),
                      );
                      break;
                    case StartPageWidgetType.shortcut:
                      if (urlCtrl.text.trim().isEmpty) return;
                      config = StartPageWidgetConfig(
                        id: id,
                        type: type,
                        title: titleCtrl.text.trim().isEmpty ? urlCtrl.text.trim() : titleCtrl.text.trim(),
                        url: _normalizeUrl(urlCtrl.text.trim()),
                        iconKey: iconKey,
                      );
                      break;
                  }
                  onAdd(config);
                  Navigator.pop(sheetContext);
                },
                child: const Text('Hinzufügen'),
              ),
            ],
          ),
        );
      });
    },
  );
}

String _normalizeUrl(String input) {
  if (input.startsWith('http://') || input.startsWith('https://')) return input;
  return 'https://$input';
}

/// Karte mit echtem, live eingebettetem Web-Panel (Kapitel 11: "Web Panel
/// Mode" — die Webseite direkt auf der Startseite, statt nur als Kachel).
class _WebPanelCard extends StatelessWidget {
  final StartPageWidgetConfig config;
  final bool editMode;
  final VoidCallback onRemove;

  const _WebPanelCard({super.key, required this.config, required this.editMode, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: NexusColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NexusColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            color: NexusColors.raised,
            child: Row(
              children: [
                if (editMode) const Icon(Icons.drag_indicator, size: 16, color: NexusColors.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(config.title, style: NexusFonts.uiMuted(size: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (editMode)
                  GestureDetector(
                    onTap: onRemove,
                    child: const Icon(Icons.close, size: 15, color: NexusColors.danger),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 220,
            child: config.url == null
                ? const Center(child: Text('Keine URL', style: TextStyle(color: NexusColors.textMuted)))
                : IgnorePointer(
                    ignoring: editMode, // im Edit-Modus nicht versehentlich navigieren
                    child: InAppWebView(
                      initialUrlRequest: URLRequest(url: WebUri(config.url!)),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        supportZoom: false,
                        useHybridComposition: true,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
