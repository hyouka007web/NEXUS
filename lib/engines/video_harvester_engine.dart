import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import '../models/harvested_video.dart';

/// Discovers publicly exposed video/player URLs. No DRM/login/CAPTCHA/access-
/// control bypass. 1:1-Verhalten zu Kotlins `VideoHarvesterEngine`.
class VideoHarvesterEngine {
  VideoHarvesterEngine._();

  static const int _maxHtmlBytes = 5 * 1024 * 1024;
  static const int _maxLinkedPages = 60;
  static const int _maxResults = 1000;
  static const String _userAgent = 'Mozilla/5.0 (Linux; NEXUS Browser/1.0)';

  static final RegExp _attrPattern = RegExp(
    r'''(?:href|src|data-src|data-url|data-video|data-file|content)\s*=\s*['"]([^'"]+)['"]''',
    caseSensitive: false,
  );
  static final RegExp _urlPattern = RegExp(
    r'''https?://[^\s"'<>\\]+''',
    caseSensitive: false,
  );
  static final RegExp _escapedUrlPattern = RegExp(
    r'''https?:\\?/\\?/[^\s"'<>]+''',
    caseSensitive: false,
  );
  static final RegExp _titlePattern = RegExp(
    r'<title[^>]*>(.*?)</title>',
    caseSensitive: false,
    dotAll: true,
  );

  static Future<List<HarvestedVideo>> harvest(
    String pageUrl, {
    bool deepInspect = true,
  }) async {
    final queue = Queue<_QueueItem>()..add(_QueueItem(pageUrl, 'Page'));
    final visited = <String>{};
    final result = <String, HarvestedVideo>{};

    while (queue.isNotEmpty &&
        visited.length < _maxLinkedPages &&
        result.length < _maxResults) {
      final item = queue.removeFirst();
      final normalizedPage = _normalize(item.url);
      if (normalizedPage == null || !visited.add(normalizedPage)) continue;

      final html = await _fetchHtml(normalizedPage);
      if (html == null) continue;

      final pageTitle = _extractTitle(html).isNotEmpty
          ? _extractTitle(html)
          : item.inheritedTitle;

      for (final candidate in _extractCandidates(html, normalizedPage)) {
        final normalized = _normalize(candidate);
        if (normalized == null) continue;
        final type = _classify(normalized);
        if (type == 'LINK') continue;
        String host;
        try {
          host = Uri.parse(normalized).host;
        } catch (_) {
          host = '';
        }
        final status = {'MP4', 'WEBM', 'M3U8', 'MEDIA'}.contains(type)
            ? 'MEDIA SOURCE'
            : 'PLAYER / VIDEO PAGE';
        result.putIfAbsent(
          normalized,
          () => HarvestedVideo(
            title: pageTitle,
            url: normalized,
            host: host,
            type: type,
            status: status,
          ),
        );
        if (deepInspect &&
            type == 'PLAYER' &&
            queue.length + visited.length < _maxLinkedPages) {
          queue.add(_QueueItem(normalized, pageTitle));
        }
      }
    }
    return result.values.toList();
  }

  static Future<String?> _fetchHtml(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..autoUncompress = true;
    try {
      final request = await client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 12));
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'text/html,application/xhtml+xml,application/json,text/plain,*/*;q=0.8',
      );
      final response =
          await request.close().timeout(const Duration(seconds: 20));
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length >= _maxHtmlBytes) break;
      }
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static List<String> _extractCandidates(String html, String baseUrl) {
    final out = <String>{};
    void add(String? raw) {
      if (raw == null || raw.trim().isEmpty) return;
      final value = _decode(raw.trim());
      if (value.startsWith('data:') ||
          value.startsWith('javascript:') ||
          value.startsWith('mailto:')) {
        return;
      }
      try {
        out.add(Uri.parse(baseUrl).resolve(value).toString());
      } catch (_) {
        // ignorieren, wie im Kotlin-Original (runCatching { }.getOrNull())
      }
    }

    for (final m in _attrPattern.allMatches(html)) {
      add(m.group(1));
    }
    for (final m in _urlPattern.allMatches(html)) {
      add(m.group(0));
    }
    for (final m in _escapedUrlPattern.allMatches(html)) {
      add(m.group(0)?.replaceAll(r'\/', '/'));
    }
    return out.toList();
  }

  static String? _normalize(String url) {
    try {
      final u = Uri.parse(url);
      final scheme = u.scheme.toLowerCase();
      if ((scheme != 'http' && scheme != 'https') || u.host.isEmpty) {
        return null;
      }
      return u.toString();
    } catch (_) {
      return null;
    }
  }

  static String _classify(String url) {
    String path;
    try {
      path = Uri.parse(url).path.toLowerCase();
    } catch (_) {
      path = '';
    }
    if (path.endsWith('.mp4') || path.endsWith('.m4v') || path.endsWith('.mov')) {
      return 'MP4';
    }
    if (path.endsWith('.webm')) return 'WEBM';
    if (path.endsWith('.m3u8')) return 'M3U8';
    if (path.endsWith('.ts')) return 'MEDIA';
    if (_isLikelyVideoPage(url)) return 'PLAYER';
    return 'LINK';
  }

  static bool _isLikelyVideoPage(String url) {
    final s = url.toLowerCase();
    const markers = [
      '/video', '/watch', '/embed', '/player', '/stream', '/trailer',
      '/episode', '/play', 'videoplayer', //
    ];
    return markers.any(s.contains);
  }

  static String _extractTitle(String html) {
    final match = _titlePattern.firstMatch(html);
    if (match == null) return '';
    final decoded = _decode(match.group(1) ?? '')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return decoded.length > 160 ? decoded.substring(0, 160) : decoded;
  }

  static String _decode(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(r'\/', '/');
}

class _QueueItem {
  final String url;
  final String inheritedTitle;
  const _QueueItem(this.url, this.inheritedTitle);
}
