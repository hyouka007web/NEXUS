import 'dart:convert';
import 'dart:io';

import '../models/scrape_result.dart';

/// Public-resource scraper. Inspects only the delivered HTML; does not
/// bypass authentication, CAPTCHA, DRM or access controls. Deterministic
/// and bounded — 1:1-Verhalten zu Kotlins `ScraperEngine`.
///
/// Ein Unterschied zum Original ist erwähnenswert: `dart:io`s [HttpClient]
/// entpackt gzip-komprimierte Antworten standardmäßig automatisch
/// (`autoUncompress` ist per Default `true`). Der Bug, den wir im
/// Kotlin-Original erst nachträglich fixen mussten (gzip angefragt, aber
/// nie entpackt), kann hier grundsätzlich gar nicht erst auftreten.
class ScraperEngine {
  ScraperEngine._();

  static const int _maxHtmlBytes = 5 * 1024 * 1024;
  static const int _maxLinks = 2500;
  static const int _maxMedia = 1000;
  static const String _userAgent = 'Mozilla/5.0 (Linux; NEXUS Browser/1.0)';

  static final RegExp _attrPattern = RegExp(
    r'''(?:href|src|data-src|data-url|data-video|data-file|content)\s*=\s*['"]([^'"]+)['"]''',
    caseSensitive: false,
  );
  static final RegExp _srcSetPattern = RegExp(
    r'''(?:srcset|data-srcset)\s*=\s*['"]([^'"]+)['"]''',
    caseSensitive: false,
  );
  static final RegExp _titlePattern = RegExp(
    r'<title[^>]*>(.*?)</title>',
    caseSensitive: false,
    dotAll: true,
  );
  static final RegExp _ogPattern = RegExp(
    r'''<meta[^>]+(?:property|name)\s*=\s*['"](?:og:video(?::secure_url)?|og:image|twitter:image|twitter:player:stream)['"][^>]+content\s*=\s*['"]([^'"]+)['"]''',
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
  static final RegExp _cssUrlPattern = RegExp(
    r'''url\(\s*['"]?([^'")]+)['"]?\s*\)''',
    caseSensitive: false,
  );

  static Future<ScrapeResult> scrape(String pageUrl) async {
    if (!pageUrl.startsWith('http://') && !pageUrl.startsWith('https://')) {
      throw ArgumentError('pageUrl muss http(s) sein: $pageUrl');
    }
    final response = await _fetch(pageUrl);
    final html = response.body;
    final base = Uri.parse(response.finalUrl);
    final links = <String>{};
    final media = <String>{};

    void add(String? raw) {
      if (raw == null || raw.trim().isEmpty || links.length >= _maxLinks) {
        return;
      }
      final value = _decodeHtml(raw.trim());
      if (value.startsWith('data:') ||
          value.startsWith('javascript:') ||
          value.startsWith('mailto:')) {
        return;
      }
      Uri resolved;
      try {
        resolved = base.resolve(value);
      } catch (_) {
        return;
      }
      final resolvedStr = resolved.toString();
      if (!resolvedStr.startsWith('http://') &&
          !resolvedStr.startsWith('https://')) {
        return;
      }
      links.add(resolvedStr);
      if (_isMedia(resolvedStr) && media.length < _maxMedia) {
        media.add(resolvedStr);
      }
    }

    for (final m in _attrPattern.allMatches(html)) {
      add(m.group(1));
    }
    for (final m in _srcSetPattern.allMatches(html)) {
      for (final part in (m.group(1) ?? '').split(',')) {
        add(part.trim().split(' ').first);
      }
    }
    for (final m in _ogPattern.allMatches(html)) {
      add(m.group(1));
    }
    for (final m in _cssUrlPattern.allMatches(html)) {
      add(m.group(1));
    }
    for (final m in _urlPattern.allMatches(html)) {
      add(m.group(0));
    }
    for (final m in _escapedUrlPattern.allMatches(html)) {
      add(m.group(0)?.replaceAll(r'\/', '/'));
    }

    // Media-looking JSON/config strings are common in JS players.
    String decoded;
    try {
      decoded = Uri.decodeFull(html);
    } catch (_) {
      decoded = html;
    }
    for (final m in _urlPattern.allMatches(decoded)) {
      add(m.group(0));
    }

    final finalLinks = links.take(_maxLinks).toList();
    final finalMedia =
        media.where(_isMedia).toSet().take(_maxMedia).toList();

    final titleMatch = _titlePattern.firstMatch(html);
    final title = titleMatch != null
        ? _decodeHtml(titleMatch.group(1) ?? '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim()
            .let((s) => s.length > 200 ? s.substring(0, 200) : s)
        : (base.host.isNotEmpty ? base.host : 'NEXUS');

    return ScrapeResult(
      title: title,
      links: finalLinks,
      media: finalMedia,
      htmlSize: utf8.encode(html).length,
    );
  }

  static Future<_Response> _fetch(String pageUrl) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..autoUncompress = true;
    try {
      final request = await client
          .getUrl(Uri.parse(pageUrl))
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
      final capped = bytes.length > _maxHtmlBytes
          ? bytes.sublist(0, _maxHtmlBytes)
          : bytes;
      return _Response(
        body: utf8.decode(capped, allowMalformed: true),
        finalUrl: response.redirects.isNotEmpty
            ? response.redirects.last.location.toString()
            : pageUrl,
      );
    } finally {
      client.close(force: true);
    }
  }

  static bool _isMedia(String url) {
    String path;
    try {
      path = Uri.parse(url).path.toLowerCase();
    } catch (_) {
      path = '';
    }
    const extensions = [
      '.mp4', '.m4v', '.webm', '.mov', '.m3u8', '.mp3', '.m4a', '.aac',
      '.flac', '.wav', '.jpg', '.jpeg', '.png', '.webp', '.gif', '.avif', //
    ];
    return extensions.any(path.endsWith);
  }

  static String _decodeHtml(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}

class _Response {
  final String body;
  final String finalUrl;
  const _Response({required this.body, required this.finalUrl});
}

extension _Let<T> on T {
  R let<R>(R Function(T) block) => block(this);
}
