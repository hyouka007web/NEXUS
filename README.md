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
- Android API 37.1
- Gradle 9.5
- Kotlin 2.2
- GeckoView 154

## NEXUS 0.3 – Video Harvester
- Dedicated Video Harvester screen for the current page.
- Discovers public video/player links, iframe/source links and common media URLs.
- Deep-inspects a bounded number of linked video pages.
- Search, select-all toggle (second tap deselects all), and per-item selection.
- Direct-media results can be passed to the existing downloader; ZIP archiving is provided by `ZipArchiveEngine` with `nexus_manifest.json`.
- No DRM, CAPTCHA, login or access-control bypass is implemented.

The project contains no visible AI/ChatGPT branding.

## Build note
The source archive is prepared for Android Studio/Gradle. A Gradle wrapper is not included in this archive, so build with the project's compatible Android Studio/Gradle environment. The Video Harvester uses bounded HTTP inspection and public page markup; it does not attempt to bypass protected playback.
