import re

# 1. fix video_downloader.dart (Headers als optional named mit default Map)
with open('lib/engines/video_downloader.dart', 'r') as f:
    v_content = f.read()

# Nullable Map durch non-null Map mit Default-Wert ersetzen
v_content = v_content.replace('Map<String, String>? headers', 'Map<String, String> headers = const {}')
v_content = v_content.replace('[Map<String, String> headers = const {}]', '{Map<String, String> headers = const {}}')

# Falls an manchen Stellen noch Method-Calls auf Nullable Maps fehlschlagen:
v_content = re.sub(r'headers\[', 'headers?[', v_content)
v_content = re.sub(r'headers\.forEach', 'headers?.forEach', v_content)

with open('lib/engines/video_downloader.dart', 'w') as f:
    f.write(v_content)

# 2. fix browser_screen.dart (Zeile 718 / TabStrip reparieren)
with open('lib/screens/browser_screen.dart', 'r') as f:
    b_content = f.read()

# Die zerstörte TabStrip-Methode durch eine funktionierende ersetzen
clean_tab_strip = '''  Widget _buildPaneTabStrip(PaneState pane) {
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
  }'''

b_content = re.sub(r'Widget _buildPaneTabStrip\(PaneState pane\)\{.*', clean_tab_strip, b_content)

with open('lib/screens/browser_screen.dart', 'w') as f:
    f.write(b_content)

print("Patch angewendet.")
