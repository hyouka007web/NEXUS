import "dart:convert";
import 'dart:io';

import '../models/harvested_video.dart';

/// Lightweight parsers for public, unencrypted HLS and DASH manifests.
/// DRM/key material is detected but never decrypted or bypassed.
class ManifestParser {
  ManifestParser._();

  static Future<List<MediaVariant>> inspect(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    try {
      final text = await _fetch(url, headers);
      final lower = text.toLowerCase();
      if (url.toLowerCase().contains('.m3u8') || lower.contains('#extm3u')) {
        return parseHls(text, url);
      }
      if (url.toLowerCase().contains('.mpd') || lower.contains('<mpd')) {
        return parseDash(text, url);
      }
    } catch (_) {}
    return const [];
  }

  static List<MediaVariant> parseHls(String text, String base) {
    final out = <MediaVariant>[];
    final lines = text.split(RegExp(r'\r?\n')).map((e) => e.trim()).toList();
    final re = RegExp(r'([A-Z-]+)=\s*(?:"([^"]*)")?([^,]+)', caseSensitive: false);
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!line.toUpperCase().startsWith('#EXT-X-STREAM-INF')) continue;
      final attrs = <String, String>{};
      for (final m in re.allMatches(line)) {
        attrs[m.group(1)!.toUpperCase()] = (m.group(2) ?? '').replaceAll('"', '');
      }
      String? child;
      for (var j = i + 1; j < lines.length; j++) {
        if (lines[j].isNotEmpty && !lines[j].startsWith('#')) {
          child = lines[j];
          break;
        }
      }
      if (child == null) continue;
      final resolution = attrs['RESOLUTION'] ?? '';
      final bandwidth = int.tryParse(attrs['BANDWIDTH'] ?? '') ?? 0;
      out.add(MediaVariant(
        url: Uri.parse(base).resolve(child).toString(),
        quality: resolution.isNotEmpty ? resolution : _qualityFromBandwidth(bandwidth),
        bandwidth: bandwidth,
        codecs: attrs['CODECS'] ?? '',
        mimeType: 'application/vnd.apple.mpegurl',
      ));
    }
    return out;
  }

  static List<MediaVariant> parseDash(String xml, String base) {
    final out = <MediaVariant>[];
    final mpdBase = _tag(xml, 'BaseURL');
    final documentBase = mpdBase == null ? base : Uri.parse(base).resolve(mpdBase).toString();
    final sets = RegExp(r'<AdaptationSet\b([^>]*)>([\s\S]*?)</AdaptationSet>', caseSensitive: false)
        .allMatches(xml);
    for (final set in sets) {
      final setAttrs = _attrs(set.group(1) ?? '');
      final body = set.group(2) ?? '';
      for (final rep in RegExp(r'<Representation\b([^>]*)>([\s\S]*?)</Representation>', caseSensitive: false)
          .allMatches(body)) {
        final attrs = <String, String>{...setAttrs, ..._attrs(rep.group(1) ?? '')};
        final repBase = _tag(rep.group(2) ?? '', 'BaseURL');
        final resolved = repBase == null ? documentBase : Uri.parse(documentBase).resolve(repBase).toString();
        out.add(MediaVariant(
          url: resolved,
          quality: attrs['height'] != null ? '${attrs['width'] ?? '?'}x${attrs['height']}' : '',
          bandwidth: int.tryParse(attrs['bandwidth'] ?? '') ?? 0,
          codecs: attrs['codecs'] ?? '',
          mimeType: attrs['mimeType'] ?? setAttrs['mimeType'] ?? 'application/dash+xml',
        ));
      }
    }
    return out;
  }

  static Future<String> _fetch(String url, Map<String, String> headers) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader,
          headers['User-Agent'] ?? 'Mozilla/5.0 (Linux; NEXUS Browser/1.0)');
      // Fix 2: Cache-Control: no-cache für frische Manifest-Ergebnisse
      req.headers.set('Cache-Control', 'no-cache, no-store, must-revalidate');
      req.headers.set('Pragma', 'no-cache');
      final ref = headers['Referer'];
      if (ref != null && ref.isNotEmpty) req.headers.set(HttpHeaders.refererHeader, ref);
      headers.forEach((k, v) {
        if (k.toLowerCase() != 'user-agent' && k.toLowerCase() != 'referer' && k.toLowerCase() != 'cookie') {
          try { req.headers.set(k, v); } catch (_) {}
        }
      });
      if (headers['Cookie']?.isNotEmpty == true) req.headers.set(HttpHeaders.cookieHeader, headers['Cookie']!);
      final res = await req.close().timeout(const Duration(seconds: 20));
      final bytes = <int>[];
      await for (final chunk in res) {
        bytes.addAll(chunk);
        if (bytes.length >= 8 * 1024 * 1024) break;
      }
      if (res.statusCode < 200 || res.statusCode >= 300) throw StateError('HTTP ${res.statusCode}');
      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      client.close(force: true);
    }
  }

  static Map<String, String> _attrs(String text) {
    final out = <String, String>{};
    for (final m in RegExp(r'(\w[\w-]*)\s*=\s*"([^"]*)"').allMatches(text)) {
      out[m.group(1)!.toLowerCase()] = m.group(2)!;
    }
    return out;
  }

  static String? _tag(String text, String name) =>
      RegExp('<$name\b[^>]*>([\s\S]*?)</$name>', caseSensitive: false)
          .firstMatch(text)?.group(1)?.trim();

  static String _qualityFromBandwidth(int bandwidth) => bandwidth <= 0 ? '' : '${(bandwidth / 1000000).toStringAsFixed(1)} Mbps';
}
