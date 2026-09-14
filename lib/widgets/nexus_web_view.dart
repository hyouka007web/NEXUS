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
    _initWebViewController();
  }

  void _initWebViewController() {
    _webViewController = InAppWebViewController(
      initialFileLoader: false,
      onWebViewCreated: (controller) {
        _webViewController = controller;
      },
      onLoadStart: (controller, url) {
        setState(() => _isLoading = true);
      },
      onLoadStop: (controller, url) {
        setState(() => _isLoading = false);
      },
      shouldInterceptRequest: (controller, request) async {
        // 🛰️ HAUPT-HOOK: Abfangen jeder Netzwerk-Anfrage
        if (widget.adblock.isBlocked(request.url.toString())) {
          // Request blocken
          return ShouldInterceptRequestResponse(
            action: ShouldInterceptRequestResponseAction.CANCEL,
            body: Uint8List(0),
            responseHeaders: {},
            contentType: 'text/plain',
            statusCode: 403,
          );
        }
        // Request durchlassen
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(
            url: Uri.parse(widget.url),
            headers: {
              'User-Agent': 'Mozilla/5.0 (Linux; Android 12; SM-S901B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
            },
          ),
          initialWebviewConfig: initialWebviewConfig(),
          initialSettings: initialSettings(),
          onWebViewCreated: (controller) {
            _webViewController = controller;
          },
          onLoadStart: (controller, url) {
            setState(() => _isLoading = true);
          },
          onLoadStop: (controller, url) {
            setState(() => _isLoading = false);
          },
          shouldInterceptRequest: (controller, request) async {
            // 🛰️ HAUPT-HOOK: Abfangen jeder Netzwerk-Anfrage
            if (widget.adblock.isBlocked(request.url.toString())) {
              return ShouldInterceptRequestResponse(
                action: ShouldInterceptRequestResponseAction.CANCEL,
                body: Uint8List(0),
                responseHeaders: {},
                contentType: 'text/plain',
                statusCode: 403,
              );
            }
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

  WebviewConfig initialWebviewConfig() {
    return WebviewConfig(
      useHybridComposition: true,
      cacheMode: CacheMode.LOAD_NO_CACHE,
      clearCache: true,
      settings: WebviewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        cacheMode: WebviewCacheMode.LOAD_NO_CACHE,
        useWideViewPort: true,
        builtInZoomControls: true,
        displayZoomControls: false,
      ),
    );
  }

  InAppWebViewSettings initialSettings() {
    return InAppWebViewSettings(
      useHybridComposition: true,
      cacheMode: CacheMode.LOAD_NO_CACHE,
      clearCache: true,
      javaScriptEnabled: true,
      domStorageEnabled: true,
      useWideViewPort: true,
      builtInZoomControls: true,
      displayZoomControls: false,
      allowFileAccess: true,
      allowContentAccess: true,
      allowMouseHandling: true,
      supportMultipleWindows: true,
      isInspectableInChrome: true,
    );
  }
}
