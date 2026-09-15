import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:nexus/services/adblock_service.dart';
import 'package:nexus/services/video_downloader.dart';
import 'dart:convert';

/// NexusWebView: Browser-Engine mit shouldInterceptRequest für Adblock,
/// Redirect-Ketten-Zählung, User-Gesture-Basierte onCreateWindow,
/// und Video-Downloader via JS-Injection.
class NexusWebView extends StatefulWidget {
  final String url;
  final AdblockService adblock;

  const NexusWebView({
    super.key,
    required this.url,
    required this.adblock,
  });

  @override
  State<NexusWebView> createState() => _NexusWebViewState();
}

class _NexusWebViewState extends State<NexusWebView> {
  late InAppWebViewController _webViewController;
  bool _isLoading = true;

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
            if (widget.adblock.isBlocked(request.url.toString())) {
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
            if (count > 5) {
              return ShouldOverrideUrlLoadingAction.cancel;
            }
            return ShouldOverrideUrlLoadingAction.allow;
          },
          onCreateWindow: (controller, createWindowRequest) async {
            if (!createWindowRequest.isUserGesture) {
              return null;
            }
            return InAppWebViewHitTestResult(
              viewType: createWindowRequest.viewType,
            );
          },
        ),
        if (_isLoading)
          const Center(
            child: CircularProgressIndicator(
              color: Colors.deepPurple,
            ),
          ),
      ],
    );
  }

  Future<void> _scrapeVideos() async {
    final result = await _webViewController.evaluateJavascript(
      source: """
        (function() {
          var srcs = [];
          document.querySelectorAll('video, source').forEach(function(el) {
            var src = el.src || el.getAttribute('src');
            if (src && src.indexOf('http') === 0 && srcs.indexOf(src) === -1) {
              srcs.push(src);
            }
          });
          return JSON.stringify(srcs);
        })();
      """) ?? '[]';

    if (result != '[]') {
      final List<dynamic> urls = jsonDecode(result);
      for (var url in urls) {
        await VideoDownloader.download(url.toString());
      }
    }
  }
}
