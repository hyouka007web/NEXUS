// Mobile (Android/iOS) Implementierung der WebView-Bridge
// Verwendet webview_flutter als Backend.

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'webview_interface.dart';

class WebViewBridgeStateImpl extends WebViewBridgeState {
  late WebViewController _controller;
  String? _currentUrl;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavascriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            // Progress callback
          },
          onPageStarted: (String url) {
            _currentUrl = url;
            if (widget.onPageStarted != null) {
              widget.onPageStarted!(url);
            }
          },
          onPageFinished: (String url) {
            _currentUrl = url;
            if (widget.onPageFinished != null) {
              widget.onPageFinished!(url);
            }
          },
          onNavigationRequest: (NavigationRequest request) async {
            // Delegate to the widget's navigationDelegate
            final result = await widget.navigationDelegate.call(request);
            return NavigationDecision.navigate;
          },
          onWebResourceError: (WebResourceError error) {
            // Error handling
          },
          onHttpError: (HttpRequestError error, String url) {
            // HTTP Error handling
          },
        ),
      )
      ..setJavaScriptMode(JavascriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent);

    if (widget.disableCache) {
      _controller.clearCache();
    }

    _loadInitialUrl();
  }

  void _loadInitialUrl() {
    final uri = Uri.parse(widget.initialUrl);
    _controller.loadRequest(uri, headers: {});
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }

  @override
  Future<void> loadUrl(String url) async {
    final uri = Uri.parse(url);
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (String url) {
          _currentUrl = url;
          if (widget.onPageStarted != null) {
            widget.onPageStarted!(url);
          }
        },
        onPageFinished: (String url) {
          _currentUrl = url;
          if (widget.onPageFinished != null) {
            widget.onPageFinished!(url);
          }
        },
        onNavigationRequest: (NavigationRequest request) async {
          final result = await widget.navigationDelegate.call(request);
          return NavigationDecision.navigate;
        },
        onWebResourceError: (WebResourceError error) {
          // Error handling
        },
        onHttpError: (HttpRequestError error, String url) {
          // HTTP Error handling
        },
      ),
    );
    final httpRequest = LoadRequestMethod.get;
    await _controller.loadRequest(uri, headers: {});
  }

  @override
  Future<void> reload() => _controller.reload();

  @override
  Future<void> goBack() => _controller.goBack();

  @override
  Future<bool> canGoBack() => _controller.canGoBack();

  @override
  Future<void> runJavaScript(String javaScript) {
    return _controller.runJavaScript(javaScript);
  }

  @override
  Future<void> runJavaScriptFromFile(String path) async {
    final content = ''; // File reading would go here
    await _controller.runJavaScript(content);
  }

  @override
  @override
  Future<void> setCacheMode(int mode) async {
    await _controller.clearCache();
  }

  @override
  Future<String?> currentUrl() => _controller.currentUrl();

  @override
  Future<String?> getHtml() => _controller.runJavaScriptReturningResult('document.documentElement.innerHTML')
      .then((value) => value?.toString());

  @override
  Future<void> loadUrlNoCache(String url, {Map<String, String>? headers}) async {
    await _controller.clearCache();
    final uri = Uri.parse(url);
    await _controller.loadRequest(uri, headers: headers ?? {});
  }

  @override
  Widget buildWebView() => this.build(_controller.context);

  // Override the parent's build method
  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
