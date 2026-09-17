# NEXUS Browser

Chromium-basierter Android-Browser (Flutter + flutter_inappwebview) mit
Vivaldi-artigem Sidebar-UI, echtem Adblocker, Deep-Media-Scraper und
Downloadmanager mit Qualitätsauswahl.

## Features

- **Multi-Tab-Browser** mit Vivaldi-artiger linker Icon-Leiste (Tabs,
  Speed-Dial, Harvester, Downloads) + oberer Tab-Leiste mit farbigen
  Domain-Akzenten
- **Adblocker**: Trie-basiertes Domain-Matching + Substring-Patterns,
  ~35 eingebaute Regeln + einlesbare Filterliste (`assets/filters/easylist_sample.txt`)
- **Deep-Scraper / Video-Harvester**: kombiniert vier Quellen, um Medien
  zu finden, egal wie die Seite sie einbettet:
  1. DOM-Scan (`<video>`, `<audio>`, `<source>`)
  2. Inline-`<script>`-Regex (deckt viele Player ab, die ihre Quelle per
     JS setzen)
  3. JSON-LD (`schema.org VideoObject`) + Open-Graph-Meta-Tags
  4. **Echtes Netzwerk-Sniffing** über `shouldInterceptRequest` — erkennt
     nachgeladene Manifeste/Dateien, die nie im sichtbaren HTML stehen
  5. Iframe-Fallback: wenn im Haupt-DOM nichts gefunden wird, werden bis
     zu 3 Iframes serverseitig nachgeladen und erneut gescannt
- **HLS/DASH-Auflösung**: gefundene `.m3u8`/`.mpd`-Manifeste werden zu
  einzelnen Qualitätsstufen aufgelöst, bevor der Download startet
- **Downloadmanager**: Qualitätsauswahl per Bottom-Sheet, Live-Fortschritt,
  Abbrechen, Speicherung in `NEXUS_Downloads/` im App-eigenen externen
  Speicher (kein Laufzeit-Permission-Prompt auf Android 10+ nötig)
- **Redirect-Ketten-Schutz**: bricht automatische Weiterleitungsketten
  (JS/Server-Redirects ohne Nutzer-Geste) nach 6 Sprüngen ab
- **Popup-Schutz**: begrenzt Popups pro Seitenaufruf (max. 2), statt sie
  pauschal zu blockieren

## Build

```bash
flutter pub get
flutter build apk --debug
```

### Falls der Build wegen fehlendem `gradlew` fehlschlägt

Der Gradle-Wrapper (`gradlew` + `gradle-wrapper.jar`) konnte in dieser
Umgebung nicht automatisch erzeugt werden (keine Netzwerk-/Flutter-SDK-
Verfügbarkeit beim Erstellen dieses Pakets). Einmalig ausführen:

```bash
flutter create --platforms=android .
```

Das ergänzt **nur** die fehlenden Plattform-Dateien (Wrapper-Skript,
`.jar`), ohne `lib/`, `pubspec.yaml` oder eigene Android-Dateien
anzufassen. Danach normal weiterbauen.

## Bekannte Einschränkungen

- Der Code wurde ohne lokale Flutter/Dart-SDK geschrieben (Container
  ohne Netzwerk/SDK) — es fand **kein** `flutter analyze` oder
  Testbuild statt. Kleinere API-Abweichungen zur gepinnten
  `flutter_inappwebview`-Version sind möglich, sollten sich aber als
  Ein-Zeiler beheben lassen.
- Rohe HLS/DASH-Downloads werden aktuell als Rohsegment-Mitschnitt
  gespeichert (kein Remuxing zu einer sauberen MP4-Datei) — für echtes
  Remuxing wäre FFmpeg (z.B. via `ffmpeg_kit_flutter`) nötig.
- Der eingebaute Video-Player zeigt bislang nur den Dateipfad; ein
  echter In-App-Player (z.B. `video_player`-Paket) fehlt noch.

## Requirements

- Flutter >= 3.22.0
- Dart >= 3.4.0
