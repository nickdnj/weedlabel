# Spec — Extraction Confidence & Self-Check

**Status:** Proposed (2026-05-30). **Owner:** capture/extraction.
**Related:** [`OPEN-ISSUES.md`](./OPEN-ISSUES.md) (OI-1/2/3/4/7), `LabelSanityChecker`,
`StrainNameFixer`, `SummaryService` hallucination guard.

## 1. Problem

The 2026-05-30 device batches showed the extraction is usually right but
*silently* wrong on a long tail of dense / merged-OCR labels: Δ9/THCA column
desyncs (`thca=9.0, d9=28.2`), strain names grabbed from boilerplate / logos /
chemotype words, and one outright hallucination (`Blue Candy Rain` on a Lollipopz
scan). We've shipped deterministic guards for each *class* we've seen, but each
new capture surfaces a new fragment. The root cause is unchanged — when the name
or potency block is OCR-merged into a cluttered row, the model has weak signal —
so an enumerated reject-list can't be complete.

**Goal:** stop shipping silent errors. When we're not sure, *say so* and let the
user be the tiebreaker (the app's existing infer-and-correct philosophy), instead
of committing a confident-looking wrong value to the Log Book.

**Non-goal:** making every extraction correct. This is about *knowing* when we're
probably wrong, not eliminating the wrongness.

## 2. Design principles

1. **Cheap deterministic checks first.** Most errors are catchable for free with
   chemistry constraints and signals we already compute. No model call.
2. **Escalate to a second opinion only on doubt.** A second FM pass doubles
   latency/battery; spend it only when the cheap checks flag uncertainty, and
   only as a *genuinely independent* check (varied input/prompt), never a re-roll.
3. **Surface, don't hide.** Low confidence → "best guess, tap to verify," not a
   blank. The user confirms or corrects; corrections already persist
   (`StrainOverrideStore` / `StrainNameOverrideStore` / `ProductTypeOverrideStore`).
4. **Per-field, not per-label.** "THCa is shaky but the name is solid" is more
   useful — and more honest — than one overall warning.

## 3. Signals (all free / deterministic)

We already produce most of these; today we throw them away.

### 3.1 Potency (chemistry constraints)
- **Total-THC identity** (NJAC §17:30-16.3): `Total THC ≈ 0.877·THCA + Δ9`.
  `LabelSanityChecker` *already* checks printed vs `computedTotalThc`. Reuse it as
  a per-field confidence input, not just a banner.
  - Permanent Gas broken: `0.877·9.0 + 28.2 = 36.1` vs printed `25.08` → **low**.
  - Permanent Gas fixed: `0.877·28.2 + 0.35 = 25.08` vs `25.08` → **high**.
- **Ordering** (flower/pre-roll): `THCA ≥ Total THC ≥ Δ9`, and `Δ9 < ~5%`.
  Violations were every swap this session.
- **PRE vs POST reconcile divergence.** `ScanModel` already logs both. A large
  gap between the FM's raw read and the deterministic OCR re-read = two
  independent interpretations disagreeing → lower confidence on that field.
- **Magnitude plausibility.** Already partly in `clampImplausibleValues`; a value
  that had to be clamped/nulled is low-confidence by definition.

### 3.2 Strain name
- **Absent from OCR.** `StrainNameFixer.isAbsentFromOCR` — none of the name's
  significant tokens appear on the label = the dominant hallucination signal
  (`Blue Candy Rain`). Strong **low**.
- **Recovered by the fixer.** `fix()` already returns `didFix`; when it had to
  replace the FM name (boilerplate / tag / logo / chemotype), confidence is
  **medium** — we guessed from a salvage, not a clean read.
- **Lineage agreement.** If `StrainKnowledgeBase` recognizes the name's lineage
  fragment, mild confidence boost; if it's unknown *and* salvaged, lower.

### 3.3 OCR quality (label-level prior)
- **Char count / legible-potency.** `ScanModel.potencyPanelLegible` already gates
  capture; a thin OCR (`chars < ~900`, the Blueberry-Caviar 717-char case) lowers
  the floor for *every* field on that scan.

## 4. Confidence model

Pure, deterministic, unit-testable — same shape as `LabelSanityChecker`.

```swift
enum Confidence: Sendable { case high, medium, low }

struct FieldConfidence: Sendable {
    let thca: Confidence
    let delta9thc: Confidence
    let totalThc: Confidence
    let strainName: Confidence
    // … cbg/cbd/terpenes as needed
    var overall: Confidence   // min across the load-bearing fields
    let reasons: [String]     // human-readable, for the verify sheet
}

enum ConfidenceScorer {
    /// `pre` = the FM's raw values before reconcile; `post` = the displayed label.
    static func score(post: CannabisLabel,
                      pre: CannabisLabel,
                      ocrText: String,
                      ocrCharCount: Int) -> FieldConfidence
}
```

Rules (start simple, tune from the harness):
- Potency field is **low** if it violates the identity/ordering, was clamped, or
  PRE↔POST diverge by > ~15%; **medium** if PRE↔POST diverge a little; else **high**.
- `strainName` is **low** if `isAbsentFromOCR`; **medium** if `didFix` or unknown
  lineage; else **high**.
- A thin-OCR scan caps every field at **medium**.

## 5. Second opinion (escalation, optional Phase 2)

Only when `overall == .low` (or a load-bearing field is low):

1. Re-run **extraction** on a *different input* — the deskewed crop instead of the
   full image, or the full image with a reworded prompt. Independence is the
   point; same prompt + near-zero temperature = no new information.
2. Compare the two extractions field-by-field.
   - **Agree** → promote confidence (two independent reads concur).
   - **Disagree** → keep **low**; prefer the value that satisfies the chemistry
     identity; mark for user verification.
3. Budget: one extra pass, gated, so the common (high-confidence) scan stays fast.

**Blind spot (document it):** self-consistency cannot catch *systematic* bias —
if both passes copy the `@Guide` example, they agree and are both wrong. That
class is owned by §3.2 `isAbsentFromOCR` and the deterministic guards, not by the
second opinion.

## 6. UX (infer-and-correct)

- **High:** show normally. No noise.
- **Medium:** subtle "best guess" affordance on the field (e.g. a dotted
  underline / small chevron) → tap opens the existing correction control.
- **Low:** inline "Double-check this — tap to confirm" on the specific field;
  keep the value visible (don't blank it). On the result screen this replaces the
  single `sanityWarning` banner with per-field cues.
- The **AI summary** already has a hallucination guard; additionally, *suppress or
  soften* the summary when a load-bearing field is **low**, so we don't narrate
  confidently over shaky data.

## 7. Pipeline & data-model changes

- `ScanModel.runPipeline`: capture `pre` (post-extraction, pre-reconcile) and
  `post`; call `ConfidenceScorer.score(...)`; thread a `FieldConfidence` into the
  terminal phase.
- `Phase.ready(label:summary:sanityWarning:strainInsight:)` →
  add `confidence: FieldConfidence`. (`sanityWarning` can fold into
  `confidence.reasons` over time.)
- `LogEntry`: persist `overall` confidence so the Log Book can flag entries that
  were saved under doubt (and prompt later correction).

## 8. What it would have caught this session

| Case | Signal | Verdict |
|---|---|---|
| Permanent Gas `thca=9.0, d9=28.2` | identity 36.1≠25.08, ordering, Δ9>5 | low → flag/fix |
| Lollipopz `d9=29.05` | Δ9>5, ordering | low → flag/fix |
| `Blue Candy Rain` on Lollipopz | name absent from OCR | low → flag |
| `DISEASE. T`, `THIS PRODUCT…`, `High` | name recovered by fixer (`didFix`) | medium → verify |
| Blueberry Caviar (717 chars, `thca=nil`) | thin OCR + missing field | low → flag |

The deterministic guards we shipped this session *fix* most of these; the
confidence layer is the **safety net for the classes we haven't enumerated** —
it flags them instead of silently committing.

## 9. Phasing

- **Phase 1 (cheap, high value):** `ConfidenceScorer` from §3 signals (no model
  call) + per-field UX. Reuses `LabelSanityChecker`, `isAbsentFromOCR`, `didFix`,
  PRE/POST. Ship this first; it would have flagged every row in §8.
- **Phase 2:** gated second-opinion extraction (§5) for `low` scans.
- **Phase 3:** persist confidence on `LogEntry`; Log Book "needs review" filter;
  summary softening.

## 10. Testing

- Unit-test `ConfidenceScorer` with the **exact device OCR fixtures** already in
  `CannabinoidReconcileTests` / `StrainNameFixerTests` — assert each §8 row scores
  `low`/`medium`. Pure function, runs in the simulator (no Vision/FM).
- Extend the offline eval harness (`tests/harness`, see
  [[highnotes-eval-harness]]) to report confidence vs ground-truth: measure
  precision/recall of "low confidence" against actually-wrong fields, and tune
  thresholds there before shipping.
