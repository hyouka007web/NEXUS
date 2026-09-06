# NEXUS (Flutter)

## Aktueller Stand

**Android:** vollständige Browser-Oberfläche nach dem `design.md`-Vorbild
des Kotlin-Originals:
- Tabs (horizontale Pill-Chips, scrollbar)
- Pill-förmige Adressleiste mit Reload-Icon
- Sidebar (eingeklappt als schmale goldene Leiste, ausklappbar): Zurück/
  Vor/Home, Komplett-Analyse, Video Harvester, Mediathek
- Native Startseite (Logo + Suchfeld) statt einer extern geladenen
  Suchmaschinen-Startseite
- Bottom-Panel für Benachrichtigungen (blockierte Weiterleitungen,
  Analyse-Ergebnisse) mit automatischem Verschwinden + optionaler Aktion
- Shield-Zähler oben rechts (Anzahl blockierter Navigationen)
- Mediathek-Screen (heruntergeladene Videos, laufende Downloads)
- Farben/Radien/Bewegungsdauern 1:1 aus `design.md` übernommen
  (`lib/theme/nexus_theme.dart`)
- Logo: dasselbe PNG wie im Kotlin-Original (`assets/nexus_logo.png`)

**Komplett-Analyse und Video Harvester brauchen keine eigene URL-Eingabe
mehr** — sie laufen automatisch auf der Seite, die gerade im aktiven Tab
offen ist (`TabManager.activeTab`), genau wie im Kotlin-Original.

**Windows:** einfachere Vorstufe (eine WebView, kein Absturz) — noch ohne
das neue Tabs/Sidebar/Adblock-UI, siehe "Warum Windows/Linux noch
zurückliegen" unten.

**Linux:** kein WebView (siehe "Linux pausiert" unten), aber
Scraper/Harvester/Downloader über den Werkzeug-Test-Screen nutzbar — dort
bleibt bewusst ein manuelles URL-Feld, weil es ohne WebView keine "aktuell
offene Seite" gibt, von der automatisch abgelesen werden könnte.

## Warum Windows/Linux beim neuen UI noch zurückliegen

Die neue Tabs/Sidebar/Adblock-Oberfläche (`lib/screens/browser_screen.dart`,
`lib/state/tab_manager.dart`, `lib/adblock/redirect_shield.dart`) ist komplett
auf `webview_flutter`s `WebViewController`/`NavigationDelegate`-API gebaut.
Diese API existiert nur für Android und iOS — `webview_windows` (Windows)
hat eine komplett andere, eigenständige API (eigener `WebviewController`-Typ,
kein `NavigationDelegate`-Äquivalent mit Request-Abfangen). Um Windows auf
denselben UI-Stand zu bringen, braucht es ein eigenes, zu dessen API
passendes Äquivalent — kommt als nächster Schritt, sobald Android bei dir
sauber läuft.

## Ehrliche Grenze beim Ad-Block/Redirect-Shield (Android)

GeckoViews `NavigationDelegate.onLoadRequest` (Kotlin-Original) bekam für
JEDE Anfrage — auch eingebettete Bilder/Skripte/iframes — ein
`hasUserGesture`-Signal und konnte einzelne Requests granular blocken.
`webview_flutter`s öffentliche API gibt uns nur ganze Seiten-Navigationen
ohne Geste-Signal. Volles Ressourcen-Blocking (einzelne Werbebanner
innerhalb einer Seite) ist damit nicht möglich — das ist eine Grenze des
offiziellen Plugins selbst, keine Fleißaufgabe. Was funktioniert: Blocken
von Navigationen zu bekannten Werbedomains, und dieselbe
Redirect-Timing-Logik (laufende vs. abgeschlossene Navigation), die beim
Kotlin-Original den entscheidenden Unterschied gemacht hat. Details direkt
im Docstring von `lib/adblock/redirect_shield.dart`.

## Warum hier kein `android/`, `windows/`, `linux/` im Repo liegt

Diese Ordner enthalten viel Plattform-Boilerplate (Gradle-Wrapper-Binärdatei,
CMake-Dateien, Win32-Runner-Code), die normalerweise vom `flutter`-Werkzeug
selbst erzeugt wird und eng an die jeweilige Flutter-Version gekoppelt ist.
Der CI-Workflow (`.github/workflows/flutter-build.yml`) erzeugt sie bei
jedem Lauf frisch über `flutter create --platforms=... .` — passend zur
jeweils installierten Flutter-Version. `pubspec.yaml` und `lib/` bleiben
davon unberührt.

## Linux pausiert (WebView)

`flutter_linux_webview` (das einzige verfügbare Linux-WebView-Paket,
CEF-basiert) ist fest an die alte `webview_flutter`-3.0.4-API gekettet und
damit inkompatibel mit dem für Android nötigen Upgrade auf 4.x — pub kann
nicht zwei Hauptversionen desselben Pakets gleichzeitig auflösen. Linux
zeigt deshalb einen expliziten Hinweisbildschirm statt einer WebView.
Scraper/Harvester/Downloader funktionieren dort trotzdem uneingeschränkt.

## Wer testet was

- **Android:** du — volle Oberfläche, direkt auf deinem Handy testbar.
- **Windows:** dein Tester-Freund — einfachere Vorstufe.
- **Linux:** Werkzeug-Test-Screen (Scraper/Harvester/Downloader).

## Build lokal

```bash
flutter create --platforms=windows,linux --org com.nexus.browser --project-name nexus_flutter .
flutter pub get
flutter build windows --debug   # bzw. linux
```

## Nächste Schritte

1. ~~Scraper + Video Harvester + Downloader nach Dart~~ **erledigt**
2. ~~Android-UI (Tabs, Sidebar, Startseite, Redirect-Shield, Mediathek)~~ **erledigt**
3. Windows-Äquivalent der Tabs/Sidebar/Adblock-Oberfläche (eigene API)
4. Einstellungen-Screen (Suchmaschine wählen, Adblock an/aus)

## Hinweis zu den portierten Engines

`dart:io`s `HttpClient` entpackt gzip-komprimierte Antworten standardmäßig
automatisch. Der Bug, den wir im Kotlin-`ScraperEngine` nachträglich fixen
mussten (gzip angefragt, aber nie entpackt), kann hier von vornherein nicht
auftreten. Alle Engines sind reines Dart ohne Plattform-Channel-Abhängigkeit
(nur `dart:io`, `path_provider`) — sie laufen unverändert auf allen drei
Plattformen.
