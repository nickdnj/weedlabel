# NJ-CRC Cannabis Label Specification (for synthetic stress-test generation)

Authoritative reference for what a New Jersey adult-use cannabis label must contain, distilled
for generating synthetic label content to stress-test the HighNotes extraction pipeline.

**Sources**
- **N.J.A.C. 17:30-16.3** — Cannabis item labeling requirements (binding rule). Field
  enumeration and verbatim warnings below come from here.
  <https://www.law.cornell.edu/regulations/new-jersey/N-J-A-C-17-30-16-3>
- **NJ-CRC Packaging and Labeling Guide, Apr 2024** (summarizes 16.2–16.6) — cannabinoid math,
  chemotypes, growth methods, serving caps, expiration. Local copy of the one official example
  label: `assets/validation/web/njcrc-official-gummies-{front,back}.png`.
- Cross-checked against the app contract in `weedlabel/Models/CannabisLabel.swift` and the canary
  OCR fixture `assets/validation/zips-blue-candy-rain.ocr.txt`.

---

## 1. Required label fields (all finished cannabis items) — §16.3(b)

| # | Field | Notes / format | Maps to `CannabisLabel` |
|---|-------|----------------|--------------------------|
| 1 | Producer name, address, **license number**, phone | Cultivator and/or manufacturer | `cultivator`, `licenseNumber` |
| 2 | Net weight & quantity | Inhalables in grams; edibles also mg dosing | `netWeight` |
| 3 | **Production/harvest date** | | `harvestDate` |
| 4 | **Expiration date** | ≤ 6 months from harvest/manufacture (most forms) | `expirationDate` |
| 5 | Sequential serial number, **batch/lot number, barcode** | Metrc tag satisfies this (24 chars, starts `1A4`) | `metrcTag`, `qrCodes` |
| 6 | Inactive/excipient ingredients; food items: ingredients desc. + nutrition | Edibles/ingestibles | — (not modeled) |
| 7 | Allergens & major food allergens | Edibles | — (not modeled) |
| 8 | Storage / refrigeration instructions | | — (not modeled) |
| 9 | **Cannabinoid + terpene profile** (finished items) | mg **and** % ; serving size & total servings | `LabelChemistry.*` |
| 10 | **Strain/cultivar name** (scientific + slang) | | `strainName` |
| 11 | **Chemotype**, growth method, organic status, pesticides | See §3 | (chemotype → inferred; not stored) |
| 12 | **Lab testing summary** — major cannabinoids + terpenoids detected | | `LabelChemistry.*` |
| 13 | Directions for administration | inhalable / ingestible / topical | — |
| 14 | *(optional)* QR/URL to full COA | | `qrCodes` (opaque only) |

`productType` (enum: flower, vape, edible, concentrate, preRoll, tincture, topical, other) is
inferred from dosage form + units, not a printed field.

---

## 2. Verbatim consumer warnings — §16.3(c)

Min **6-point** font unless noted. **All** finished items carry these five:

1. `This product contains cannabis`
2. `This product is intended for use by adults 21 years of age or older and not for resale. Keep out of the reach of children`
3. `There may be health risks associated with the consumption of this product, including for women who are pregnant, breastfeeding, or planning on becoming pregnant`
4. `Do not drive a motor vehicle or operate heavy machinery while using this product`
5. Poison control number — `Poison Control 1-800-222-1222` (per 42 U.S.C. § 300d-71)

Conditional:

- **High potency** (>40% total THC), min 10-pt, on front:
  `This is a high potency product and may increase your risk for psychosis`
- **Ingestible**, min 10-pt, on front:
  `The intoxicating effects of this product may be delayed by two or more hours`
  - fast-acting variant: `The intoxicating effects of this product usually occur in less than 20 minutes but may be delayed by two or more hours`
- **Electronic smoking device (vape):**
  `This device has not been evaluated or approved by the Food and Drug Administration.`
- **Any non-required product claim**, boldface:
  `This statement has not been evaluated by the Food and Drug Administration. This product is not intended to diagnose, treat, cure, or prevent any disease.`

These warnings are realistic label *noise* — the extractor must ignore them. Useful as distractor
text that the FM should NOT pull cannabinoid/strain values from.

---

## 3. Cannabinoid & terpene rules (Packaging Guide pp. 13–15)

**Totals math** (label prints these; extractor copies verbatim, never computes):
- Total THC = (THCA × 0.877) + Δ9-THC
- Total CBD = (CBDA × 0.877) + CBD
- Total CBG = (CBGA × 0.878) + CBG

