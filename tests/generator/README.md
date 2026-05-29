# Synthetic label generator

Deterministic NJ-CRC cannabis label generator for stress-testing the HighNotes
extraction pipeline. We author the values, so **ground truth is exact** — no Claude
proxy needed; the harness scores Apple Foundation Models directly against truth.

Spec it implements: [`docs/NJ-CRC-LABEL-SPEC.md`](../../docs/NJ-CRC-LABEL-SPEC.md).

## Generate

```bash
python3 tests/generator/generate.py            # default: seed 42, 12 cases
python3 tests/generator/generate.py --seed 7   # different deterministic draw
python3 tests/generator/generate.py --count 40 # scale up
zsh    tests/generator/render.sh               # HTML -> PNG (image fixtures)
```

Outputs (regenerable, tracked in git):
- `assets/validation/synthetic/<slug>.ocr.txt` — **TEXT level**: OCR-noised text
  (canary-style glyph/typo/scramble noise) fed straight to FM extraction.
- `assets/validation/synthetic/<slug>.html` + `.png` — **IMAGE level**: clean label
  rendered to PNG, run through the full pipeline incl. real Vision OCR.
- `tests/fixtures/ground-truth-synthetic.json` — exact truth, scorer schema, keyed by
  fixture filename. Merged with the hand-authored `ground-truth.json` by `score.py`.

Coverage: flower (normal / >40% high-potency / low-THC-high-CBD), pre-roll, vape
(distillate + live resin), concentrate, edible, tincture, topical. Edibles/tinctures/
topicals are mg-dosed, so their `.ocr.txt` carries mg dosing with **no** percentages —
this tests that the extractor never maps mg into the `%` fields.

## Run the harness against synthetic fixtures (Apple-only)

Needs macOS 26 + Apple-Intelligence hardware (Foundation Models). No API key.

**Build with the Xcode toolchain, not Command Line Tools** — `FoundationModels` only
ships in the Xcode 26 SDK, so plain `swift build`/`swift run` fails with
`no such module 'FoundationModels'` when `xcode-select` points at CLT. Prefix every
command with `DEVELOPER_DIR` (no sudo, no permanent switch):

```bash
cd tests/harness
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift run HighNotesHarness --images ../../assets/validation/synthetic --skip-claude
python3 score.py results/<run>/run.json          # per-field Apple accuracy vs truth
python3 score.py results/<run>/run.json --filter lotcode_trap   # slice ONE trap
python3 score.py results/<run>/run.json --filter .ocr.txt       # text level only
python3 score.py results/<run>/run.json --filter .png           # image level only
```

`--skip-claude` and `.ocr.txt` fixture ingestion were added to the harness for this
(Main.swift). Text fixtures skip Vision OCR; image fixtures (`.png`) run it. The trap
tag in each slug means `--filter <trap>` reports accuracy for just that failure mode.

## Noise model

`apply_noise()` mirrors the deterministic ways Vision mangles real NJ labels (see the
canary `assets/validation/zips-blue-candy-rain.ocr.txt`): `%`→`06`/`96`/`%%`, terpene
typos (`Linaool`, `Lim onene`), `CBD`→`CBO`, key/value line splits, and full reading-order
scramble on potency-bearing types. Tune severity per type in `generate.py` (`level`).
