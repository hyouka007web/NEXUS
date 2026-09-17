import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:nexus/models/browser_tab.dart';
import 'package:nexus/models/harvested_media.dart';
import 'package:nexus/services/adblock_engine.dart';
import 'package:nexus/services/deep_harvester.dart';
import 'package:nexus/services/universal_scraper.dart';
import 'package:nexus/theme/nexus_theme.dart';

/// NexusWebView: die eigentliche Browser-Engine für einen Tab.
///  - shouldInterceptRequest: Adblock + passives Netzwerk-Sniffing (Harvester)
///  - shouldOverrideUrlLoading: Redirect-Ketten-Schutz (bricht nach zu vielen
///    automatischen Weiterleitungen ohne Nutzer-Geste ab)
///  - onCreateWindow: Popups werden nicht mehr pauschal geblockt, sondern
///    (begrenzt) als neuer Tab geöffnet — echter Redirect-/Popup-Schutz statt
///    kompletter Funktionsverweigerung
///  - onLoadStop: UniversalScraper wird injiziert, gefundene Iframes werden
///    serverseitig nachgeladen und erneut gescannt
class NexusWebView extends StatefulWidget {
  final BrowserTab tab;
  final AdBlockEngine adblock;
  final void Function(String url) onOpenNewTab;

  const NexusWebView({
    super.key,
    required this.tab,
    required this.adblock,
    required this.onOpenNewTab,
  });

  @override
  State<NexusWebView> createState() => _NexusWebViewState();
}

class _NexusWebViewState extends State<NexusWebView> with AutomaticKeepAliveClientMixin {
  int _popupsThisLoad = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final tab = widget.tab;
    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri(tab.url),
            headers: const {
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 13; SM-S901B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
            },
          ),
          initialSettings: InAppWebViewSettings(
            useHybridComposition: true,
            cacheMode: CacheMode.LOAD_DEFAULT,
            javaScriptEnabled: true,
            domStorageEnabled: true,
            useWideViewPort: true,
            builtInZoomControls: true,
            displayZoomControls: false,
            allowFileAccess: true,
            allowContentAccess: true,
            supportMultipleWindows: true,
            mediaPlaybackRequiresUserGesture: false,
            javaScriptCanOpenWindowsAutomatically: true,
          ),
          onWebViewCreated: (controller) {
            tab.controller = controller;
          },
          onLoadStart: (controller, url) {
            _popupsThisLoad = 0;
            tab.clearHarvested();
            tab.update(
              isLoading: true,
              url: url?.toString() ?? tab.url,
              isHome: false,
            );
          },
          onProgressChanged: (controller, progress) {
            tab.update(progress: progress / 100.0);
          },
          onTitleChanged: (controller, title) {
            if (title != null && title.isNotEmpty) tab.update(title: title);
          },
          onLoadStop: (controller, url) async {
            tab.update(isLoading: false, progress: 1.0);
            final canBack = await controller.canGoBack();
            final canFwd = await controller.canGoForward();
            tab.update(canGoBack: canBack, canGoForward: canFwd);
            await _runDeepScrape(controller, tab);
          },
          onReceivedError: (controller, request, error) {
            tab.update(isLoading: false);
          },
          shouldInterceptRequest: (controller, request) async {
            final url = request.url.toString();

            if (widget.adblock.isBlocked(url, resourceType: request.headers?['Sec-Fetch-Dest'] ?? 'other')) {
              return WebResourceResponse(contentType: 'text/plain', data: Uint8List(0), statusCode: 403);
            }

            // Passives Netzwerk-Sniffing: erkennt nachgeladene Manifeste/
            // Mediendateien, die nie im sichtbaren DOM auftauchen.
            final sniffed = tab.networkSniffer.inspect(
              requestUrl: url,
              pageUrl: tab.url,
              pageTitle: tab.title,
            );
            if (sniffed != null) {
              tab.addHarvested(sniffed);
              unawaited(_resolveVariantsAsync(tab, sniffed));
            }
            return null;
          },
          shouldOverrideUrlLoading: (controller, navigationAction) async {
            final url = navigationAction.request.url.toString();
            // isRedirect (Android) markiert Navigationen, die der Server/das
            // Script ausgelöst hat — nicht der Nutzer. Nur solche zählen
            // in die Weiterleitungskette.
            final isAutoRedirect = navigationAction.isRedirect ?? false;

            if (!isAutoRedirect) {
              tab.resetRedirectChain();
              return NavigationActionPolicy.ALLOW;
            }

            final shouldAbort = tab.registerRedirect();
            if (shouldAbort) {
              _notifyBlocked(context, 'Weiterleitungskette gestoppt ($url)');
              return NavigationActionPolicy.CANCEL;
            }
            return NavigationActionPolicy.ALLOW;
          },
          onCreateWindow: (controller, createWindowAction) async {
            final targetUrl = createWindowAction.request.url?.toString();
            if (targetUrl == null) return false;

            _popupsThisLoad++;
            if (_popupsThisLoad > 2) {
              // Popup-Spam-Schutz: ab dem 3. Popup pro Seitenaufruf wird geblockt.
              _notifyBlocked(context, 'Popup blockiert ($targetUrl)');
              return false;
            }
            widget.onOpenNewTab(targetUrl);
            return false; // wir öffnen selbst einen NEXUS-Tab statt eines nativen Fensters
          },
        ),
        if (tab.isLoading)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              value: tab.progress > 0 ? tab.progress : null,
              minHeight: 2,
              backgroundColor: Colors.transparent,
              valueColor: const AlwaysStoppedAnimation<Color>(NexusColors.accent),
            ),
          ),
      ],
    );
  }

  void _notifyBlocked(BuildContext context, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: const TextStyle(fontSize: 12)), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _runDeepScrape(InAppWebViewController controller, BrowserTab tab) async {
    final raw = await controller.evaluateJavascript(source: UniversalScraper.injectedJs) as String?;
    if (raw == null) return;
    final result = UniversalScraper.parseResult(raw, pageUrl: tab.url, pageTitle: tab.title);

    for (final media in result.entries) {
      tab.addHarvested(media);
      unawaited(_resolveVariantsAsync(tab, media));
    }

    // Wenn im Haupt-DOM nichts gefunden wurde, aber Iframes vorhanden sind:
    // die wahrscheinlichsten (erste 3) serverseitig nachladen und erneut scannen.
    // Das deckt eingebettete Player ab, deren Quelle erst im Iframe-Dokument steht.
    if (result.entries.isEmpty && result.iframeUrls.isNotEmpty) {
      for (final iframeUrl in result.iframeUrls.take(3)) {
        final found = await DeepHarvester.scanIframe(iframeUrl, pageTitle: tab.title);
        for (final media in found) {
          tab.addHarvested(media);
          unawaited(_resolveVariantsAsync(tab, media));
        }
      }
    }
  }

  Future<void> _resolveVariantsAsync(BrowserTab tab, HarvestedMedia media) async {
    if (media.kind != MediaKind.hls && media.kind != MediaKind.dash) return;
    final variants = await DeepHarvester.resolveVariants(media);
    media.variants = variants;
    tab.notifyMediaUpdated();
  }
}

void unawaited(Future<void> future) {}
