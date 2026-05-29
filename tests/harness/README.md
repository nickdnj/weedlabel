# HighNotesHarness

Local macOS 26 CLI that runs the HighNotes (weedlabel) AI chain side-by-side
against the Claude API on the fixture cannabis labels, so we can spot Apple
Foundation Models disagreements and use them to refine the on-device prompts —
and, crucially, score BOTH sides against hand-authored ground truth so we don't
optimize on agreement alone.

## What it does

For each image under `assets/validation/` (the default fixture set):

1. **Vision OCR** — `MacImageOCR`, a macOS counterpart of the app's UIKit-bound
   `StaticImageOCR` (same `.accurate` / language-correction / `en-US` config and
   orientation sweep). Runs ImageIO + Vision so no UIKit is dragged in.
2. **Apple Pass A** — calls the production `ExtractionService` on-device. This is
   **TWO Foundation Models passes** over smaller `@Generable` sub-schemas
   (`LabelMetadata`, then `LabelChemistry`), composed into one `CannabisLabel` —
   mirrored exactly, not flattened to one call.
3. **Deterministic post-processing** — `Pipeline.postProcess` runs the SAME
   on-device cleanup the app applies in `ScanModel.runPipeline`: merge QR codes →
   `fixSwappedThcFields` → `StrainNameFixer` → `ProductTypeInference`. Applied to
   **both** the Apple and Claude labels, so the comparison is end-of-pipeline.
4. **Apple Pass B** — calls the production `SummaryService`, running its real P6
   denylist, regenerate-up-to-2x loop, %-hallucination guard, and grounded
   deterministic fallback exactly as the app does. The deterministic strain
   insight (`StrainKnowledgeBase`) is fed into the prompt just like in-app.
5. **Claude Pass A + B** — sends the SAME per-pass `ExtractionService`
   instructions / `SummaryService.systemInstructions` + the byte-identical user
   prompts to Claude. A JSON-schema appendix is appended for each sub-schema
   (since `@Generable` has no Claude analogue). The same P6 denylist AND
   %-hallucination guard are applied to Claude's summary for parity (Claude is
   *flagged*, not mutated — it has no on-device regenerate/fallback loop).
6. **Diff + scoring** — a numeric-tolerance, enum-aware field-by-field diff
   (`Comparator`), per-label `diff.md`, an `index.md` roll-up, a machine-readable
   `run.json`, and a ground-truth `accuracy.md` (via `score.py`).

With `--refine`, a final Claude call ingests the run digest + current
instructions and proposes concrete, quoted prompt edits → `proposed-prompts.md`,
**never auto-applied**.

## Two kinds of measurement (read this)

- **Agreement** (`index.md`, the Comparator) — where Apple and Claude differ. This
  is only a **proxy**. Chasing agreement can pull Apple *toward Claude's errors*.
- **Ground-truth correctness** (`accuracy.md`, `score.py`) — Apple-correct% vs
  Claude-correct% per field against hand-authored `tests/fixtures/ground-truth.json`.
  This is the real target.

### The #1 lesson (paid for in real VinoLabel regressions)

> **Prefer DETERMINISTIC reference/knowledge rules over prompt edits.** Prompt
> edits plateau. **Negative-example banlists REGURGITATE** — listing "do not write
> X" measurably *increases* X. **VALIDATE every proposed edit against the harness
> before adopting** — several of VinoLabel's auto-proposed edits regressed and
> were reverted; the real wins came from deterministic backfill (known category ⇒
> implied field) and recovering a field from OCR when extraction returned null.

The HighNotes deterministic layer that should usually absorb a fix instead of a
prompt edit: `OCRPreprocessor`, `StrainNameFixer`, `ProductTypeInference`,
`CannabisLabel.fixSwappedThcFields`, `StrainKnowledgeBase`. The `--refine` system
prompt is wired to recommend these first.

## Requirements

- **macOS 26** on Apple-Intelligence-capable hardware (M-series). The Foundation
  Models side is skipped per-label if AI is unavailable; `--skip-apple` skips it
  explicitly for a Claude-only sanity run.
- **Full Xcode** (not just Command Line Tools) — invoke via `DEVELOPER_DIR`.
- **`ANTHROPIC_API_KEY`** in the environment.

## Running

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export ANTHROPIC_API_KEY=sk-ant-...
cd tests/harness

# Smoke test (3 labels) — produces per-label diffs + index.md + accuracy.md
swift run HighNotesHarness --limit 3

# Full sweep + prompt-refinement suggestions
swift run HighNotesHarness --refine

# Just the canary
swift run HighNotesHarness --include-pattern zips

# Different Claude model / lower concurrency / Claude-only
swift run HighNotesHarness --model claude-sonnet-4-6
swift run HighNotesHarness --claude-concurrency 2
swift run HighNotesHarness --skip-apple

