# Execution Log — HighNotes (weedlabel) iOS Spike → v1

**Period:** 2026-05-09 → 2026-05-27
**Author:** Nick DeMarco with Claude (pair-dev sessions)
**Scope:** From "drop the canary image and run extraction" through a working,
on-device, device-tested scan→extract→summarize pipeline with strain
intelligence, user corrections, and a reliability-first capture flow.

This log records *how we executed against the plan* and *every scope change* we
made along the way. The formal specs that resulted are:
- [`PRD-v1.md`](./PRD-v1.md) — what the product is and must do
- [`SAD-v1.md`](./SAD-v1.md) — how it's built
- [`UXD-v1.md`](./UXD-v1.md) — the screens and flows

---

## 1. Where we started

The canary spike was scaffolded (Xcode project via xcodegen, `@Generable`
`CannabisLabel`, sanity checker, FM availability gate, extraction + summary
services, VisionKit bridge, a PostScan view). The canary image
(`assets/validation/zips-blue-candy-rain.jpeg`) was **not yet committed** — that
was the gate to validating the core premise (P1): *does Foundation Models extract
a clean structured label from real OCR?*

The plan: drop the canary, run it, and if FM output cleared the bar, the rest is
mechanical UI. If not, the project shape changes.

## 2. What we learned (the premises that moved)

| Premise (as planned) | What we found | Source |
|---|---|---|
| FM `@Generable` needs capable device hardware to test | **Works in the iPhone 17 Pro iOS-26 Simulator** (`availability=available`) | first canary runs |
| Vision OCR works everywhere | **Fails in the Simulator** ("Could not create inference context"); device-only | sim runs |
| The Zips canary is a near-perfect colon-delimited parse | **It's a worst-case input** — cylindrical tin shot at an angle, two-column potency table, OCR de-syncs name↔value | bbox analysis |
| One `@Generable` schema → one FM call | **The combined schema overran the 4096-token context** repeatedly (4093–4943 tokens) | device logs |
| A document/rectangle detector would frame the label | **Apple's document scanner can't isolate a label from packaging** — geometry is the wrong signal here | user device test |
| Live-frame OCR is good enough | **Live preview-frame OCR is a major noise source**; a high-res still reads far cleaner | device logs |

These findings drove the strategic pivot in §4.

## 3. Execution timeline (what we built, in order)

1. **macOS Vision OCR harness** (`tools/ocr_canary.swift`) — validated the OCR
   leg without a device; exposed the noise patterns (% glyph → `90/00/06/%%`,
   terpene typos, two-column de-sync).
2. **Static-image OCR path** (`StaticImageOCR`) + Debug **"Run bundled canary"**
   entry + `-AutoRunCanary` launch arg — made the FM step runnable headlessly in
   the Simulator against a fixture (since live Vision fails there).
3. **OCR preprocessor** (`OCRPreprocessor`) — deterministic cleanup of the
   learnable noise, so the prompt doesn't pay tokens to re-derive it.
4. **Prompt Lab** (Debug `PromptLabView`) — in-app prompt iteration with A/B
   against baseline, clipboard export, live result diff.
5. **Phase-1 capture UX** — viewfinder corner brackets + dimmed mask, live
   **field-detected chips** (`FieldDetector`), explicit shutter (replaced the
   150-char auto-fire), and a **preview/confirm** screen.
6. **Auto-capture** — when all field chips are green for ~1s, the shutter fires
   itself; countdown ring on the shutter; manual override always available.
7. **Context-window campaign** (the longest thread) — in escalating order:
   slashed the system prompt, stripped regulatory boilerplate from OCR, **dieted
   the schema** (dropped fields), **flattened** the nested structs, and finally
   **split extraction into two FM passes** (metadata + chemistry) — which solved
   it for good.
8. **Safety layer** — the **hallucination guard** (reject any summary percentage
   not present in the parsed label), THC↔Δ9-THC and THCA↔Total-THC **post-fixes**,
   **strain-name post-fix** (the model picking "Limonene"/"Beicaropa" as strain).
9. **Verify-screen removal** — the dead-end "verify" screen became a non-blocking
   **warning banner** on the result screen; the summary always runs (the
   hallucination guard is the backstop).
10. **Strain intelligence** (`StrainKnowledgeBase`) — sativa/indica/hybrid from
    the printed `(S)/(I)/(H)` marker first, then name-lineage inference; later
    extended to **5 classes** (added hybrid-leaning-sativa / -indica); later again
    with **lineage flavor character** (Gelato→dessert, Diesel→fuel, Kush→pine…).
11. **User-correctable strain DB** (`StrainOverrideStore`) — tag/correct a
    strain's class; persists locally; user correction outranks marker/lineage.
12. **Learn-more links** (`ProductLinks`) — surface URL-bearing QR payloads
    (COA links) + a cultivator web search.
