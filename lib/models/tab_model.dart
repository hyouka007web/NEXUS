import 'dart:math';

import 'package:webview_flutter/webview_flutter.dart';

/// Sentinel-URL für einen neuen/Home-Tab — zeigt die native NEXUS-
/// Startseite statt eine externe Suchmaschinen-Homepage zu laden (die
/// könnte in der WebView leer rendern). Entspricht der HOME_SENTINEL-Idee
/// aus dem Kotlin-Original.
const String kHomeSentinel = 'nexus://home';

class NexusTab {
  final String id;
  final WebViewController controller;
  String url;
  String title;
  bool isLoading;

  /// Wird kurz vor einer selbst ausgelösten Navigation (Adressleiste,
  /// Zurück/Vor-Button) gesetzt, damit der Redirect-Shield sie nicht als
  /// verdächtige Fremd-Weiterleitung fehlinterpretiert — entspricht
  /// `pendingAppNavigation` im Kotlin-`RedirectShield`.
  bool pendingAppNavigation;

  NexusTab({
    String? id,
    required this.controller,
    this.url = kHomeSentinel,
    this.title = 'Neuer Tab',
    this.isLoading = false,
    this.pendingAppNavigation = false,
  }) : id = id ?? _randomId();

  bool get isHome => url == kHomeSentinel;

  static String _randomId() {
    final rnd = Random.secure();
    return List.generate(8, (_) => rnd.nextInt(16).toRadixString(16)).join();
  }
}