# Score a finished run against ground truth, and gate a clean subset
python3 score.py results/<run>/run.json
python3 score.py results/<run>/run.json --golden
python3 score.py results/<run>/run.json --filter zips
```

Outputs land in `tests/harness/results/<UTC-timestamp>/`:

```
index.md               roll-up + per-field agreement table (the PROXY)
accuracy.md            Apple-correct% vs Claude-correct% vs ground truth (the TARGET)
run.json               machine-readable summary (score.py + Refiner read this)
proposed-prompts.md    (only with --refine) — NEVER auto-applied
<label-slug>/
  ocr.txt, ocr-cleaned.txt
  apple-passA.json | apple-passA.txt
  claude-passA.json | claude-passA.txt | claude-passA-raw.txt
  insight.json         strain insight + sanity verdict
  apple-passB.txt, claude-passB.txt
  diff.md
```

## Parallelization

Built in three stages so a full run finishes in ≈ Apple-serial time, not the sum:

1. **OCR all labels concurrently** (Vision is local + cheap).
2. **Apple-serial loop ‖ bounded Claude-concurrent group**, started AT THE SAME
   TIME via `async let`. Apple Foundation Models is **strictly serial** (on-device
   sessions don't overlap); everything Claude is network-bound and runs
   concurrently, bounded by `--claude-concurrency` (default 6). Wall-clock ≈
   `max(apple, claude)`. Without this the Claude phase alone is 30+ min; with it
   it collapses to a few minutes and the Apple-serial pass is the floor.
3. **Zip the two halves by index.**

`ClaudeClient` is an `actor` (its `URLSession` awaits interleave → real network
concurrency); all harness result types are `Sendable`.

## Layout & symlink discipline

`Sources/HighNotesHarness/Shared/` is **symlinks** to the app target's
pure-Foundation files — so the harness tests **production code**, not a copy:

```
CannabisLabel.swift        ProductType+Display.swift   LabelSanityChecker.swift
ExtractionService.swift    SummaryService.swift        OCRPreprocessor.swift
StrainKnowledgeBase.swift  StrainNameFixer.swift        ProductTypeInference.swift
AvailabilityGate.swift
```

**Edit the originals in `weedlabel/`, never the symlinks.** The UIKit-bound
`StaticImageOCR` is deliberately NOT symlinked (we use `MacImageOCR` instead).

Two tiny visibility relaxations were made to the originals so the Claude side can
send byte-identical prompts: `ExtractionService.metadataPrompt` /
`.chemistryPrompt` and `SummaryService.buildUserPrompt` are now `internal`
(were `private`).

Harness-only code:
- `Main.swift` — argument parsing + the staged parallel orchestration
- `MacImageOCR.swift` — macOS Vision/ImageIO OCR (counterpart to `StaticImageOCR`)
- `ClaudeClient.swift` — minimal Anthropic Messages client (an actor)
- `ClaudeChain.swift` — the two-pass extraction + summary mirror on the Claude side
- `Pipeline.swift` — the deterministic post-processing mirror of `ScanModel`
- `Comparator.swift` — numeric-tolerance, enum-aware `CannabisLabel` diff
- `Reporter.swift` — per-label artifacts + `index.md` + `run.json`
- `Refiner.swift` — the prompt-refinement meta-prompt (deterministic-first)

`CannabisLabel` is already `Codable` in the app (Log Book persistence), so no
extra Codable shim is needed — the Claude side decodes its two JSON passes into a
merged `CannabisLabel` whose field values match the production
`CannabisLabel(metadata:chemistry:)` composer.

## Ground truth

`tests/fixtures/ground-truth.json` is keyed by fixture **filename** and must be
hand-filled by reading each real label once (the only genuine human step — see
the `_template` blocks). `score.py` skips `_`-prefixed keys, scores only asserted
(present, non-null) fields, and applies the tolerances in `_conventions`
(cannabinoids ±0.5, terpenes ±0.1, productType exact, strainName/cultivator
contains-match, dates ISO-exact). `dominantTerpene` is a truth-only convenience
field scored against whichever terpene the model reports highest.

`golden.json` is the regression gate's clean subset + an `accuracy_floor` (0.75).
**Re-select it from a stable run** once ground truth is filled.

## What differs from VinoHarness

- **Two-pass extraction** (metadata + chemistry sub-schemas) instead of one — both
  the Apple and Claude sides run two passes and compose.
- **No reference dataset** — wine has appellation/varietal/vintage JSON;
  HighNotes' "knowledge" is in-source deterministic code (`StrainKnowledgeBase`
  etc.), so there's no `ReferenceLoader` and the post-processing is `Pipeline`.
- **The %-hallucination guard** — Pass B's safety net is a percentage-grounding
  guard (every "NN%" in the summary must appear in the parsed label ±0.5),
  applied to both sides, plus the P6 medical/dosing denylist.
- **Numeric + terpene fields with tolerances** and an **enum `productType`** —
  the diff and scorer are numeric/enum-aware, not string equality.
- **Filename-keyed, hand-authored ground truth** — no folder-slug truth like wine
  appellations; each cannabis label is read by a human once.
