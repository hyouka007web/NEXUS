import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:nexus/models/harvested_media.dart';
import 'package:nexus/services/network_sniffer.dart';

/// Repräsentiert einen einzelnen Browser-Tab inkl. WebView-Controller,
/// Ladezustand, Redirect-Kette und den in diesem Tab geharvesteten Medien.
class BrowserTab extends ChangeNotifier {
  final String id;
  InAppWebViewController? controller;

  String url;
  String title;
  String? faviconUrl;
  bool isLoading;
  double progress;
  bool canGoBack;
  bool canGoForward;
  bool isHome; // zeigt Speed-Dial statt WebView

  /// Zählt Weiterleitungen innerhalb der *aktuellen* Navigation
  /// (wird bei jeder neuen, vom Nutzer ausgelösten Navigation zurückgesetzt).
  int redirectChainCount;
  DateTime? navigationStartedAt;

  final List<HarvestedMedia> harvestedMedia = [];
  final Set<String> _seenMediaKeys = {};
  final NetworkSniffer networkSniffer = NetworkSniffer();

  BrowserTab({
    required this.id,
    this.url = 'nexus://home',
    this.title = 'Neuer Tab',
    this.faviconUrl,
    this.isLoading = false,
    this.progress = 0,
    this.canGoBack = false,
    this.canGoForward = false,
    this.isHome = true,
    this.redirectChainCount = 0,
  });

  void resetRedirectChain() {
    redirectChainCount = 0;
    navigationStartedAt = DateTime.now();
  }

  bool registerRedirect() {
    redirectChainCount++;
    return redirectChainCount > 6; // true = Kette abbrechen
  }

  void addHarvested(HarvestedMedia media) {
    if (_seenMediaKeys.contains(media.dedupeKey)) return;
    _seenMediaKeys.add(media.dedupeKey);
    harvestedMedia.add(media);
    notifyListeners();
  }

  /// Wird aufgerufen, wenn sich z.B. die aufgelösten Qualitätsstufen
  /// eines bereits vorhandenen HarvestedMedia-Eintrags geändert haben.
  void notifyMediaUpdated() => notifyListeners();

  void clearHarvested() {
    harvestedMedia.clear();
    _seenMediaKeys.clear();
    networkSniffer.reset();
    notifyListeners();
  }

  void update({
    String? url,
    String? title,
    String? faviconUrl,
    bool? isLoading,
    double? progress,
    bool? canGoBack,
    bool? canGoForward,
    bool? isHome,
  }) {
    if (url != null) this.url = url;
    if (title != null) this.title = title;
    if (faviconUrl != null) this.faviconUrl = faviconUrl;
    if (isLoading != null) this.isLoading = isLoading;
    if (progress != null) this.progress = progress;
    if (canGoBack != null) this.canGoBack = canGoBack;
    if (canGoForward != null) this.canGoForward = canGoForward;
    if (isHome != null) this.isHome = isHome;
    notifyListeners();
  }
}
