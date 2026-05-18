# weedlabel

NJ cannabis label scanner — native iOS, fully on-device.

Personal cannabis journal: photograph a NJ-CRC dispensary label, get structured cannabinoid + terpene data, an AI-generated interpretation, and longitudinal session tracking. No servers, no accounts, no API costs.

## Status

**Canary spike scaffolded** (2026-05-09). The Xcode project lives in `weedlabel.xcodeproj/`, generated from `project.yml` via `xcodegen` (`brew install xcodegen` if rebuilding). Source files cover: `CannabisLabel` `@Generable` schema (NJAC §17:30-16.3 fields), productType-aware `LabelSanityChecker`, `AvailabilityGate` for Foundation Models triple-state probe, `ExtractionService` and `SummaryService` actors (with the P6 regex/regen/fallback validator pipeline), `DataScannerView` UIKit bridge, and a Variant C-styled `PostScanView` from `/design-shotgun`. The active design doc lives at `~/.gstack/projects/nickdnj-weedlabel/`. Build the spike by opening `weedlabel.xcodeproj`, setting your Team in the `weedlabel` target → Signing & Capabilities, and running on an iOS 26 device with Apple Intelligence enabled.

The repo's own pivot story: this is the pickup point for the iOS build after a pivot away from a Next.js + Supabase + Claude vision PWA. See `docs/legacy/` for the discovery / PRD / architecture work that informed the pivot.

## Architecture (high level)

| Layer | Component |
|---|---|
| Camera + OCR + barcode | VisionKit `DataScannerViewController` |
| Compliance signal | Vision framework — detect NJ universal cannabis symbol |
| Structured extraction | Foundation Models with a `CannabisLabel` `Generable` type |
| Interpretation / report | Foundation Models (on-device LLM) |
| Storage | SwiftData (local), optional iCloud sync |
| Optional enrichment | COA fetch if QR resolves to a Certificate of Analysis URL |

**Device gating:** **iOS 26.0+ minimum** (Foundation Models' public stable `@Generable` macro is `@available(iOS 26.0, *)` — confirmed during the canary spike build attempt 2026-05-09). Within iOS 26, Foundation Models additionally requires Apple-Intelligence-capable hardware (iPhone 15 Pro / 16 / 17 series / M-series iPad). Hardware-incapable or AI-disabled iOS 26 users get scan + structured data view; AI features gated to capable hardware. iOS 18-25 users cannot install the app at all.

**Cost model:** $0 ongoing infrastructure. $99/yr Apple Developer Program required for **both TestFlight and App Store** (TestFlight access goes through App Store Connect, which requires the paid program). The free path before signing up is sideloading via Xcode with a personal Apple ID (3-app limit, 7-day re-signing cadence).

## Why iOS native (not web)

The original direction was a Next.js PWA with Claude Sonnet 4.6 vision through a Supabase Edge Function. PRD v0.1 + SAD v0.1 are preserved in `docs/legacy/`. Pivoted because:

- **Foundation Models** (iOS 26.0+ for stable public API; the framework existed in iOS 18.1 in beta but `@Generable` ships at iOS 26) gives a free on-device LLM with structured `Generable` output — collapses the entire backend.
- **VisionKit DataScannerViewController** does live OCR + barcode in one component; far better than browser OCR.
- **Privacy** — "100% on-device" is a real selling point for cannabis users.
- **$0 ongoing infrastructure** — no Supabase, no Vercel, no Anthropic API bills.

Nutrition label scanning (originally a free flagship to fund a cannabis IAP unlock) was dropped. Apple is shipping nutrition label scanning into the iOS 27 Camera/Health app at WWDC 2026-06-08; the market is too crowded (Yuka, Nutriscan, FoodSwitch) and Apple is about to commoditize the basics. Cannabis label scanning is the actual whitespace — competitors do flower visual ID (KushScan, Kushy Scanner), manual journals (Releaf), or hardware (HiGrade, Purpl PRO). Nobody scans regulated dispensary labels.

## Validation artifact

Zips "Blue Candy Rain" 28g flower label (Fresh Grow LLC, Somerset NJ, license C000186, harvested 2025-12-10) tested 2026-05-09. Parses cleanly:

- **Cannabinoids:** THCA 29.73%, Δ9-THC 1.45%, CBG 0.49%, total 32.25%
- **Terpenes:** 5.03% total — myrcene 1.83%, limonene 0.84%, linalool 0.84%, β-caryophyllene 0.44%
- **Provenance:** cultivator + license + Metrc tag + harvest/expiration + two QR codes (one likely COA)

NJ-CRC labels are colon-delimited key:value structured. Foundation Models extraction should be near-perfect. **Use this label as the canary in the prototype** — drop the image at `assets/validation/zips-blue-candy-rain.jpeg` when you have it on the laptop.

## Open decisions (revisit before v0.2 docs)

1. **Pricing model** — free, paid one-time, or freemium with paid AI features?
2. **Older-device experience** — what does the non-AI version look like? Just structured data, or shell out to a Cloud LLM as fallback?
3. **Backdating window** — can a session be logged against a product purchased weeks ago?
4. **App Store positioning copy** — informational/educational + 21+ age gate is the established path; needs concrete wording.
5. **COA fetching** — fetch + parse on detect, or just deep-link to the lab's site?

## Recommended next session

Start a fresh Claude Code session in this directory. Don't write v0.2 docs yet — prototype the critical path first:

1. Scaffold a SwiftUI Xcode project (iOS 26.0+ target, single-target app).
2. Wire `DataScannerViewController` → capture text + barcodes → display raw OCR.
3. Define a `CannabisLabel` `Generable` type matching the Zips label structure (cannabinoids + terpenes + provenance + metrc + dates).
4. Pipe OCR text into Foundation Models with the `Generable` schema; render the parsed object.
5. Run against the Zips label image. Validate quality before building any UI around it.

If Foundation Models output quality clears the bar on real OCR text, the rest is mechanical. If it doesn't, the project changes shape — better to know that on day one than after building a UI.

After validation, write PRD v0.2 + SAD v0.2 (or skip straight to dev planning if the prototype is conclusive).

## Predecessor

Old repo: [nickdnj/nj-weed-label-app](https://github.com/nickdnj/nj-weed-label-app) — **archived 2026-05-09**. Contained the Next.js PWA discovery + PRD/SAD v0.1. The `docs/legacy/` folder here is the durable reference; the old repo is frozen.
