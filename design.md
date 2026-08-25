# NEXUS Browser — Design System

NEXUS replaces the old TUF-Blade branding. The visual language remains technical/gaming, but the product name, splash screen and UI copy are NEXUS.

## Visual direction
Dark-mode only. Flat technical surfaces. Gold circuit-trace accents. No gradients or decorative shadows.

### Palette
- bg-base #1E1E1E
- bg-surface #2E3033
- bg-surface-raised #3A3D40
- accent-primary #FFB800
- accent-success #00FF66
- accent-danger #FF3B3B
- text-primary #FFFFFF
- text-muted #A0A0A0
- border #3F4245

## Layout
Top bar: NEXUS logo, URL/search field, shield counter, scraper action, menu.
Tab strip: horizontal, compact and scrollable.
Sidebar: navigation/tools, collapsed to a thin gold rail; expanded on demand.
Web content: GeckoView.
Bottom floating panel: compact, non-modal notifications for blocked redirects, scraper results and downloads. It auto-dismisses and offers a single OPEN action where appropriate.

## Motion
- sidebar: 180ms ease-out
- bottom panel: 220ms slide/fade
- loading circuit trace: 400–600ms
- no bounce/scale decoration
- respect reduced-motion preferences where Android exposes them

## UX principle
The browser should feel like a professional tool rather than a collection of dialogs. Blocking events never open a large modal automatically; the user gets a small bottom notification and can tap OPEN if desired.
