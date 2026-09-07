import 'dart:convert';

/// Netzwerk-Sniffer per JS-Injection. Löst eine Lücke, die auch das
/// gerenderte-DOM-Auslesen (`VideoHarvesterEngine.extractFromRenderedHtml`)
/// nicht schließt: viele Player schreiben die eigentliche Stream-URL nie ins
/// DOM, auch nicht nach dem Rendern — sie holen sie per `fetch()`/`XHR` und
/// reichen sie direkt intern an `MediaSource`/`<video>` weiter. Ein reines
/// "lies das DOM" sieht so eine URL nie, weil sie nirgends als Attribut
/// oder JSON-Text steht.
///
/// Der Trick: ein Skript wird injiziert, das `window.fetch` und
/// `XMLHttpRequest.prototype.open` überschreibt (klassisches "Network
/// Sniffing per Monkey-Patch", dieselbe Technik, mit der z.B. Browser-
/// Erweiterungen oder die Chrome-DevTools-"Network"-Ansicht arbeiten) und
/// jede angefragte URL protokolliert, die nach Video/HLS/DASH aussieht.
/// Zusätzlich wird auf `play`-Events von `<video>`-Elementen gelauscht und
/// deren `currentSrc` erfasst — das fängt auch Fälle, in denen der Browser
/// selbst (nicht die Seiten-JS) die Quelle setzt.
///
/// **Ehrliche Grenze:** Cross-Origin-iframes sind per Browser-Sicherheits-
/// modell (Same-Origin-Policy) für injizierten JS-Code unerreichbar — das
/// ist keine Einschränkung dieses Ansatzes, sondern eine harte Grenze des
/// Web-Sicherheitsmodells selbst, die für jede Technik gilt, injiziertes JS
/// eingeschlossen. Und: die Injektion passiert bei `onPageStarted`, also
/// sobald die Navigation beginnt — synchron im `<head>` ausgeführte Skripte
/// können in seltenen Fällen schneller sein als die Injektion. In der
/// Praxis passiert der eigentliche Video-Request aber meist erst nach
/// Nutzer-Interaktion (Play-Button) oder verzögertem Laden, wo dieses
/// Zeitfenster keine Rolle mehr spielt.
class NetworkSniffer {
  NetworkSniffer._();

  static const String injectionScript = '''
(function() {
  if (window.__nexusSniffInstalled) return;
  window.__nexusSniffInstalled = true;
  window.__nexusSniffed = window.__nexusSniffed || [];

  function looksLikeMedia(url) {
    if (typeof url !== 'string') return false;
    return /\\.(m3u8|mpd|mp4|webm|m4s|ts)(\\?|\$)/i.test(url)
      || /\\/(hls|dash|manifest|playlist|segment)/i.test(url);
  }

  function record(url) {
    try {
      if (!looksLikeMedia(url)) return;
      if (window.__nexusSniffed.indexOf(url) === -1) {
        window.__nexusSniffed.push(url);
      }
    } catch (e) {}
  }

  var origFetch = window.fetch;
  if (origFetch) {
    window.fetch = function(input, init) {
      try {
        record(typeof input === 'string' ? input : (input && input.url));
      } catch (e) {}
      return origFetch.apply(this, arguments);
    };
  }

  var origOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url) {
    try { record(url); } catch (e) {}
    return origOpen.apply(this, arguments);
  };

  document.addEventListener('play', function(e) {
    try {
      var t = e.target;
      if (t && t.currentSrc) record(t.currentSrc);
      if (t && t.src) record(t.src);
    } catch (e) {}
  }, true);

  // Bereits vorhandene <video>/<source>-Elemente auch ohne Play-Event
  // erfassen, falls die Quelle schon beim Injektionszeitpunkt gesetzt ist.
  document.querySelectorAll('video, source').forEach(function(el) {
    if (el.currentSrc) record(el.currentSrc);
    if (el.src) record(el.src);
  });
})();
''';

  /// Liest die bisher gesammelten URLs aus der Seite zurück. `raw` ist das
  /// JSON-kodierte Ergebnis von `runJavaScriptReturningResult` — auf
  /// Android kommt das immer als JSON-String-Literal zurück (auch wenn der
  /// eigentliche Wert selbst schon JSON ist), daher der doppelte Decode.
  static List<String> parseResult(Object raw) {
    try {
      var decoded = jsonDecode(raw.toString());
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is List) {
        return decoded.whereType<String>().toList();
      }
    } catch (_) {
      // Sniffer-Ergebnis war leer/kaputt — einfach nichts beitragen,
      // die übrigen Erkennungswege (DOM, Netzwerk-Crawl) laufen weiter.
    }
    return const [];
  }
}