13. **Compelling summary** — rewrote the summary prompt to be vivid and
    sensory; then **toned it to informational** after Apple's built-in safety
    guardrail rejected the promotional framing on cannabis content. Enriched the
    deterministic fallback to lead with strain character instead of "couldn't
    read."
14. **High-res capture** (`ScannerController` + `DataScannerViewController.capturePhoto()`)
    — capture a sharp full-res still at confirm time and OCR *that*, with a
    fallback to live OCR. The single biggest expected quality lever.
15. **HighNotes rebrand** (parallel session) — `Brand.swift`, first-run
    `OnboardingView`/`RootView`; tagline "Your AI budtender"; bold-&-playful
    visual direction; "100% on-device, no accounts, no tracking" positioning.

Every step kept the test suite green; it grew from ~35 to **199 tests** by the
end of this build-out (and to **224** with the later tip jar + corrections work).

## 4. Scope changes (decisions that altered the plan)

1. **Strategic pivot: reliability over precision.** Photo-OCR of chemistry
   percentages is unreliable on real packaging (curved, glossy, two-column). We
   stopped trying to be a spec sheet and leaned into what we GET reliably:
   strain name, classification, license, Metrc, dates, QR. Chemistry is
   best-effort and clearly flagged when suspect.

2. **Name-based inference became a primary feature**, not a nicety. The strain
   name + printed S/I/H marker reliably yields a sativa/indica/hybrid read,
   typical effect, time-of-day, and flavor character — even when chemistry
   extraction returns nothing.

3. **Two-pass FM extraction** replaced the single combined schema. `CannabisLabel`
   is no longer `@Generable`; it's composed from two `@Generable` passes
   (`LabelMetadata`, `LabelChemistry`). This is the load-bearing fix for the
   on-device context window.

4. **Schema trimmed.** Dropped from the extraction schema: `terpenesOther`
   (dynamic array — very expensive), `growthMethod`, `batchOrLot`, `cbga`,
   `cbda`. Add back when an edible canary needs them.

5. **No rectangle/document detection.** The check-deposit metaphor inspired the
   capture flow, but document segmentation empirically fails to isolate a label
   from packaging. Content confirmation (the field chips) is the correct
   "looking at the right thing" signal for this domain.

6. **Orientation locked to portrait.** The capture path handles label
   orientation internally; no landscape mode.

7. **The "verify" gate is non-blocking.** Sanity problems surface as a banner,
   never a dead end; the AI summary always attempts to run.

8. **Rebrand + monetization stance.** weedlabel → **HighNotes**. Never paywall;
   future revenue is optional tipping and possibly monetized external links —
   neither built now.

9. **Tip jar built (2026-05-27).** Tipping moved from "deferred" to shipped in
   code. Three StoreKit **consumable** tiers ($0.99 / $2.99 / $4.99), reached
   only from About — never pushy. Apple requires IAP for developer tips (gl.
   3.1.1), so external payment links were never an option. The view renders a
   `TipTier` value type rather than StoreKit's `Product` (previewable, testable).
   A local `TipJar.storekit` wired into the run scheme makes the whole flow
   purchasable in the Simulator today — the only thing waiting on the paid Apple
   account is registering the product IDs in App Store Connect. This is the one
   network-touching part of an otherwise on-device app; documented as a bounded,
   no-user-data exception, not a backend.

## 5. Known open issues (carried forward)

- **Strain name vs lot code.** On labels where a lot code reads like a strain
  (e.g. "Blueberry Cariar"), the model sometimes picks it over the marketing
  name ("Blue Candy Rain"), which can also mis-key the lineage inference. The
  strain post-fix only catches chemical-fragment names, not plausible-looking
  lot codes.
- **THCA vs Total-THC assignment** still occasionally swaps on dense two-column
  potency blocks; the sanity checker catches it as a warning.
- **High-res capture is device-only** (`capturePhoto()` has no Simulator camera);
  Simulator validation uses the bundled OCR fixture.

## 6. Test + build status at end of period

- **224 tests passing** across 14 suites — the original 11 (`FieldDetector`,
  `LabelSanityChecker`, `OCRPreprocessor`, `P6Validator`,
  `SummaryHallucinationGuard`, `SummaryFallback`, `ScanModel pipeline`,
  `StrainKnowledgeBase`, `StrainNameFixer`, `StrainOverrideStore`, `ProductLinks`)
  plus `TipJar` (tip-jar logic), `ProductTypeOverrideStore`, and in-progress
  strain-name-correction tests.
- Build green on iPhone 17 Pro Simulator (iOS 26 SDK).
- Device signing resolved: `DEVELOPMENT_TEAM: 5VPR237YHV` now set in
  `project.yml`, so xcodegen no longer wipes it.
