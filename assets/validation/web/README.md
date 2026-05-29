# Web-sourced validation labels

Real NJ cannabis labels gathered from the public web (2026-05-28) to widen the OCR +
Foundation Models test set beyond the device photos in the parent directory. Kept separate
because these are third-party images, not our own captures — attribution below.

## Strongest OCR inputs (full structured compliance text)

| File | What it is | Form factor | Source |
|------|-----------|-------------|--------|
| `njcrc-official-gummies-back.png` | Official NJ-CRC example back label: Active/Other Ingredients, full warning block, "Made by: Cannabis Farms", Permit 0123ABC345, Manufactured 05/12/23, Beyond Use Date 11/12/23, Lot PHCSTP-045678, barcode, NOT SAFE FOR KIDS symbol. Clean mockup — happy-path parser input. | Edible | nj.gov NJCRC Packaging & Labeling Guide (Apr 2024), p.1 |
| `njcrc-official-gummies-front.png` | Matching front: "Cannabis-Infused Gummies", Cannabis Sativa "Lamb's Bread", 100mg THC / 10mg per serving / 10 servings, Net Wt 28.35g. | Edible | same PDF |
| `panda-farms-flower-tin-preroll.jpg` | **Real photo.** Panda Farms flower jar + pre-roll tubes + 14g tin showing the full NJ compliance warning panel (NJ Medical Cannabis Program, Poison Control 800-222-1222, FDA disclaimer, NOT SAFE FOR KIDS). | Flower / pre-roll | headynj.com |

## Supplementary real product photos (front/brand-forward; partial compliance text)

| File | What it is | Form factor | Source |
|------|-----------|-------------|--------|
| `thc-seltzers-4pack.jpg` | WYNK, Mystic Orbit, CANN, Cornbread cans — front THC mg panels + universal symbol. | Beverage | headynj.com |
| `precious-prerolls-boxes.jpg` | Precious "Prime" pre-roll boxes; side panel reads THREE PRE-ROLLS / CANNABIS FLOWER / NET WEIGHT 2G. High-res (3391×4239). | Pre-roll | headynj.com |
| `jersey-strong-prerolls-jars.jpg` | Jersey Strong jars + pre-roll tubes (single / 2-pack), brand fronts + net-weight text. | Flower / pre-roll | headynj.com |
| `flower-union-gummy-nj-symbol.jpg` | Macro of a gummy with the NJ universal cannabis symbol embossed — exercises the Vision symbol-detection path, not OCR. | Edible | headynj.com |

## Why so few

The open web is hostile to this search: Google Images → CAPTCHA, Bing → SafeSearch filters
cannabis to junk, DuckDuckGo → anomaly block, Reddit (the richest source of real back-label
photos) → hard 403. "How to read a label" blogs serve AI-generated mockups with garbled
placeholder text (useless for OCR). The reachable real-photo source (Heady NJ) photographs
products brand-front, so legible full compliance panels are rare. See the
`nj-label-image-sources` memory for the working recipe. For more real labels, the highest-yield
path remains user-captured photos like the `IMG_07xx` set in the parent directory.