**Chemotype** (derived from ratio + total THC %):
- `High THC, Low CBD` — THC:CBD > 5:1 **and** total THC ≥ 15%
- `Moderate THC, Moderate CBD` — ratio 5:1…1:5, total THC 5–15%
- `Low THC, High CBD` — ratio < 1:5, total THC ≤ 5%

**Growth methods:** Indoor · Outdoor · Soil-grown · Hydroponic · Aquaponic.

**Realistic value ranges** (for plausible generation; from the canary + typical NJ labels):

| Form factor | Total THC / cannab. | THCA | Δ9-THC | CBG | CBD | Total terpenes | Net weight | Dosing |
|-------------|--------------------|------|--------|-----|-----|----------------|-----------|--------|
| Flower / pre-roll | 13–32% | 15–35% | 0.3–2% | 0.1–1.5% | 0–1% | 0.5–6% | 1g, 3.5g, 7g, 14g, 28g | — |
| Vape cart | 60–90% | 0–85%* | 0–80%* | 0–3% | 0–3% | 1–12% | 0.3g, 0.5g, 1g | mg sometimes |
| Concentrate (rosin/badder) | 60–90% | 50–90% | 0.5–5% | 0–3% | 0–3% | 1–15% | 0.5g, 1g | — |
| Edible | mg-based | — | — | — | — | — | net wt of food | ≤10mg/serving, ≤100mg/pkg |
| Tincture | mg/mL | — | — | — | — | — | mL | per-mL mg |

\* distillate carts often report mostly Δ9/total-THC with little THCA; live-resin carts retain THCA.

Individual terpenes typically reported: myrcene, limonene, linalool, β-caryophyllene, α/β-pinene,
humulene, terpinolene, bisabolol, caryophyllene oxide, ocimene, nerolidol. Each 0.02–2.5%; the
six named in the schema (myrcene, limonene, linalool, betaCaryophyllene, pinene, humulene) are the
high-value slots.

---

## 4. Identifier formats (for plausible synthetic provenance)

- **License #:** letter + 6 digits, e.g. `C000186` (cultivator), also `RE…`, `MA…` classes.
- **Metrc tag:** 24 alphanumerics, starts `1A4`, e.g. `1A4110300003C8D000041730`.
- **Permit number** (PDF example): `0123ABC345`.
- **Dates:** label prints US `MM/DD/YYYY`; schema normalizes to ISO `YYYY-MM-DD`.
- **Lot/batch:** free-form, e.g. `PHCSTP-045678`, `9 - 120925 - <strain>`.

---

## 5. OCR-noise model (what makes a fixture *realistic*)

The canary fixture shows NJ-CRC OCR is structured colon:value text that Vision mangles
deterministically. A generator that only emits clean text under-tests the extractor. Inject:

- **`%` glyph corruption:** `%` → `06`, `96`, `00`, `9%`, `%%`, `O/o`, `0/0`.
- **Digit/letter swaps:** `THC9:` for `THC%`, `Betainene` for `BetaPinene`, `Linaool` for
  `Linalool`, `Lim onene` (space-split), `CBO`/`CBOA` for `CBD`/`CBDA`.
- **Line scrambling:** Vision returns fragments out of reading order — label key and value land
  on non-adjacent lines (see canary: `THCA: 29.73 00` far from `Potency Analysis:`).
- **Strain-name wrapping:** name split across lines (`Zips - Blue Candy` / `Rain - 28g`).
- **Lot-code-as-noise:** a bare 24-char Metrc tag on line 1 (FM has mis-grabbed this as THCA).
- **Decoy numbers:** phone `(973) 400-0188`, ZIP `08873`, address `15 World's Fair Drive`.

Known extractor failure modes these target (see `tests/fixtures/ground-truth.json` history):
strain-name reassembly, Total-THC vs Δ9 vs THCA confusion, myrcene/limonene transposition,
product-type misclassification, lot-code → THCA.

---

## 6. What "generate label content" should produce

Two fixture levels, both feedable to `tests/harness/`:

1. **Clean structured label text** → render to PNG (full pipeline incl. Vision OCR) *or* hand to
   the harness as ground truth. Tests the happy path across product types.
2. **OCR-noised text fixtures** (`<slug>.ocr.txt` + `ground-truth.json` entry) → bypass image
   OCR, stress just the FM extraction against §5 noise. Highest signal per token; mirrors the
   existing `zips-blue-candy-rain.ocr.txt` + ground-truth pattern.

Each generated case = (clean ground-truth `CannabisLabel` JSON) + (noised OCR text). The harness
already scores extraction against ground truth with numeric tolerances (cannab. ±0.5, terp. ±0.1).
