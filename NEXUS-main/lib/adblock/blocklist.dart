/// Feste Starter-Blockliste, 1:1 aus `blocklist_hosts.txt` des Kotlin-
/// Originals übernommen — nur der Host-Teil. Die dortigen generischen
/// Substring-Regeln ("tracking", "pixel.gif", "/ads/", "/adserver/") sind
/// bewusst NICHT übernommen: die waren für Requests auf Ressourcen-Ebene
/// gedacht (mit Quelldomain-Kontext), wir blocken hier aber nur ganze
/// Seitennavigationen (siehe redirect_shield.dart, dortiger Kommentar zur
/// API-Grenze von webview_flutter). Auf eine komplette Navigations-URL
/// angewendet, würden diese losen Substrings zu falschen Treffern führen.
class Blocklist {
  Blocklist._();

  static const Set<String> hosts = {
    'doubleclick.net',
    'googlesyndication.com',
    'adservice.google.com',
    'adnxs.com',
    'taboola.com',
    'outbrain.com',
    'scorecardresearch.com',
    'zedo.com',
    'ads.example',
  };

  /// Prüft [host] und alle übergeordneten Domains (z.B. "sub.ads.example"
  /// matcht auch "ads.example") — gleiche Logik wie im Kotlin-Original.
  static bool isBlockedHost(String host) {
    var current = host.toLowerCase();
    while (current.isNotEmpty) {
      if (hosts.contains(current)) return true;
      final dot = current.indexOf('.');
      if (dot < 0) break;
      current = current.substring(dot + 1);
    }
    return false;
  }
}
