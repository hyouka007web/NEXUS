#!/data/data/com.termux/files/usr/bin/bash
set -e
[ -f "lib/engines/manifest_parser.dart" ] && sed -i "1i import \"dart:convert\";" lib/engines/manifest_parser.dart
[ -f "lib/screens/browser_screen.dart" ] && sed -i "1i import \"package:flutter/services.dart\";" lib/screens/browser_screen.dart
[ -f "lib/screens/browser_screen.dart" ] && sed -i "s/tab\.controller/_tabManager.activeTab?.controller/g" lib/screens/browser_screen.dart
[ -f "lib/engines/video_downloader.dart" ] && sed -i "s/Map<String, String> headers = const {},/Map<String, String> headers = const <String, String>{},/g" lib/engines/video_downloader.dart
git add -A && git commit -m "fix: resolve import and syntax errors" && git push origin main && rm -f fix.sh
