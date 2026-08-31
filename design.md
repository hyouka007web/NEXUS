# NEXUS Browser — Design System

NEXUS is the sole branding — no legacy TUF-Blade references remain anywhere in the codebase or package structure.

## Visual direction
Dark-mode only. Gold circuit-trace accents, now on rounded, modern surfaces: pill-shaped search bars, fully round icon buttons, rounded tab chips and rounded-top panels instead of sharp rectangles.

### Palette
- bg-base #1E1E1E
- bg-surface #2E3033
- bg-surface-raised #3A3D40
- bg-pill #252729 (search bar / start page surface)
- accent-primary #FFB800
- accent-primary-soft #40FFB800
- accent-success #00FF66
- accent-danger #FF3B3B
- text-primary #FFFFFF
- text-muted #A0A0A0
- border #3F4245

### Shape
- radius_button 14dp, radius_panel 18dp, radius_pill 28dp (fully round on a 52–56dp tall element)
- icon buttons are fully round (oval), not rounded rectangles
- sidebar's collapsed rail is 28dp wide so its toggle arrow stays visible and tappable (never below ~24dp)

## Layout
Top bar: two compact rows only — (1) logo/wordmark + shield counter + overflow menu, (2) one full-width rounded search/URL pill with an inline reload icon. Back/forward/home/scraper/download/mediathek live in the sidebar and the overflow menu, not duplicated in the top bar, so the bar never overflows on narrow portrait screens.
Tab strip: horizontal, compact, scrollable, pill-shaped chips.
Sidebar: navigation/tools, collapsed to a thin gold rail (still visible, not hidden); expanded on demand.
Start page: native NEXUS screen (logo, rounded search field, current search engine) shown for new/home tabs instead of loading an external search engine's homepage, which could render blank inside GeckoView.
Web content: GeckoView.
Bottom floating panel: compact, non-modal, rounded top corners; notifications for blocked redirects, scraper results and downloads. It auto-dismisses and offers a single OPEN action where appropriate.

## Motion
- sidebar: 180ms ease-out
- bottom panel: 220ms slide/fade
- loading circuit trace: 400–600ms
- no bounce/scale decoration
- respect reduced-motion preferences where Android exposes them

## UX principle
The browser should feel like a professional tool rather than a collection of dialogs. Blocking events never open a large modal automatically; the user gets a small bottom notification and can tap OPEN if desired.
