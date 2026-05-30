# Design System — Pocketbud

> **Pocketbud** — *Your AI budtender. Lives in your pocket, never leaves it.*
> Working brand for the app currently named `weedlabel` / formerly "HighNotes". Repo/target rename still deferred.

Live, editable showcase: **`docs/branding/showcase.html`** (open in a browser). Exportable icon master: **`docs/branding/pocketbud-icon.svg`** + rendered **`docs/branding/icon-master-1024.png`**. Static snapshots and historical explorations are in `docs/branding/` (see its `README.md`).

## Product Context
- **What this is:** A privacy-first, 100% on-device iOS AI budtender. Point the phone at any cannabis label → on-device OCR + Apple Foundation Models extract cannabinoids/terpenes/provenance → grounded plain-English interpretation + a private Log Book.
- **Who it's for:** Curious adult cannabis consumers (Sara / Marcus / Dani) who want to understand what they're consuming and keep a private journal.
- **The one memorable thing:** *It's private — it lives in your pocket and never leaves.* Every visual choice serves this. The privacy promise is a hero element, not fine print (see Privacy Pillars).
- **Project type:** Native iOS 26+ app (SwiftUI). Light + dark mode, Dynamic Type, system materials.

## Aesthetic Direction
- **Direction:** Bold Playful — confident, friendly, high-contrast, big rounded type, with personality (the icon literally jokes on the name).
- **Decoration level:** Intentional — soft shadows, rounded cards, generous negative space.
- **Mood:** Premium and warm, never stoner-cliché. The cannabis cue is a single *stylized, smooth* leaf.
- **App surfaces are dark-first** (privacy = night). The **app-icon scene is light** (a white dress shirt) so the green pops and the icon stands out as the premium/light tile on a home screen.

## Color
- **Approach:** Green-primary, amber-accent. Green is the brand; amber is the one warm spark.
- **Green (primary):** Leaf `#2FA866` · Bright `#3FBE7D` · Deep `#1C6E45`. Badges, chips, strain tags, the privacy pillars, the icon flap + leaf.
- **Amber (accent):** `#FFB020` · Ember `#FF8A1E`. The large THC number, the camera shutter, the active tab, the "bud" in the wordmark, the joint's lit ember. Use sparingly so it pops.
- **Sage (soft tint):** `#6B8F71` — quiet green for low-emphasis surfaces.
- **Dark surfaces (app):** Green-Ink `#0C120E` / `#0A0F0C` · Card `#121814` · Hairline `#232A25`.
- **Light / cream:** `#FBF8F1` / `#F7F3EC` (icon shirt, light mode bg) · Ink Charcoal `#1A1A1F` (light-mode text).
- **Cream text on dark:** `#F7F3EC`; muted `#8B9089`.
- **Semantic:** success `#34C759`, warning `#FFB020`, error `#FF3B30`, info `#0A84FF`.
- **Dark-mode strategy:** dark green-ink is the default app theme; light mode is warm cream.

## Privacy Pillars (load-bearing UI pattern)
The privacy promise is shown as **three bold green pillars**, not a small badge:
**◹ 100% on-device** · **⌀ No internet** · **🛡 Nothing leaves your phone**
Each = icon + bold SF Pro Rounded label in a green-outlined chip. Use on the hero/marketing surfaces and (condensed) on the scan + results screens. This is the single most important message — give it weight.

## Typography
- **Display / Hero:** SF Pro Rounded, weight 800, tracking -0.02em. (`ui-rounded` in HTML mockups.)
- **Body / UI:** SF Pro Text (`-apple-system`).
- **Data / numbers:** SF Mono, tabular figures — cannabinoid/terpene percentages.
- **Scale (pt):** caption 11 · footnote 13 · body 16 · title3 20 · title2 26 · large THC readout 54–76.

## Iconography & Logo
- **App icon — "Pocketbud" (shirt pocket protector):** a literal, playful take on the name. A **white/cream dress shirt** (with placket + buttons) and a **chest patch pocket**; a **green pocket-protector flap** (scalloped hem, pen slots) sits on the pocket; a **bright-green cannabis leaf** and a **lit joint** (cream body, amber ember, soft smoke wisp) pop out of it. The leaf is sized to stay *inside* the pocket width. Green pops against the white shirt; the ember is the warm accent.
  - **Source:** `docs/branding/pocketbud-icon.svg` (standalone 1024 SVG). Export the App Store master from it (1024×1024 PNG, no alpha) → `docs/branding/icon-master-1024.png`.
  - **Small sizes:** the joint + smoke drop out below ~60px; the leaf + green pocket carry the mark. iOS allows per-size artwork if a simplified small icon is wanted.
- **Wordmark:** `Pocket` in cream/ink + `bud` in amber, SF Pro Rounded 800. Dark + light lockups.

## Spacing
- **Base unit:** 4px. **Density:** comfortable. **Scale:** 2xs(2) xs(4) sm(8) md(16) lg(24) xl(32) 2xl(48).
- **Screen padding:** 17–22px horizontal.

## Layout
- **Approach:** grid-disciplined within iOS conventions; one hero element per screen.
- **Border radius:** chips/badges 999 (pill) · cards 16–18 · app icon 22.5% (iOS superellipse) · tab bar Scan · Log Book · About.

## Motion
- **Approach:** intentional. Scan→result transition, card entrances, amber shutter capture animation.
- **Easing/Duration:** enter ease-out, exit ease-in; micro 100ms, short 200ms, medium 320ms.

## Screens (mockups in docs/branding/showcase.html)
1. **Scan** — live camera, amber corner reticle, "Point at any label / Reading on-device — nothing is uploaded", amber shutter.
2. **Results** — privacy badge → hero strain name → large amber THC% (mono) → green terpene chips → provenance → "Pocketbud says" AI summary card.
3. **Log Book** — search + grouped cards (icon thumb, name, type, THC%), marked Private.
4. **About + Tip Jar** — logo, "Everything stays on your phone" panel, three gentle consumable tips, never a paywall.

## Decisions Log
| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-05-30 | Name → **Pocketbud** | Clearable (vs. "Stash AI"); cannabis lane open; "pocket" = on-device/private built into the name |
| 2026-05-30 | Bold Playful aesthetic | User pick; personality without cliché |
| 2026-05-30 | **Green-primary, amber-accent** palette | User pushed for more green; green = brand, amber = one warm spark; replaces the earlier amber-forward and the older green→violet gradient |
| 2026-05-30 | Icon = white-shirt **pocket protector** with leaf + lit joint | User direction; literal play on the name, witty, green pops on white; leaf sized to stay inside the pocket |
| 2026-05-30 | Privacy shown as **three bold pillars** | Privacy is the core differentiator — it gets hero weight, not a small badge |
