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

## Linux pausiert (Stand: nach dem ersten echten CI-Fehlschlag)

Der erste Android-Build ist an `webview_flutter 3.0.4` gescheitert
("Namespace not specified" — diese alte Version zieht eine
`webview_flutter_android`-Fassung, die noch keinen `namespace` deklariert,
was moderne Android-Gradle-Plugin-Versionen zwingend verlangen). Der Fix
(Upgrade auf `webview_flutter ^4.10.0`, die aktuell gepflegte Version) hat
aber einen Nebeneffekt: `flutter_linux_webview` — das einzige verfügbare
Linux-WebView-Paket, CEF-basiert — ist fest an die alte 3.0.4-API gekettet.
**pub kann nicht zwei Hauptversionen desselben Pakets gleichzeitig
auflösen**, das ist keine Konfigurationsfrage, sondern eine harte Grenze.

Entscheidung: Android + Windows laufen jetzt auf der modernen, gepflegten
Basis. Linux zeigt stattdessen einen expliziten Hinweisbildschirm statt
einer WebView — ehrlich sichtbar, nicht stillschweigend kaputt. Scraper,
Video Harvester und Downloader funktionieren unter Linux trotzdem
uneingeschränkt, die hängen an keiner WebView-Engine.

Falls Linux-WebView-Unterstützung später wichtig wird: entweder eine
gepflegte, auf `webview_flutter` 4.x oder eine eigene Platform-Channel-Lösung
aufbauende Alternative suchen, oder für Linux komplett auf ein eigenes
CEF-Embedding ohne den `webview_flutter`-Plugin-Unterbau umsteigen (mehr
Aufwand, aber unabhängig von diesem Versionskonflikt).

## Wer testet was

- **Android:** du, direkt auf deinem Handy (APK aus dem Actions-Artifact
  installieren, wie beim Kotlin-NEXUS).
- **Windows:** dein Tester-Freund.
- **Linux:** aktuell nur der Werkzeug-Test-Screen (Scraper/Harvester/
  Downloader) sinnvoll testbar, siehe oben — die WebView selbst zeigt
  bewusst nur einen Hinweistext.

## Build lokal (falls dein Tester-Freund das lieber selbst macht)

```bash
flutter create --platforms=windows,linux --org com.nexus.browser --project-name nexus_flutter .
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
