# Design System — Pocketbud

> **Pocketbud** — *Your AI budtender. Lives in your pocket, never leaves it.*
> Working brand for the app currently named `weedlabel` / formerly "HighNotes". Repo/target rename still deferred.

Visual mockups live in `docs/branding/` (open the `.html` files in a browser to edit; PNGs are rendered snapshots).

## Product Context
- **What this is:** A privacy-first, 100% on-device iOS AI budtender. Point the phone at any cannabis label → on-device OCR + Apple Foundation Models extract cannabinoids/terpenes/provenance → grounded plain-English interpretation + a private Log Book.
- **Who it's for:** Curious adult cannabis consumers (Sara / Marcus / Dani) who want to understand what they're consuming and keep a private journal. Privacy-conscious, not necessarily heavy users.
- **The one memorable thing:** *It's private — it lives in your pocket and never leaves.* Every visual choice serves this.
- **Project type:** Native iOS 26+ app (SwiftUI). Light + dark mode, Dynamic Type, system materials.

## Aesthetic Direction
- **Direction:** Bold Playful — confident, friendly, high-contrast, big rounded type. The polish of Things/Bear with more personality.
- **Decoration level:** Intentional — soft shadows, rounded cards, generous negative space. No texture-for-texture's-sake.
- **Mood:** Premium and warm, never stoner-cliché. **No detailed cannabis leaf, no neon green, no green-leaf-on-black.** The cannabis cue is a single *stylized, smooth* leaf used only in the icon.
- **Dark-first:** Privacy reads as night/secret/intimate. The signature surface is near-black; light mode is a warm cream alternative.

## Typography
- **Display / Hero:** SF Pro Rounded, weight 800, tight tracking (-0.02em). Native iOS warmth; carries the playful tone. (`ui-rounded` in HTML mockups.)
- **Body / UI:** SF Pro Text (`-apple-system`).
- **Data / numbers:** SF Mono with tabular figures — cannabinoid/terpene percentages must align and read precise.
- **Scale (pt):** caption 11 · footnote 13 · body 16 · title3 20 · title2 26 · large THC readout 54–76.

## Color
- **Approach:** Expressive — amber is the load-bearing brand color, used boldly.
- **Primary accent — Amber Bright:** `#FFB020` (Bold Playful) / **Honey Amber** `#F5A623` (calmer contexts). Warmth, the "high note," all primary CTAs and key numbers.
- **Secondary — Sage:** `#6B8F71` (with tint `#9EC3A4`). The premium, muted cannabis nod. Strain tags, the privacy panel.
- **Dark surfaces:** Twilight Ink `#0B0B0E` / `#0E0D13`, Indigo Surface `#1B1A24`, card `#15151A`, hairline `#26262E`.
- **Light surfaces:** Warm Cream `#F7F3EC` / `#FBF8F1`, Ink Charcoal `#1A1A1F` text, amber-on-light text `#9A6500`.
- **Cream text on dark:** `#F7F3EC`; muted `#8B8794`.
- **Semantic:** success `#34C759`, warning `#FFB020`, error `#FF3B30`, info `#0A84FF` (iOS system).
- **Dark-mode strategy:** dark is the *default* design, not a derived theme. Light mode reduces amber saturation slightly to avoid glare on cream.

## Iconography & Logo
- **App icon — "Leaf in Pocket":** a stylized smooth cannabis leaf (5 leaflets, single color, not serrated clip-art) rising out of a pocket pouch. Twilight leaf+pocket on a bold **amber tile** (`#FFB020`→`#E08600` gradient) so it pops on a dark home screen. Verified legible 1024px → 40px.
- **Wordmark:** `Pocket` in cream/ink + `bud` in amber, SF Pro Rounded 800. Works on dark and light.
- **Privacy motif:** a small lock-in-pouch badge ("Private · On your phone") recurs on every screen.
- **Source:** `docs/branding/icon-final.html` (SVG, editable). Export the 1024×1024 master from there.

## Spacing
- **Base unit:** 4px. **Density:** comfortable.
- **Scale:** 2xs(2) xs(4) sm(8) md(16) lg(24) xl(32) 2xl(48).
- **Screen padding:** 18–22px horizontal.

## Layout
- **Approach:** grid-disciplined within iOS conventions; hero element per screen (the strain name + THC number on results).
- **Border radius:** chips/badges 999 (pill) · cards 16–18 · app icon 22.5% (iOS superellipse) · phone-content cards 14–18.
- **Tab bar:** Scan · Log Book · About.

## Motion
- **Approach:** intentional. Scan→result transition, card entrances, a satisfying capture animation on the amber shutter.
- **Easing/Duration:** enter ease-out, exit ease-in; micro 100ms, short 200ms, medium 320ms.

## Screens (mockups in docs/branding/)
1. **Scan** — live camera, amber corner reticle, "Point at any label / Reading on-device — nothing is uploaded", amber shutter.
2. **Results** — privacy badge → hero strain name → large THC% (mono) → terpene chips → provenance → "Pocketbud says" AI summary card.
3. **Log Book** — search + grouped cards (icon thumb, name, type, THC%), all marked Private.
4. **About + Tip Jar** — logo, "Everything stays on your phone" sage panel, three gentle consumable tips ($1.99 / $4.99 / $9.99), never a paywall.

## Decisions Log
| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-05-30 | Name → **Pocketbud** | Clearable (vs. "Stash AI" — 3+ existing apps + Stash Financial TM); cannabis lane open; "pocket" = on-device/private built into the name |
| 2026-05-30 | Bold Playful + dark-first | User pick; privacy=night, amber pops, personality without cliché |
| 2026-05-30 | Leaf-in-Pocket icon, stylized leaf | User wants a cannabis cue; stylized/smooth leaf avoids clip-art + Apple is fine with leaves for informational apps |
| 2026-05-30 | Created by /design-consultation | Foundation for all UI work |
