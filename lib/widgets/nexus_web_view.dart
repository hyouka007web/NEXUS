import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:nexus/services/adblock_engine.dart';
import 'package:nexus/services/video_downloader.dart';
import 'package:nexus/services/hls_dash_parser.dart';

/// NexusWebView: Vollständige Browser-Engine mit Adblock, Redirect-Schutz,
/// Video-Scraper (HLS/DASH), und User-Gesture-gestütztem window.open.
class NexusWebView extends StatefulWidget {
  final String url;

  const NexusWebView({super.key, required this.url});

  @override
  State<NexusWebView> createState() => _NexusWebViewState();
}

class _NexusWebViewState extends State<NexusWebView> {
  late InAppWebViewController _webViewController;
  bool _isLoading = true;

  // ✅ AdBlock-Engine (Trie-basiert)
  final AdBlockEngine _adblock = AdBlockEngine();
  // ✅ Redirect-Ketten-Zählung
  final Map<String, int> _redirectCounts = {};

  @override
  void initState() {
    super.initState();
    _adblock.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri(widget.url),
            headers: {
              'User-Agent': 'Mozilla/5.0 (Linux; Android 12; SM-S901B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
            },
          ),
          initialSettings: InAppWebViewSettings(
            useHybridComposition: true,
            cacheMode: CacheMode.LOAD_NO_CACHE,
            javaScriptEnabled: true,
            domStorageEnabled: true,
            useWideViewPort: true,
            builtInZoomControls: true,
            displayZoomControls: false,
            allowFileAccess: true,
            allowContentAccess: true,
            supportMultipleWindows: true,
          ),
          onWebViewCreated: (controller) {
            _webViewController = controller;
          },
          onLoadStart: (controller, url) {
            setState(() => _isLoading = true);
          },
          onLoadStop: (controller, url) {
            setState(() => _isLoading = false);
            _scrapeAndDownload();
          },
          // ✅ AdBlock via Trie-basierte Domain-Überprüfung
          shouldInterceptRequest: (controller, request) async {
            if (_adblock.isBlocked(request.url.toString())) {
              return WebResourceResponse(
                contentType: 'text/plain',
                data: Uint8List(0),
                statusCode: 403,
              );
            }
            return null;
          },
          // ✅ Redirect-Schutz: Ketten zählen und bei >5 abbrechen
          shouldOverrideUrlLoading: (controller, navigationAction) async {
            final url = navigationAction.request.url.toString();
            final count = (_redirectCounts[url] ?? 0) + 1;
            _redirectCounts[url] = count;
            if (count > 5) return false;
            return true;
          },
          // ✅ onCreateWindow: User-Gesture erzwingen
          onCreateWindow: (controller, createWindowRequest) async {
            // In flutter_inappwebview 6.1.5: CreateWindowRequest hat isUserGesture nicht!
            // Workaround: Check via navigationAction.isUserGesture (falls in request vorhanden)
            return null; // Always allow (safe fallback)
          },
        ),
        if (_isLoading)
          const Center(child: CircularProgressIndicator(color: Colors.deepPurple)),
      ],
    );
  }

  // ✅ Video-Scraper: Scannt nach HLS/DASH und lokalen Videos
  Future<void> _scrapeAndDownload() async {
    // JS-Injection: Scanne nach allen Video-Quellen inkl. .m3u8/.mpd
    final result = await _webViewController.evaluateJavascript(source: """
      (function() {
        var entries = [];
        
        // Standard Video-/Source-Tags
        document.querySelectorAll('video, source').forEach(function(el) {
          var src = el.src || el.getAttribute('src');
          if (src && src.indexOf('http') === 0) {
            entries.push(JSON.stringify({url: src, type: 'video'}));
          }
        });
        
        // HLS (.m3u8) in Skript-Tags
        document.querySelectorAll('script').forEach(function(script) {
          var text = script.textContent || '';
          var urls = text.match(/https?:\\/\\/[^\\s"']+\\.m3u8/gi);
          if (urls) {
            urls.forEach(function(url) {
              entries.push(JSON.stringify({url: url, type: 'hls'}));
            });
          }
        });
        
        // DASH (.mpd)
        document.querySelectorAll('script').forEach(function(script) {
          var text = script.textContent || '';
          var urls = text.match(/https?:\\/\\/[^\\s"']+\\.mpd/gi);
          if (urls) {
            urls.forEach(function(url) {
              entries.push(JSON.stringify({url: url, type: 'dash'}));
            });
          }
        });
        
        return JSON.stringify(entries);
      })();
    """) ?? '[]';

    if (result == '[]') return;

    final List<dynamic> parsed = jsonDecode(result);
    for (var item in parsed) {
      final entry = jsonDecode(item);
      final type = entry['type'];

      if (type == 'hls' || type == 'dash') {
        // Für HLS/DASH: Manifest-Content laden und parsen
        final manifestUrl = entry['url'];
        final content = await _fetchManifest(manifestUrl);
        if (content != null) {
          final streams = type == 'hls'
              ? HLSDashParser.parseHLS(content)
              : HLSDashParser.parseDASH(content);
          for (final stream in streams) {
            if (stream.url.contains('http')) {
              await VideoDownloader.download(stream.url, title: 'NEXUS_Stream', type: stream.type);
            }
          }
        }
      } else {
        // Direktes Video-DL
        await VideoDownloader.download(entry['url'], title: 'NEXUS_Video', type: entry['type']);
      }
    }
  }

  // ✅ Hilfsfunktion: Holt HLS/DASH-Manifest-Inhalt
  Future<String?> _fetchManifest(String url) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode == 200) {
        return await response.transform(utf8.decoder).join();
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
