# NJ Weed Label Reader and Reporter — Discovery Brief

**Document type:** Pre-PRD discovery
**Date:** 2026-05-05
**Author:** Product Requirements specialist (research pass, not full PRD)
**Status:** Draft for stakeholder review

---

## 0. One-paragraph summary

A consumer mobile app for New Jersey adult-use cannabis customers that turns a photographed dispensary label into structured, queryable data (cannabinoids, terpene profile, cultivator, Metrc tag, dates), then layers a personal consumption journal on top so users can learn what works for them over time. There is a real white-space here: existing journal apps (Strainprint, Releaf, Jointly) require manual data entry and existing catalog apps (Leafly, Weedmaps, Hytiva) don't ingest your actual purchase. Combining label OCR + journaling + NJ-specific compliance context appears to be unoccupied. Two material constraints will shape MVP: (1) Apple permits cannabis apps if geo-restricted to legal jurisdictions and age-gated, but Google Play prohibits anything that looks like facilitating sale, so the app must be informational/journaling only on Android; (2) Metrc Retail ID QR codes are now live across NJ dispensaries, which gives us an authoritative data source and changes the OCR-vs-QR architecture decision.

---

## 1. NJ regulatory landscape

### 1.1 Mandated label fields (NJAC 17:30-16.2 through 16.6)

Per the NJ-CRC Packaging and Labeling Guide and N.J.A.C. 17:30-16.3, labels for adult-use flower must carry:

- **Licensee identity** — name, address, license number of the cultivator/manufacturer/packager (your sample shows "Fresh Grow LLC, Somerset NJ, License C000186")
- **Product identity** — product type, strain name, category
- **Net weight** in metric and U.S. customary units
- **Cannabinoid content** — Total THC (delta-9-THC + THCA), Total CBD, other identified cannabinoids; expressed as mg/serving, mg/package, AND percentage
- **Chemotype banding** for flower — high/moderate/low THC and high/moderate/low CBD
- **Ingredient list** in descending predominance (manufactured/infused only)
- **Allergen declarations** (manufactured/infused only)
- **Servings per package** (multi-serving products)
- **Batch number, harvest date, expiration date, test results reference**
- **Universal NJ cannabis symbol** (red/yellow/black, on white or light background, on every package and ideally every serving)
- **Government health warnings** — do not drive/operate machinery, pregnancy/breastfeeding caution, mental-health risk for high-potency, keep away from children
- **Metrc package tag** (your sample: `1A4110300008C8D000041730`) and increasingly a **Metrc Retail ID QR code** linking to authoritative cannabinoid/terpene/COA/recall data

### 1.2 Universal symbol

NJ-CRC publishes the symbol with strict color specs (CMYK red C15/M99/Y93/K5; yellow C1/M19/Y99/K0; black) on white/light background. Detecting this symbol in a label image is a useful "is this a NJ cannabis label?" gate for the app.

### 1.3 Metrc Retail ID — the inflection point

Metrc Retail ID went live in NJ in 2024 and is one of the four launch states (alongside MD, MI, MS). It produces serialized per-item QR codes that resolve to authoritative product data — origin, potency, terpenes, COA, recall status. This materially changes our architecture: **for newer products, scan the QR; for older or partial labels, fall back to OCR/vision.** It also gives us a way to *verify* what OCR extracts against the source-of-truth, which is the foundation of the "Reporter" use case.

### 1.4 Consumer-protection complaint channel

Mislabeling complaints go to `crc.compliance@crc.nj.gov` (Office of Compliance and Investigations). N.J.A.C. 17:30-9.16 codifies the cannabis business complaint process. The CRC has acknowledged real labeling-variance problems — independent testing has found pre-rolls where actual THC was roughly half of labeled THC. There is a genuine consumer-protection gap our app could help close.

### 1.5 Restrictions on consumer apps

I found no NJ-specific rule prohibiting a third-party app that *catalogs purchases* (as opposed to facilitating sale). Age verification is expected industry practice (21+) and aligns with platform store requirements. Geo-restriction to NJ is necessary for Apple compliance.

---

## 2. Competitor / adjacent apps

