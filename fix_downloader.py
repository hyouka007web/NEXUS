with open('lib/engines/video_downloader.dart', 'r') as f:
    content = f.read()

# 1. Alle Methodensignaturen von {Map...} oder Map... = const {} auf [Map<String, String> headers = const {}] umstellen
import re
content = re.sub(
    r'(Future<[^\>]+>\s+\w+\([^)]*?)(?:\{\s*Map<String,\s*String>\s+headers\s*=\s*const\s*\{\},\s*\}|Map<String,\s*String>\s+headers\s*=\s*const\s*\{\},?)',
    r'\1[Map<String, String> headers = const {}]',
    content
)

# Fallback für die Methoden-Signaturen
content = content.replace('Map<String, String> headers = const {},', 'Map<String, String> headers = const {}')
content = content.replace('{Map<String, String> headers = const {}}', '[Map<String, String> headers = const {}]')

# 2. Aufrufe korrigieren, falls irgendwo noch named übergeben wird
content = content.replace('headers: headers', 'headers')

with open('lib/engines/video_downloader.dart', 'w') as f:
    f.write(content)

print("video_downloader.dart erfolgreich repariert.")
