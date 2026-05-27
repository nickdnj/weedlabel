# Open Issues — HighNotes

**Last Updated:** 2026-05-27
**Status:** Consolidated backlog from the spike→v1 work. Severity:
**P1** = trust/correctness or blocks ship · **P2** = quality/UX · **P3** = nice-to-have/debt.

This is the single source of truth for known issues. Cross-referenced from the
[PRD](./PRD-v1.md), [SAD](./SAD-v1.md), and [execution log](./EXECUTION-LOG-2026-05.md).

---

## Extraction quality

### OI-1 · Strain name vs lot code  **(P1)**
On labels where a lot/batch code reads like a strain (e.g. "9 - 120925 -
Blueberry Cariar"), the model sometimes picks it over the marketing name ("Blue
Candy Rain"). `StrainNameFixer` only catches names that are *chemical fragments*
(e.g. "Limonene", "Beicaropa") — not plausible-looking lot codes.
**Knock-on:** a wrong strain name mis-keys the lineage classification
(e.g. "blueberry" → indica for a product that isn't). Most user-visible quality
gap. Candidate fix: prefer the top-of-label prominent line; down-rank lines that
contain digit-dash-digit lot patterns.

### OI-2 · THCA ↔ Total THC assignment swap  **(P2)**
On dense two-column potency blocks the model still occasionally assigns the
Total-THC value to `thca` (or vice-versa). The post-fixes catch the common cases;
the sanity checker flags the rest as a (non-blocking) warning banner. Residual.

### OI-3 · totalCannabinoids fabrication  **(P2)**
Seen the model emit a round/invented `totalCannabinoids` (e.g. `100`, `29.57`)
that isn't on the label. Sanity catches the egregious ones; the summary
hallucination guard prevents fabricated numbers reaching the AI text, but the
*field* can still be wrong in Source Data.

### OI-4 · Chemistry unreliable on curved / two-column labels  **(P2, structural)**
The fundamental limitation behind OI-2/OI-3: OCR de-syncs name↔value on
two-column potency tables and curved/cylindrical packaging. High-res capture
(`capturePhoto`) is the mitigation we just shipped; measure whether it closes the
gap before investing in layout-aware OCR.

### OI-5 · Cultivator brand/strain confusion  **(P3)**
The `cultivator` field sometimes gets the brand+strain string (e.g. "Krnd
Lollipopz") instead of the producer. Low impact; no post-fix yet.

---

## AI summary & safety

### OI-6 · Apple FM guardrail rejections  **(P2)**
Apple's built-in Foundation Models content guardrail can reject a summary on
cannabis content. We mitigated by toning the prompt to neutral/informational and
falling back to the grounded deterministic summary on `guardrailViolation`. Could
still recur on edge inputs; the fallback keeps it graceful but the AI summary is
lost when it fires.

### OI-7 · Strain insight depends on correct strain name  **(P2)**
Lineage-based classification is only as good as the strain name (see OI-1). When
the name is wrong, the Profile card and summary character can be wrong. User
correction is the escape hatch but the default can mislead.

---

## Capture / platform

### OI-8 · High-res capture is device-only  **(P3, expected)**
`DataScannerViewController.capturePhoto()` has no Simulator camera, and
`StaticImageOCR` fails in the Simulator ("Could not create inference context").
The live high-res path is exercised only on hardware; the Simulator uses the
bundled OCR fixture (`-AutoRunCanary`). By design, but means CI/Simulator can't
cover that path.

### OI-9 · Preview chips reflect live OCR, not the captured still  **(P3)**
The field chips on the preview/confirm screen are computed from the last live
OCR snapshot, not the high-res still that was actually captured. Minor cosmetic
inconsistency; the still's OCR is what's actually used for extraction.

### OI-10 · `clearStrainClass` recomputes from `lastSeenOcr`  **(P3)**
When the user removes a correction, the insight is recomputed from
`lastSeenOcr`, which can be empty on the canary/fixture path (live path is fine).
Edge case.

---

## Validation coverage

### OI-11 · Only a worst-case canary  **(P2)**
The committed canary (`zips-blue-candy-rain`) is a cylindrical tin shot at an
angle — a worst case. We have additional validation images
(`assets/validation/IMG_07xx`) but no second *committed canonical canary* for a
flat label (vape box / edible) to validate the happy path. Adding one may
reintroduce some dropped schema fields (cbga/cbda for edibles).

### OI-12 · OCRPreprocessor over-match risk  **(P3)**
The percent-noise rules are scoped per-line to cannabinoid/terpene context, but a
non-cannabis line that happens to contain a keyword + "NN NN" could still be
rewritten. Low risk on NJ-CRC labels; documented for future label formats.

---

## Productization / debt

### OI-13 · Strip Debug surface before App Store  **(P1 at ship)**
Remove before submission: `PromptLabView.swift` + its `#if DEBUG` wiring in
`ContentView`; `ScanModel.runBundledCanary()/runBundledCanaryLiveOCR()` + launch
args; `extractWithCustomInstructions`/`summarizeWithCustomInstructions`;
`CannabisLabel.diagnosticJSON`; `[CANARY]` logging. All are `#if DEBUG`-gated, so
a Release build excludes them — verify before submitting.

### OI-14 · Repo/target still named `weedlabel`  **(P3)**
Product is **HighNotes**; the repo, Xcode target, and bundle id prefix still say
`weedlabel`. Cosmetic rename deferred.

### OI-15 · Override store is unbounded JSON  **(P3)**
`FileStrainOverrideStore` writes an ever-growing JSON file. Fine at current
scale; migrate to SwiftData when journaling adds data volume.

### OI-16 · App Store cannabis policy risk  **(P2, business)**
Apple's review of cannabis apps is a live risk. Keep all shipped copy
informational, non-promotional, 21+. The on-device + no-commerce posture helps
but doesn't guarantee approval.

---

## Deferred by decision (not bugs — tracked so we don't lose them)

- **Session/consumption journaling + analytics** — the v0.1 core; returns once
  capture is trustworthy.
- **Monetization** — optional tipping and possibly monetized external links;
  explicitly not built. Never paywall.
- **COA fetch/parse** — link-only for now to preserve the on-device claim.
- **iCloud / cross-device sync** of corrections.
- **Layout-aware OCR** for two-column potency tables (only if high-res capture
  doesn't close OI-4).