| App | Category | What it does well | Gap vs. our concept |
|---|---|---|---|
| **Strainprint** | Consumption journal | Symptom tracking, dosage logging, points/rewards. Strong medical patient base. | All entry is manual. No label ingest. Generic strain DB, not NJ-specific. |
| **Releaf** | Consumption journal | Most detailed strain entry on the market — grower, harvest date, batch, eight cannabinoids, dozen-plus terpenes. Real-time session tracking. | Still all manual entry. Closest to our data model but slowest to onboard a new product. |
| **Jointly** | Goals-based wellness journal | Maps consumption to wellness goals (sleep, stress, focus). Good UX for casual users. | No label ingest. Less detail per entry. |
| **Leafly** | Catalog + dispensary finder | 5,000+ strains, 1.3M reviews, dispensary discovery, in-app ordering in some markets. | Discovery, not personal history. Doesn't know what *you* bought. |
| **Weedmaps** | Catalog + marketplace | Strain DB, deal/menu discovery, education content. | Same gap — discovery, not personal record. |
| **Hytiva** | Catalog + dispensary finder | Strain database with effects/flavors. | Less prominent than Leafly/Weedmaps. Same discovery gap. |
| **Label-OCR apps** | (sought) | — | I could not find a consumer app whose primary input is photographing a dispensary label. Producer/retailer barcode tools exist (Orca Scan, Flourish), but nothing consumer-facing. |

### White-space analysis

The unmet job is **"the label in my hand is the input."** Today a NJ consumer who wants to remember "I liked the Blueberry Caviar from Fresh Grow because it had high myrcene and 27% THC" must either type all that into Releaf manually, photograph the label and dig later, or just forget. Our MVP wedge is making that capture frictionless — point camera, get a structured record. Combined with NJ-specific compliance context (Metrc lookup, label-vs-actual reconciliation) and personal pattern detection, this is a defensible position.

---

## 3. User personas and jobs-to-be-done

### Persona A — "Sara, the Connoisseur" (recreational, 28-45)

Buys flower 1-3x/month from 2-3 NJ dispensaries. Cares about terpene profile, cultivar, sometimes cultivator. Already comparing notes mentally.

- **JTBD:** When I find a strain I love, help me remember exactly what made it good so I can find it (or something similar) next time.
- **Jobs:** Capture purchase, tag with subjective rating + effect notes, get recommendations like "you've rated 4 high-myrcene strains 8+/10."

### Persona B — "Marcus, the Symptom Tracker" (medical-leaning, 35-65)

Uses cannabis for sleep, anxiety, or chronic pain. Wants evidence about what actually works. May have come from the legacy NJ medical program.

- **JTBD:** Help me figure out which products actually relieve my symptoms so I'm not guessing or overspending.
- **Jobs:** Capture purchase, log session with symptom-relief score, surface correlations (CBN content vs. sleep score, etc.), exportable history for my doctor.

### Persona C — "Dani, the Value/Trust Shopper" (recreational, 21-35, budget-conscious)

Comparison-shops aggressively. Suspicious of inflated potency claims. Reads about NJ recalls.

- **JTBD:** Help me get the most cannabinoid for my dollar and avoid products that don't deliver what's on the label.
- **Jobs:** Compute $/mg-THC across purchases and dispensaries, flag this product on a recall list, alert me if independent testing shows my batch was mislabeled.

(Personas A and B are the strongest MVP targets. Persona C unlocks the "Reporter" angle and is a v1.5 priority.)

---

## 4. Interpreting "Reporter"

The product name carries three plausible meanings. Pick one to lead with for MVP and treat the others as adjacent:

| Interpretation | Description | MVP fit |
|---|---|---|
| **Personal reports** | "Your top cultivators this quarter," "your average THC %," symptom-trend reports for a doctor | Strong. Natural extension of the journal. Low regulatory risk. |
| **Consumer-protection reporting** | Flag mislabeled/expired/recalled products to NJ-CRC; community-sourced label-vs-COA discrepancy database | Strong story, real CRC need (per NJBIZ reporting on labeling failures), but heavier to build and politically sensitive. Better as a v1.5 differentiator. |
| **Social sharing / reviews** | Post your journal entries publicly à la Untappd or Vivino | Risky on Apple (app-store reviews of controlled substances), commoditized by Leafly/Weedmaps. Skip for MVP. |

**Recommendation:** Lead MVP messaging with **Personal Reports** ("know what works for you"). Tease **Consumer-Protection Reporting** as a v1.5 capability ("we'll help you spot bad labels"). Defer social.

---

## 5. MVP feature set

### P0 — Must ship (5-7 features)

