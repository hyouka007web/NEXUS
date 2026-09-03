# NEXUS Browser

NEXUS is a dark, technical Android browser built around GeckoView.

## Core
- GeckoView rendering engine
- multi-tab browsing
- local host/pattern adblock
- redirect and popup shield
- compact bottom action panel
- public-page HTML scraper for links/media/title
- direct media discovery and download
- local media library
- search engine selection
- pinned web apps

## Safety boundaries
The scraper operates on pages the browser can normally access. It does not bypass authentication, paywalls, CAPTCHAs or access controls. Media downloads are limited to directly reachable URLs.

## Build
- JDK 17
- Android API 35
- Gradle 8.9
- Android Gradle Plugin 8.7.3
- Kotlin 2.0.21
- GeckoView 154

## NEXUS 0.4 – Mediathek & Player Overhaul
- Dedicated Video Harvester screen for the current page.
- Discovers public video/player links, iframe/source links and common media URLs.
- Deep-inspects a bounded number of linked video pages.
- Search, select-all toggle (second tap deselects all), and per-item selection.
- Direct-media results can be passed to the existing downloader; ZIP archiving is provided by `ZipArchiveEngine` with `nexus_manifest.json`.
- No DRM, CAPTCHA, login or access-control bypass is implemented.

The project contains no visible AI/ChatGPT branding.

## Build note
The source archive is prepared for Android Studio/Gradle. The project is configured for Android Studio with JDK 17, Gradle 8.9, Android Gradle Plugin 8.7.3, compileSdk/targetSdk 35, and Android SDK Platform 35. The CI workflow uses the same toolchain. The Video Harvester uses bounded HTTP inspection and public page markup; it does not attempt to bypass protected playback.

## NEXUS 0.4 – Mediathek, Player, Fixes
- Package fully renamed to `com.nexus.browser` (no legacy TUF-Blade naming left).
- Real error pages on load failure (DNS, TLS, timeout, offline) instead of a blank screen.
- Tabs are persisted across app restarts (URLs + active tab restored on launch).
- Ad-block rule matching hardened: filter options (`$domain=`, `$third-party`, etc.) are now parsed and applied instead of being matched as literal text, removing a class of false positives.
- Mediathek rebuilt with two views: "In Arbeit" (live per-video progress bars, downloads survive app restart) and "Meine Downloads" (fully offline, no network needed).
- New YouTube-style video player (`NexusPlayerActivity`) with custom controls and a sleep timer (15/30/45/60 min or "nach diesem Video"), which pauses playback at zero.
