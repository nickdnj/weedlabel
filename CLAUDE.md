# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repo state

**Canary spike scaffolded** (2026-05-09). Xcode project at `weedlabel.xcodeproj/` (generated from `project.yml` by `xcodegen` — `brew install xcodegen` to regenerate). Sources in `weedlabel/` cover the entire spike pipeline (Generable schema, sanity checker, FM availability gate, extraction + summary services with P6 validator, VisionKit bridge, Variant C post-scan view from `/design-shotgun`). Tests in `weedlabelTests/` cover the P6 regex denylist and the productType-aware sanity rules. The canary image (`assets/validation/zips-blue-candy-rain.jpeg`) is **not yet dropped in** — that's the gate to actually validating P1.

The active design doc is `~/.gstack/projects/nickdnj-weedlabel/nickd-main-design-20260509-144715.md` — the durable source of truth for v1 architecture decisions, premises, and validator specs. Read that before any non-trivial change.

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
