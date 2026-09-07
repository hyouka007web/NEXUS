import 'package:webview_flutter/webview_flutter.dart';

import '../engines/network_sniffer.dart';
import '../models/block_event.dart';
import '../models/tab_model.dart';
import 'blocklist.dart';

/// Navigations-Ebene-Schutz für einen Tab: blockt (a) Navigationen zu
/// bekannten Werbe-/Tracker-Hosts und (b) Weiterleitungen, die JS auslöst,
/// *nachdem* eine Seite bereits fertig geladen war, ohne dass der Nutzer
/// gerade selbst etwas angeklickt hat (klassisches Malvertising-Muster:
/// "warte ein paar Sekunden, dann leite weg").
///
/// **Ehrliche Grenze gegenüber dem Kotlin/GeckoView-Original:**
/// GeckoViews `NavigationDelegate.onLoadRequest` bekommt für JEDE Anfrage
/// (auch Unterressourcen wie Bilder/Skripte/iframes) ein `hasUserGesture`-
/// Flag mitgeliefert und kann einzelne Requests granular blocken, bevor sie
/// überhaupt geladen werden. `webview_flutter`s öffentliche API
/// (`NavigationDelegate.onNavigationRequest`) gibt uns dagegen **nur**
/// ganze Seiten-Navigationen (Top-Level, kein `hasUserGesture`-Signal) —
/// eingebettete Werbebanner, Tracking-Pixel oder -Skripte innerhalb einer
/// Seite lassen sich damit NICHT blocken. Das ist keine Fleißaufgabe, die
/// noch nachgeholt werden kann, sondern eine Grenze des offiziellen
/// `webview_flutter`-Plugins selbst (bestätigt über die offizielle
/// pub.dev-Dokumentation). Für echtes Ressourcen-Blocking bräuchte man das
/// inoffizielle `flutter_inappwebview`-Paket mit eigenem
/// `shouldInterceptRequest`-Äquivalent — ein größerer Umbau, kein Fix hier.
///
/// Was hier also tatsächlich passiert: Popup-artige Seitenwechsel zu
/// Werbedomains werden verhindert, und die Art von Redirect, die im
/// Kotlin-Original monatelang den schwarzen Bildschirm bei der
/// Google-Suche verursacht hat (siehe RedirectShield-Fix dort), wird hier
/// von Anfang an richtig behandelt: Weiterleitungen, die noch zur
/// *laufenden* Navigation gehören (z.B. Googles Consent-Hop), werden
/// erlaubt; Weiterleitungen nach bereits abgeschlossenem Laden werden
/// geprüft.
class RedirectShield {
  RedirectShield._();

  static NavigationDelegate build({
    required NexusTab tab,
    required void Function(BlockEvent) onBlocked,
    required void Function(bool loading) onLoadingChange,
    required void Function(String url) onLocationChange,
  }) {
    String? currentHost;

    return NavigationDelegate(
      onPageStarted: (url) {
        tab.isLoading = true;
        currentHost = Uri.tryParse(url)?.host.toLowerCase();
        onLoadingChange(true);
        onLocationChange(url);
        tab.controller.runJavaScript(NetworkSniffer.injectionScript);
      },
      onPageFinished: (url) {
        tab.isLoading = false;
        onLoadingChange(false);
        tab.controller.getTitle().then((title) {
          if (title != null && title.isNotEmpty) {
            tab.title = title;
            onLocationChange(tab.url);
          }
        });
      },
      onNavigationRequest: (request) {
        final wasAppNavigation = tab.pendingAppNavigation;
        tab.pendingAppNavigation = false;

        final uri = Uri.tryParse(request.url);
        final host = uri?.host.toLowerCase() ?? '';

        if (host.isNotEmpty && Blocklist.isBlockedHost(host)) {
          onBlocked(BlockEvent(url: request.url, reason: BlockReason.adHost));
          return NavigationDecision.prevent;
        }

        final crossDomain =
            currentHost != null && host.isNotEmpty && host != currentHost;
        final stillLoading = tab.isLoading;

        // Siehe Klassen-Doc: kein hasUserGesture-Signal verfügbar, daher
        // nur die beiden Signale, die wir tatsächlich haben — genau das
        // Muster, das beim Kotlin-Original den entscheidenden Unterschied
        // gemacht hat (isLoading statt fixem Zeitfenster).
        if (!wasAppNavigation && crossDomain && !stillLoading) {
          onBlocked(
            BlockEvent(url: request.url, reason: BlockReason.redirectNoGesture),
          );
          return NavigationDecision.prevent;
        }

        return NavigationDecision.navigate;
      },
    );
  }
}
