import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:nexus/services/adblock_service.dart';

/// NexusWebView: Browser-Engine mit shouldInterceptRequest für Adblock
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
            url: WebUri.parse(widget.url),
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
          },
          // 🛰️ HAUPT-HOOK: Abfangen jeder Netzwerk-Anfrage für Adblock
          shouldInterceptRequest: (controller, request) async {
            if (widget.adblock.isBlocked(request.url.toString())) {
              // Request blocken mit WebResourceResponse
              return WebResourceResponse(
                contentType: 'text/plain',
                data: Uint8List(0),
                statusCode: 403,
              );
            }
            // Request durchlassen
            return null;
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
}
