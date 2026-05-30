# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repo state

**Device-tested v1 spike** (updated 2026-05-27). The product is now **HighNotes — "Your AI budtender"** (repo/target still named `weedlabel`; rename deferred). On-device scan → two-pass Foundation Models extraction → strain intelligence → grounded AI summary, with high-res capture, a user-correctable strain DB, learn-more links, and a **StoreKit tip jar** (the one, never-pushy way to support the app — reached only from About). 224 tests passing.

**The current specs live in `docs/` — read these first:**
- `docs/PRD-v1.md` — product requirements
- `docs/SAD-v1.md` — software architecture (pipeline, components, safety layers, build/signing)
- `docs/UXD-v1.md` — UX flows and screens
- `docs/EXECUTION-LOG-2026-05.md` — how the spike became v1, every scope change, open issues
- `docs/legacy/` — the dead Next.js/Supabase PWA v0.1 (read only for the durable *why*)

The older `.gstack` design doc and the v0.1 docs predate the native pivot and the reliability-first reshaping — defer to `docs/*-v1.md`.

**Signing:** `project.yml` sets `DEVELOPMENT_TEAM: 5VPR237YHV`, so xcodegen regens no longer break device signing.

## Architecture (target)

Native iOS app, **fully on-device**, no backend. Pipeline:

1. **VisionKit `DataScannerViewController`** — live camera capture of OCR text + barcodes/QR in one component.
2. **Vision framework** — detect the NJ universal cannabis symbol as a compliance signal.
3. **Foundation Models (on-device LLM)** — extract a `CannabisLabel` `Generable` struct from the OCR text. The `Generable` schema is the contract; everything downstream depends on it parsing cleanly.
4. **Foundation Models again** — generate the user-facing interpretation/report from the parsed struct.
5. **SwiftData** — local persistence of products + sessions, with optional iCloud sync.
6. **Optional COA fetch** — if a QR resolves to a Certificate of Analysis URL.

