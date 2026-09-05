# NEXUS (Flutter) — Stufe 0: Werkzeug-Test

Zweck dieser Version: **nur prüfen, ob der Build auf Android, Windows und
Linux durchläuft** und ein Fenster mit einer geladenen Testseite
(`https://example.com`) zeigt. Keine NEXUS-Logik (kein Adblock, kein
Redirect-Shield, keine Tabs) — die kommt erst in den nächsten Stufen, wenn
klar ist, dass der Drei-Plattformen-Ansatz bei euch beiden praktisch
funktioniert.

## Warum hier kein `android/`, `windows/`, `linux/` im Repo liegt

Diese Ordner enthalten viel Plattform-Boilerplate (Gradle-Wrapper-Binärdatei,
CMake-Dateien, Win32-Runner-Code), die normalerweise vom `flutter`-Werkzeug
selbst erzeugt wird und eng an die jeweilige Flutter-Version gekoppelt ist.
Statt das von Hand nachzubauen und zu riskieren, dass es mit einer neueren
Flutter-Version nicht mehr zusammenpasst, erzeugt der CI-Workflow
(`.github/workflows/flutter-build.yml`) diese Ordner bei jedem Lauf frisch
über `flutter create --platforms=... .` — passend zur jeweils installierten
Flutter-Version. `pubspec.yaml` und `lib/` bleiben davon unberührt.

## Wer testet was

- **Android:** du, direkt auf deinem Handy (APK aus dem Actions-Artifact
  installieren, wie beim Kotlin-NEXUS).
- **Windows + Linux:** dein Tester-Freund, jeweils auf echter Hardware.
  Besonders beim Linux-Build (CEF-Plugin, siehe unten) ist echtes Feedback
  wichtig — das lässt sich nicht aus dem CI-Log allein beurteilen.

## Bekanntes Risiko: Linux

Für Linux gibt es kein offizielles "System-WebView" wie bei Android/Windows.
Das genutzte Paket `flutter_linux_webview` bettet Chromium über CEF ein und
ist laut eigener Dokumentation ausdrücklich als instabil markiert ("hängt
oder stürzt auf manchen Systemen ab"). Falls der Linux-Build bei deinem
Tester nicht startet oder abstürzt: das ist erwartbar und der Punkt, an dem
wir entscheiden müssen, ob wir dabei bleiben oder für Linux einen anderen
Weg suchen.

## Build lokal (falls dein Tester-Freund das lieber selbst macht)

```bash
flutter create --platforms=windows,linux --org com.nexus.browser .
flutter pub get
flutter build windows --debug   # bzw. linux
```

## Nächste Schritte (nach erfolgreichem Stufe-0-Test)

1. ~~Scraper + Video Harvester (reine HTTP-Requests, aus Kotlin nach Dart übertragen)~~
   **erledigt** — `lib/engines/scraper_engine.dart`,
   `lib/engines/video_harvester_engine.dart`,
   `lib/engines/ytdlp_style_extractor.dart`,
   `lib/engines/media_link_finder.dart`,
   `lib/engines/video_downloader.dart`,
   `lib/state/download_repository.dart`.
   Testbar über den Werkzeug-Button (oben rechts) auf dem WebView-Testscreen.
2. UI-Gerüst (Tabs, Adressleiste, Einstellungen)
3. Ad-Block/Redirect-Shield pro Plattform (Android: WebView-NavigationDelegate,
   Windows: WebView2 `WebResourceRequested`, Linux: CEF `ResourceRequestHandler`)

### Hinweis zu den portierten Engines

Ein Unterschied zum Kotlin-Original ist erwähnenswert: `dart:io`s
`HttpClient` entpackt gzip-komprimierte Antworten standardmäßig automatisch.
Der Bug, den wir im Kotlin-`ScraperEngine` nachträglich fixen mussten (gzip
angefragt, aber nie entpackt) kann hier von vornherein nicht auftreten.

Alle Engines sind reines Dart ohne Plattform-Channel-Abhängigkeit (nur
`dart:io`, `path_provider`) — sie laufen unverändert auf Android, Windows
und Linux.
