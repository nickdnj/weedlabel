# Product Requirements Document: HighNotes

**Version:** 1.0
**Last Updated:** 2026-05-27
**Author:** Nick DeMarco with Claude (AI assist)
**Status:** Living — reflects the device-tested v1 spike
**Supersedes:** `docs/legacy/PRD-v0.1.md` (Next.js/Supabase PWA — dead architecture)

> **Naming.** The product is **HighNotes — "Your AI budtender."** The repo and
> Xcode target are still named `weedlabel`; rename is cosmetic and deferred.

---

## 0. Executive summary

HighNotes is a **native iOS app, 100% on-device**, that lets an adult-use
cannabis consumer point their phone at a New Jersey dispensary product label and
instantly get a clear, friendly read on what they're holding: the strain and its
sativa/indica/hybrid character, the standout chemistry when it's legible, and a
short plain-English description — plus the provenance fields (license, Metrc tag,
dates) and any QR/COA link. Nothing leaves the phone except when the user taps an
external link.

The wedge is unchanged from v0.1 in spirit — *remove manual data entry, make the
label in your hand the input* — but the v1 spike reshaped the value proposition
around a hard-won lesson: **photo OCR of fine-print chemistry is unreliable on
real packaging, but the strain name and label markers are reliable.** So
HighNotes leads with confident, name-derived intelligence and treats precise
chemistry as best-effort, clearly flagged when suspect, never fabricated.

There is **no backend, no account, no tracking.** The only monetization is an
optional **tip jar** (built — three StoreKit consumable tiers, reached only from
About; never a paywall, "tip if you can, don't if you can't"); monetized
external links remain a possible-later, not-built option.

---

## 1. Overview

### 1.1 Problem

