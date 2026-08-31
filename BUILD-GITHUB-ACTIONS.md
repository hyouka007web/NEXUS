# NEXUS – APK-Build ohne Android Studio

## Build auf GitHub

1. Repository auf GitHub öffnen.
2. **Actions** öffnen.
3. **Build NEXUS APK** auswählen.
4. **Run workflow** drücken.
5. Nach erfolgreichem Lauf den Build öffnen.
6. Unter **Artifacts** `NEXUS-debug-apk` herunterladen.
7. ZIP auf dem Handy entpacken und die APK installieren.

Der Workflow verwendet:
- JDK 17
- Gradle Wrapper des Projekts
- Android SDK Platform 35
- Build Tools 35.0.0
- `assembleDebug`

Es ist kein Android Studio auf dem Handy erforderlich.

## Wichtig

Der Workflow kann nur erfolgreich bauen, wenn der Quellcode selbst mit der konfigurierten Toolchain kompiliert. Ein erfolgreicher GitHub-Workflow ist deshalb der eigentliche Build-Test.