1. **Label capture** — Camera flow: take 1-3 photos of a NJ adult-use label. Detects the NJ universal cannabis symbol as a sanity check.
2. **Hybrid extraction** — If a Metrc Retail ID QR code is present, scan it as primary source of truth. Otherwise, use vision/LLM OCR to extract structured fields (cannabinoids, terpenes, cultivator, license #, dates, Metrc tag, weight). Always show the user the parsed fields with a "fix this" affordance before saving.
3. **Product library** — Each captured label becomes a Product record. De-duplicate across multiple purchases of the same SKU/batch.
4. **Consumption log** — Log a session against a Product: timestamp, amount (rough), method (flower/vape/etc.), 1-10 effect rating, free-text notes, optional structured tags (sleep, focus, pain-relief, anxiety).
5. **Personal reports** — At least three: "Your top strains," "Your terpene preferences" (correlate high-rated sessions with terpene composition), "Potency over time" (THC% trend).
6. **Age-gate + NJ geo-restriction** — 21+ confirmation on first launch; geo-fence to NJ for app-store compliance.
7. **Local-first data with optional encrypted cloud backup** — Treat consumption data as sensitive PII; default storage on-device.

### P1 — v1.5 (5-ish)

1. **Recall and labeling-discrepancy alerts** — Cross-reference saved Metrc tags against CRC recall feeds and surface alerts: "Your Blue Candy Rain batch was recalled."
2. **Consumer-protection report flow** — One-tap "report this label to NJ-CRC" that generates a pre-filled email to `crc.compliance@crc.nj.gov` with photos and structured findings.
3. **$/mg-THC analytics** — Cost tracking across dispensaries and cultivators.
4. **Doctor/caregiver export** — PDF or CSV of your symptom-tracking history.
5. **Cultivator/strain profile pages** — Aggregate your own history per cultivator and strain ("you've bought from Fresh Grow 6 times, average rating 7.8").

### Explicitly out of scope for MVP

- Buying or reserving product (Google Play prohibition, Apple complexity)
- Public reviews / social feed
- Multi-state expansion
- Edibles/concentrate-specific data models (start with flower since the sample is flower; expand based on demand)

---

## 6. Open questions for the user

1. **Target market size and geography** — NJ-only at launch, or design for multi-state from day one (CO, MA, NY have similar Metrc and labeling regimes)? NJ-only is simpler and lets us own a niche; multi-state needs a pluggable rules engine.
2. **Mobile platforms** — iOS-first (where cannabis apps are explicitly allowed), Android-after (with feature limits to satisfy Google Play), or web app to sidestep store rules entirely? My lean: iOS-first native, web companion for reports.
3. **Monetization** — Free with optional pro tier? Affiliate revenue from dispensary referrals (raises Apple/Google scrutiny)? Anonymous-aggregate-data sales to cultivators (raises trust scrutiny)? Paid one-time purchase?
4. **Data privacy posture** — How aggressive on privacy? Local-only with no account (most defensible, hardest to monetize), or account + encrypted cloud + explicit opt-in for any analytics?
5. **"Reporter" ambition** — Is the v1.5 consumer-protection reporting flow important to you personally, or is this purely a personal-journal product? This decides whether we invest in a CRC-relations posture early.
6. **Vision/OCR architecture** — Comfortable with on-device Apple Vision + a cloud LLM fallback (cheap, fast, but cloud-dependent for hard labels), or strict on-device only (privacy story, more engineering)?
7. **Social features** — Hard "no social" to keep app-store risk low, or share-to-friend allowed (DM-style, not public feed)?
8. **Build vs. buy on the strain DB** — Use Leafly's API where available, license a strain DB, or build a thin custom DB seeded by user captures?

---

## 7. Risks and non-obvious concerns

- **Apple App Store** — Cannabis apps are permitted since June 2021 *if* geo-restricted to legal jurisdictions and they don't facilitate sale outside licensed dispensaries. A pure label-reader/journal is well within bounds, but reviewer interpretation can be uneven; expect 1-2 review cycles. A strong age-gate and NJ-geofence on first launch is non-negotiable.
- **Google Play** — Stricter. Effective April 15, 2026 the Developer Program Policies still ban apps that "facilitate the sale of marijuana." A journaling/reader app should be fine, but any feature that resembles ordering, in-app shopping cart, or delivery scheduling will trigger removal. Plan to ship Android with reduced feature surface or skip Android initially.
- **Texas App Store Accountability Act (Jan 1, 2026)** — Sets precedent for state-level age-verification mandates on app stores. NJ may follow. Bake in robust age-verification rather than checkbox-style.
- **OCR accuracy and liability** — If we extract the wrong THC % and a user makes a dosing decision based on it, that's a real harm vector. Always show the user the parsed fields with edit affordance before saving; never quietly substitute extracted data for what the label says.
- **Health-claim risk** — Pattern-detection that says "myrcene helps your sleep" can be read as a medical claim. Use careful language ("you rated sessions with this product higher for sleep") and disclaim.
- **Data sensitivity** — Cannabis consumption history is sensitive even where legal (employment, custody, federal travel implications). Local-first storage + explicit, granular cloud opt-in. Avoid third-party analytics SDKs that ship usage data off-device.
- **Cultivator/dispensary pushback** — If the app exposes label-vs-COA discrepancies publicly, expect legal pressure. Keep discrepancy data private to the user and route formal complaints through the CRC channel rather than publishing.
- **Metrc dependency** — Retail ID QR is the cleanest data source but Metrc has no public consumer API. We'd be scanning QR codes that resolve via Metrc's web URLs; durability of that approach is a question for the architecture phase.
- **Strain-name ambiguity** — "Blueberry Caviar" from one cultivator is genetically different from another's. De-dup logic must key on cultivator + strain + batch, not strain name alone.

---

## Sources

- [NJ-CRC Packaging and Labeling Guide for Adult-Use (2024)](https://www.nj.gov/cannabis/documents/businesses/Business%20Resources/NJCRC_Packaging_Labeling_Guide2024.pdf)
- [N.J.A.C. 17:30-16.3 — Cannabis item labeling requirements](https://www.law.cornell.edu/regulations/new-jersey/N-J-A-C-17-30-16-3)
- [N.J.A.C. Title 17, Ch. 30 — Personal Use Cannabis Rules](https://www.law.cornell.edu/regulations/new-jersey/title-17/chapter-30)
- [N.J.A.C. 17:30-9.16 — Cannabis business complaint process](https://www.law.cornell.edu/regulations/new-jersey/N-J-A-C-17-30-9-16)
- [NJ Cannabis Universal Symbol Standards](https://www.nj.gov/cannabis/assets/images/universal-symbol/NJ_Cannabis_Universal_Symbol_Standards.pdf)
- [NJ-CRC Packaging and Labeling Guide Addendum 02-25](https://www.nj.gov/cannabis/documents/businesses/Business%20Resources/NJ-CRC%20Packaging%20and%20Labeling%20Guide%20Addendum%2002-25.pdf)
- [NJ-CRC Contact / Compliance](https://www.nj.gov/cannabis/about/contact-us/)
- [NJBIZ — Mold, pathogens, mislabeling: NJ cannabis products fail safety tests](https://njbiz.com/mold-pathogens-mislabeling-nj-cannabis-products-fail-safety-tests/)
- [Metrc — New Jersey partner page](https://www.metrc.com/partner/new-jersey/)
- [Metrc Retail ID launch announcement](https://www.metrc.com/news/metrc-revolutionizes-cannabis-supply-chain-with-launch-of-metrc-retail-id/)
- [Metrc Retail ID — 1M weekly QR codes across 21 markets](https://www.metrc.com/news/metrc-retail-id-achieves-1-million-weekly-run-rate-of-qr-codes-across-21-markets-an-unprecedented-pace-for-cannabis-supply-chain-technology/)
- [Strainprint app](https://strainprint.ca/app/)
- [High Times — Strainprint vs. Releaf](https://hightimes.com/products/strainprint-app-can-actually-help-you-find-your-perfect-strain/)
- [PotNetwork — Which app will help you find the best cannabis high (Strainprint/Releaf detail)](https://www.potnetwork.com/news/which-app-will-help-you-find-best-cannabis-high)
- [CBD Oracle — 16 Best Cannabis Apps 2026](https://cbdoracle.com/lifestyle/cannabis-apps/)
- [Leafly](https://www.leafly.com/)
- [Weedmaps — Strains](https://weedmaps.com/strains)
- [Marijuana Moment — Apple now allows marijuana businesses on App Store, Google maintains ban](https://www.marijuanamoment.net/apple-now-allows-marijuana-businesses-on-its-app-store-while-google-maintains-ban/)
- [MJBizDaily — Apple's new cannabis app rules; Google a holdout](https://mjbizdaily.com/apples-new-cannabis-app-rules-benefit-marijuana-businesses-but-google-a-holdout/)
- [Google Play Developer Program Policy](https://support.google.com/googleplay/android-developer/answer/16933379?hl=en)
- [Cannabis Regulations AI — Texas App Store Accountability Act, Jan 1 2026](https://www.cannabisregulations.ai/cannabis-and-hemp-regulations-compliance-ai-blog/texas-app-store-age-verification-cannabis-2026)
- [Budpedia — Smart cannabis packaging: QR & NFC traceability](https://www.budpedia.com/articles/smart-cannabis-packaging-qr-nfc-traceability)