NJ adult-use products carry rich, regulated labels (cannabinoids %, terpenes,
cultivator, license #, Metrc tag, harvest/expiration, QR/COA). That information
is lost the moment the package goes in a drawer, and it's tedious to read and
interpret in the dispensary or at home. Existing journals make you type it all;
existing catalogs don't know what you actually bought.

### 1.2 Solution

Point, capture, understand:

1. **Capture** — frame the label; the app confirms it's reading a real cannabis
   label (by detecting the expected fields), then takes a sharp high-resolution
   photo.
2. **Extract** — on-device Foundation Models reads the photo's OCR text into a
   structured label (two focused passes: metadata, then chemistry).
3. **Interpret** — derive the strain's sativa/indica/hybrid character, typical
   effect, time-of-day, and flavor from the name + printed marker; generate a
   short informational AI summary grounded only in extracted/known facts.
4. **Correct & explore** — the user can fix the strain classification (it
   persists locally and improves future scans); tap through to the label's
   COA/info link or a producer web search.

### 1.3 Target users

Carried from v0.1 (full detail in `docs/legacy/requirements-discovery-brief.md`):
- **Sara, the Connoisseur** — wants to remember and find good products again.
- **Marcus, the Symptom Tracker** — wants to understand effects (HighNotes stays
  strictly non-medical; see §6 guardrails).
- **Dani, the Value/Trust Shopper** — served by provenance + COA links.

All users 21+. NJ-CRC labels are the v1 target format.

### 1.4 Positioning (load-bearing copy)

- **100% on-device. No accounts. No tracking.**
- The only thing that leaves the phone is when *you* tap an external link.
- Tone: warm, generous, bold-and-playful ("Your AI budtender"). App-Store-safe
  language in shipped strings.

---

## 2. Goals & non-goals

### 2.1 v1 goals
- A scan reliably **confirms a cannabis label is in frame** before capture.
- A scan reliably yields **strain + classification + provenance** (license,
  Metrc, dates, net weight, product type, QR).
- The result screen is **always compelling** — even when chemistry can't be
  read, it leads with name-derived character, never a blank or a fabricated
  number.
- **Never show a number the label didn't print.** Suspect data is flagged;
  invented data is blocked.
- Everything runs **on-device** on Apple-Intelligence-capable hardware.

### 2.2 Non-goals (v1)
- Session/consumption journaling and analytics (v0.1's core; deferred to a later
  HighNotes phase once capture is trustworthy).
- Cloud sync, accounts, social, e-commerce.
- COA *fetching/parsing* (we link out; we don't scrape).
- Any monetization that gates the app (paywalls, subscriptions, ads). The tip
  jar is the lone monetization surface and is purely optional.
- Landscape mode.
- Non-NJ label formats.

---

## 3. Functional requirements

### 3.1 Capture
- **FR-C1** Live camera scan in portrait, with a viewfinder rectangle (framing
  guidance) and a dimmed mask outside it; OCR is constrained to that region.
- **FR-C2** Live **field-detection chips** (License, Metrc, Potency, Terpenes,
  QR) light up as the corresponding signature is read.
- **FR-C3** The shutter is enabled once a quality threshold is met (≥3 of 5
  fields). **Auto-capture** fires after the fields stay detected ~1s; the user
  can tap to capture early.
- **FR-C4** On confirm, capture a **high-resolution still** and OCR that (not the
  live preview frames). Fall back to live OCR if the still capture is
  unavailable.
- **FR-C5** A **preview/confirm** screen shows the captured photo, the detected
  fields, and the OCR text, with **Process** / **Re-scan** actions.

### 3.2 Extraction
- **FR-E1** Two-pass on-device FM extraction: metadata pass + chemistry pass,
  composed into one `CannabisLabel`.
- **FR-E2** Deterministic OCR preprocessing removes known noise (% glyph
  mis-reads, terpene/cannabinoid name OCR errors), strips regulatory boilerplate,
  and de-duplicates lines before extraction.
- **FR-E3** Dates normalized to ISO `YYYY-MM-DD`.
- **FR-E4** Post-extraction fixes correct common model errors (Δ9-THC vs Total
  THC, THCA vs Total THC swaps; strain name that's actually a chemical fragment).

### 3.3 Interpretation
- **FR-I1** Strain classification (sativa / indica / hybrid / hybrid-leaning-
  sativa / hybrid-leaning-indica) resolved by precedence: **user correction >
  printed marker > name lineage**; otherwise "unknown."
- **FR-I2** Each classification carries a factual effect direction, time-of-day,
  and flavor/character note (lineage-specific where known).
- **FR-I3** AI summary: 2–3 sentence, informational, grounded strictly in
  extracted fields + classification; vivid but non-promotional and non-medical.
- **FR-I4** Regulatory derivations: computed Total THC/CBD, chemotype, and the
  NJAC high-potency warning when applicable.

### 3.4 Corrections & persistence
- **FR-P1** The user can set or correct the strain classification from the result
  screen (5-way picker). The correction persists locally and applies to future
  scans of the same strain; it can be removed.

### 3.5 Learn more
- **FR-L1** Surface URL-bearing QR payloads (e.g. COA links) as tappable links.
- **FR-L2** Offer a cultivator web-search link.

### 3.6 Safety & trust (cross-cutting)
- **FR-S1 Hallucination guard** — any percentage the AI summary states must
  appear (±0.5%) in the parsed label; otherwise fall back to a deterministic,
  grounded summary.
- **FR-S2 Sanity checks** — out-of-distribution values (e.g. flower >40% total,
  Total-THC formula mismatch, terpene sum > total) surface as a non-blocking
  "verify against the printed label" banner.
- **FR-S3 P6 content rules** — no medical claims, dosing language, or
  second-person directives in any AI text (regex floor + regeneration; Apple's
  built-in guardrail is an additional ceiling).
- **FR-S4** Never invent a value the label didn't print.

### 3.7 Onboarding
- **FR-O1** A first-run welcome screen states what HighNotes is and its privacy
  promise; persists only a "seen it" flag (`@AppStorage`).

---

## 4. Reliability tiers (what we promise per field)

| Field | Reliability | Notes |
|---|---|---|
| Metrc tag, License #, QR/COA URL, Net weight, Dates, Product type | **High** | Regex / barcode / predictable formats |
| Strain classification (S/I/H) | **High** when the label prints a marker; **Medium** from lineage | User can correct; correction wins |
| Strain name | **Medium** | Post-fix guards against chemical-fragment picks; lot-code confusion is a known gap |
| Cultivator | **Medium** | Occasional brand/strain confusion |
| Individual cannabinoid / terpene % | **Best-effort** | Flagged when suspect; never fabricated |

---

## 5. Success metrics (v1 spike framing)

- **Capture confidence:** ≥90% of in-frame label attempts light ≥3 field chips
  before capture.
- **Compelling result:** 100% of completed scans render a non-empty, non-
  fabricated summary (AI or grounded fallback).
- **Trust:** 0 fabricated percentages reach the user (hallucination guard).
- **Extraction fit:** 0 context-window failures on real NJ-CRC labels (two-pass).
- Engagement/retention metrics from v0.1 re-apply once journaling returns.

---

## 6. Constraints

- **Platform:** iOS 26.0+; Foundation Models requires Apple-Intelligence-capable
  hardware (iPhone 15 Pro / 16 / 17 / M-series iPad). Non-capable devices get
  scan + structured data, no AI summary.
- **On-device only:** no backend, no network calls by the app itself. The sole
  exception is the optional tip jar's StoreKit purchase — Apple-mediated, no
  user data, and only when the user chooses to tip.
- **Distribution:** $99/yr Apple Developer Program (TestFlight + App Store). The
  same paid account is also required to register the tip jar's In-App Purchase
  products before tips work in production.
- **App Store cannabis policy** is a live risk; keep copy informational, non-
  promotional, 21+.

---

## 7. Open product questions

- Strain-name reliability (lot-code confusion) — worth a dedicated heuristic?
- When does session journaling (the v0.1 core) come back?
- Do we add an edible/vape canary to validate non-flower formats (would
  reintroduce some dropped schema fields)?
- COA: link-only forever, or eventually fetch/parse (would dent the on-device
  claim)?
