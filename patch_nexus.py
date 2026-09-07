import re

# 1. Fix video_downloader.dart (Benannte Parameter mit optionalen eckigen Klammern [ ... ] reparieren)
with open('lib/engines/video_downloader.dart', 'r') as f:
    content = f.read()

# Ersetze die fehlerhaften Parameter-Signaturen durch echte optionale Positional-Parameter [ ... ]
content = re.sub(
    r'\{\s*Map<String,\s*String>\s+headers\s*=\s*const\s*<String,\s*String>\{\},\s*\}',
    '[Map<String, String> headers = const {}]',
    content
)
content = re.sub(
    r'Map<String,\s*String>\s+headers\s*=\s*const\s*<String,\s*String>\{\},',
    'Map<String, String>? headers,',
    content
)

with open('lib/engines/video_downloader.dart', 'w') as f:
    f.write(content)

# 2. Fix browser_screen.dart (Null Safety & Missing Bracket Fix)
with open('lib/screens/browser_screen.dart', 'r') as f:
    b_content = f.read()

# Fix Object? -> Object
b_content = b_content.replace('NetworkSniffer.parseCaptures(raw)', 'NetworkSniffer.parseCaptures(raw!)')

# Fix WebViewController? -> WebViewController (Fallback wenn null)
b_content = b_content.replace(
    'child: WebViewWidget(controller: _tabManager.activeTab?.controller),',
    'child: _tabManager.activeTab?.controller != null ? WebViewWidget(controller: _tabManager.activeTab!.controller) : const SizedBox.shrink(),'
)

with open('lib/screens/browser_screen.dart', 'w') as f:
    f.write(b_content)

print("Python Patching erfolgreich durchgeführt.")