**Hardware/OS gate:** **iOS 26.0+ minimum** (Foundation Models' public stable `@Generable` macro is `@available(iOS 26.0, *)` — discovered during the canary spike build attempt; the original "iOS 18.1+" claim was wrong). Within iOS 26, Foundation Models also requires Apple-Intelligence-capable hardware (iPhone 15 Pro / 16 / 17 series / M-series iPad). Hardware-incapable or AI-disabled iOS 26 users still get the scan + structured-data view; AI features are gated to capable hardware. **No cloud LLM fallback** — see the active design doc at `~/.gstack/projects/nickdnj-weedlabel/` for the older-device fallback decision.

## What's superseded (do NOT use)

`docs/legacy/` documents a Next.js 15 PWA on Vercel + Supabase (Postgres/Auth/Storage/Edge Functions) + Claude Sonnet 4.6 vision through an Edge Function. **All platform-specific decisions there are dead** (Next.js, Supabase, RLS, Anthropic API, per-scan cost model). Read those docs for *why* (personas, wedge thesis, field schemas, NJ-CRC label structure, logging modes, phasing) — not *how*.

What still applies from v0.1: persona work (Sara/Marcus/Dani), the wedge thesis ("remove manual data entry from cannabis journaling"), field schemas (Metrc tag, cannabinoids, terpene panel, license #, harvest/expiration, batch/lot — these translate directly to the Swift `Generable` type), logging modes (quick 4-tap vs. detailed 7-section), and P0/P1/P2 phasing.

## The validation canary

`assets/validation/zips-blue-candy-rain.jpeg` (image not yet committed) is the canonical canary: Zips "Blue Candy Rain" 28g flower, Fresh Grow LLC, license C000186, harvest 2025-12-10. NJ-CRC labels are colon-delimited key:value structured, so Foundation Models extraction should be near-perfect. Expected parse:

- Cannabinoids: THCA 29.73%, Δ9-THC 1.45%, CBG 0.49%, total 32.25%
- Terpenes: 5.03% total — myrcene 1.83%, limonene 0.84%, linalool 0.84%, β-caryophyllene 0.44%
- Provenance: cultivator + license + Metrc tag + harvest/expiration + two QR codes (one likely COA)

**Run the prototype against this label first.** If Foundation Models output quality clears the bar on real OCR text, the rest is mechanical UI work. If it doesn't, the project shape changes — better to know on day one. Each new label form factor (flower / vape / edible / concentrate / pre-roll) should get one canonical canary committed to `assets/validation/`.

## Build / test commands

No project yet — once scaffolded, expect the standard Xcode flow:

```bash
# Build (replace scheme/destination after scaffolding)
xcodebuild -scheme weedlabel -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# Run unit tests
xcodebuild -scheme weedlabel -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test

# Single test
xcodebuild -scheme weedlabel -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test -only-testing:weedlabelTests/CannabisLabelParserTests/testZipsBlueCandyRain
```

Foundation Models and `DataScannerViewController` both need a real device or simulator on **iOS 26.0+**. The `@Generable` extraction path specifically requires Apple-Intelligence-capable hardware (iPhone 15 Pro / 16 / 17 series / M-series iPad) to test end-to-end; simulator coverage of the FM step is limited even on iOS 26 simulators.

## Cost / distribution

$0 ongoing infrastructure (no Supabase, no Vercel, no Anthropic API). **$99/yr Apple Developer Program is required for both TestFlight and App Store** (TestFlight goes through App Store Connect, which requires the paid program — the original "TestFlight is free" claim was wrong). The genuinely free path before signing up is sideloading via Xcode with a personal Apple ID (3-app limit, 7-day re-signing). Don't reintroduce server dependencies without an explicit pivot — "100% on-device" is a load-bearing product claim, not just an implementation detail.

**Tip jar / IAP.** The tip jar (`TipJar.swift` + `TipJarView.swift`) is the *only* monetization and the *only* thing besides external-link taps that leaves the device — three **consumable** In-App Purchases (Apple requires IAP for developer tips, gl. 3.1.1; PayPal/etc. would be rejected). Tips are pure goodwill; never a paywall. Local testing runs against `TipJar.storekit` (repo root, wired into the run scheme via `project.yml` `storeKitConfiguration`) and works **only when launched from Xcode** — `simctl launch` doesn't inject it. Before shipping, the three product IDs (`com.demarconet.weedlabel.tip.{small,medium,large}`) must be created in App Store Connect (needs the paid account + agreements/tax/banking). This IAP is *not* a "server dependency" — it's Apple-mediated and carries no user data, so it doesn't violate the on-device claim.
## gstack

This repo's Claude Code workflow uses [gstack](https://github.com/garrytan/gstack). To install it (one-time, per machine):

```
git clone --single-branch --depth 1 https://github.com/garrytan/gstack.git ~/.claude/skills/gstack && cd ~/.claude/skills/gstack && ./setup
```

(`./setup` requires [bun](https://bun.sh).)

Once installed:
- Use the `/browse` skill for **all** web browsing. Never use `mcp__claude-in-chrome__*` tools.
- Available skills: `/office-hours`, `/plan-ceo-review`, `/plan-eng-review`, `/plan-design-review`, `/design-consultation`, `/design-shotgun`, `/design-html`, `/review`, `/ship`, `/land-and-deploy`, `/canary`, `/benchmark`, `/browse`, `/connect-chrome`, `/qa`, `/qa-only`, `/design-review`, `/setup-browser-cookies`, `/setup-deploy`, `/setup-gbrain`, `/retro`, `/investigate`, `/document-release`, `/document-generate`, `/codex`, `/cso`, `/autoplan`, `/plan-devex-review`, `/devex-review`, `/careful`, `/freeze`, `/guard`, `/unfreeze`, `/gstack-upgrade`, `/learn`.

## Design System
The brand is **Pocketbud** ("Your AI budtender. Lives in your pocket, never leaves it.") — leading name as of 2026-05-30, repo/target rename still deferred. Read `DESIGN.md` before any visual or UI decision; colors, SF Pro Rounded typography, the Bold-Playful dark-first aesthetic, and the Leaf-in-Pocket icon are defined there. Mockups + editable SVG/HTML live in `docs/branding/`. App Store submission requirements (incl. cannabis guideline 1.4.3 and the "No Data Collected" privacy label) are in `docs/APP-STORE-CHECKLIST.md`. Do not deviate from DESIGN.md without explicit user approval.
