import 'package:flutter/material.dart';
import '../state/tab_manager.dart';
import '../theme/nexus_theme.dart';

class PaletteItem {
  const PaletteItem(this.label, this.category, this.icon, this.onRun, {this.hint, this.commandId});
  final String label;
  final String category;
  final IconData icon;
  final VoidCallback onRun;
  final String? hint;
  final String? commandId;
}

class CommandPalette extends StatefulWidget {
  const CommandPalette({super.key, required this.tabManager, required this.items});
  final TabManager tabManager;
  final List<PaletteItem> items;
  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final controller = TextEditingController();
  final focus = FocusNode();
  int selected = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus());
  }

  @override
  void dispose() {
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  bool _fuzzy(String query, String source) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return true;
    final s = source.toLowerCase();
    var i = 0;
    for (final c in s.split('')) {
      if (i < q.length && c == q[i]) i++;
    }
    return i == q.length;
  }

  @override
  Widget build(BuildContext context) {
    final tabs = widget.tabManager.tabs.map((t) {
      return PaletteItem(
        t.isHome ? 'Neuer Tab' : t.title,
        'Tabs',
        Icons.tab,
        () => widget.tabManager.switchTab(t.id),
        hint: t.url,
      );
    }).toList();
    final all = [...widget.items, ...tabs];
    final filtered = all.where((item) {
      return _fuzzy(controller.text, item.label) ||
          _fuzzy(controller.text, item.category) ||
          _fuzzy(controller.text, item.hint ?? '');
    }).toList();
    if (selected >= filtered.length) {
      selected = filtered.isEmpty ? 0 : filtered.length - 1;
    }

    return Material(
      color: Colors.transparent,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
          child: Container(
            margin: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: NexusColors.bgSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: NexusColors.border),
            ),
            child: Column(
              children: [
                TextField(
                  controller: controller,
                  focusNode: focus,
                  autofocus: true,
                  onChanged: (_) => setState(() => selected = 0),
                  onSubmitted: (_) {
                    if (filtered.isNotEmpty) {
                      Navigator.pop(context);
                      filtered[selected].onRun();
                    }
                  },
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Befehl, Tab, Bookmark oder Verlauf suchen…',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(18),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final active = index == selected;
                      return InkWell(
                        onTap: () {
                          Navigator.pop(context);
                          item.onRun();
                        },
                        onHover: (_) => setState(() => selected = index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                          color: active ? NexusColors.bgSurfaceRaised : Colors.transparent,
                          child: Row(
                            children: [
                              Icon(item.icon, color: active ? NexusColors.accentPrimary : NexusColors.textMuted, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.label, style: const TextStyle(fontSize: 14)),
                                    Text(
                                      item.category + (item.hint == null ? '' : ' · ${item.hint}'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11, color: NexusColors.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      const Text('↑↓ auswählen', style: TextStyle(fontSize: 11, color: NexusColors.textMuted)),
                      const Spacer(),
                      Text('${filtered.length} Treffer · Esc schließen', style: const TextStyle(fontSize: 11, color: NexusColors.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
