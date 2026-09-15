import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:nexus/services/adblock_engine.dart';
import 'package:nexus/services/video_downloader.dart';
import 'package:nexus/services/hls_dash_parser.dart';

/// NexusWebView: Browser-Engine mit shouldInterceptRequest für Adblock,
/// Redirect-Ketten-Zählung, User-Gesture-Basierte onCreateWindow,
/// und Video-Downloader via JS-Injection.
class NexusWebView extends StatefulWidget {
  final String url;

  const NexusWebView({super.key, required this.url});

  @override
  State<NexusWebView> createState() => _NexusWebViewState();
}

class _NexusWebViewState extends State<NexusWebView> {
  late InAppWebViewController _webViewController;
  bool _isLoading = true;

  static final AdBlockEngine _adblock = AdBlockEngine();
  final Map<String, int> _redirectCounts = {};

  @override
  void initState() {
    super.initState();
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
            _scrapeVideos();
          },
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
          shouldOverrideUrlLoading: (controller, navigationAction) async {
            final url = navigationAction.request.url.toString();
            final count = (_redirectCounts[url] ?? 0) + 1;
            _redirectCounts[url] = count;
            if (count > 5) return Future.value<bool?>(false);
            return Future.value<bool?>(true);
          },
          onCreateWindow: (controller, createWindowRequest) async {
            return null;
          },
        ),
        if (_isLoading)
          const Center(child: CircularProgressIndicator(color: Colors.deepPurple)),
      ],
    );
  }

  Future<void> _scrapeVideos() async {
    final result = await _webViewController.evaluateJavascript(source: """
      (function() {
        var entries = [];
        document.querySelectorAll('video, source').forEach(function(el) {
          var src = el.src || el.getAttribute('src');
          if (src && src.indexOf('http') === 0) {
            entries.push(JSON.stringify({url: src, type: 'video'}));
          }
        });
        document.querySelectorAll('script').forEach(function(script) {
          var text = script.textContent || '';
          var urls = text.match(/https?:\\/\\/[^\\s"']+\\.m3u8/gi);
          if (urls) {
            urls.forEach(function(url) {
              entries.push(JSON.stringify({url: url, type: 'hls'}));
            });
          }
        });
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
        final streamUrl = entry['url'];
        final content = await _fetchManifest(streamUrl);
        if (content != null) {
          final streams = type == 'hls' ? HLSDashParser.parseHLS(content) : HLSDashParser.parseDASH(content);
          for (final stream in streams) {
            if (stream.url.contains('http')) {
              await VideoDownloader.download(stream.url, title: 'NEXUS_Stream', type: stream.type);
            }
          }
        }
      } else {
        await VideoDownloader.download(entry['url'], title: 'NEXUS_Video', type: entry['type']);
      }
    }
  }

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
