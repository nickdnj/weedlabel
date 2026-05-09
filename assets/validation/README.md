# Validation Assets

Real NJ-CRC dispensary label images used to validate the OCR + Foundation Models pipeline.

**Intentionally tracked in git** — these are the canary set; reproducibility matters more than repo size. Keep images modest (compress before adding).

## Canonical canary

- `zips-blue-candy-rain.jpeg` — Zips "Blue Candy Rain" 28g flower, Fresh Grow LLC (Somerset NJ, license C000186), harvest 2025-12-10. Tested in conversation 2026-05-09. Parses cleanly: cannabinoids (THCA 29.73%, Δ9-THC 1.45%, CBG 0.49%, total 32.25%), terpenes (5.03% total), full provenance, Metrc tag, two QR codes.

**To do:** drop the actual image file here when you're back at the laptop with it.

## Intent

Each new label form factor (flower, vape, edible, concentrate, pre-roll) gets one canonical canary committed here. The prototype + future regression tests run against this set.
