# Product Requirements Document: NJ Weed Label Reader and Reporter

**Version:** 0.1
**Last Updated:** 2026-05-05
**Author:** Nick D. with Product Requirements specialist (AI assist)
**Status:** Draft for review

---

## 0. Executive summary

A NJ-only Progressive Web App (PWA) where adult-use cannabis customers photograph the label on a product they bought, the app extracts structured fields via Claude Sonnet 4.6 vision, and the user logs detailed sessions against that product. The result is a personal consumption journal with analytics — what worked, what didn't, which terpenes correlate with which effects, how tolerance is shifting over time. This is a **personal product**: no social feed, no e-commerce, no regulatory reporting at launch.

The MVP wedge is removing manual data entry from cannabis journaling. Existing journals (Strainprint, Releaf, Jointly) require typing every cannabinoid, terpene, cultivator, and date. Existing catalogs (Leafly, Weedmaps) don't know what you bought. We win by making the label in your hand the input.

---

## 1. Overview

### 1.1 Purpose

NJ adult-use cannabis customers buy products with rich, regulated labels (cannabinoids %, terpenes, cultivator, batch, harvest date, Metrc tag) and immediately lose all of that information once the package goes in a drawer. They cannot learn from their own consumption because the data is fragmented across packaging, memory, and rough impressions.

This product solves that by:

1. **Capturing** the label as a structured Product record with one photo (or two — front + back).
2. **Logging** detailed consumption sessions against that Product — dose, method, onset, peak, effects, mood, context.
3. **Surfacing** patterns the user could not detect by memory: terpene-effect correlations, strain history, tolerance trends, "what worked when I had trouble sleeping."

### 1.2 Target users

**Primary — Persona A: "Sara, the Connoisseur."** Recreational user, 28–45, NJ resident, buys flower or vape 1–3x/month from 2–3 dispensaries. Already mentally comparing strains. Wants to remember which products were great so she can find them (or terpene-similar ones) again.

**Primary — Persona B: "Marcus, the Symptom Tracker."** Medical-leaning user, 35–65, often a former NJ medical-program patient. Uses cannabis for sleep, anxiety, or chronic pain. Wants evidence about what actually relieves symptoms; tired of guessing.

**Secondary — Persona C: "Dani, the Value/Trust Shopper."** Recreational, 21–35, comparison-shops, suspicious of inflated potency claims. Will be served better by v1.5 features ($/mg-THC, recall alerts, label-vs-COA reconciliation). Not the MVP target but the data model should not preclude her.

All users must be 21+ and physically in NJ at first launch (geo-soft-check; see §3.1).

See discovery brief §3 for full persona detail.

### 1.3 Success metrics

**Activation (P0 measure of "the wedge works"):**
- ≥70% of users who complete onboarding successfully scan and save at least one Product within 5 minutes of finishing the age gate.
- ≥80% of label scans produce a Product record the user accepts without manual edits to cannabinoid % or strain name.

**Engagement (P0 measure of "the journal is sticky"):**
- ≥40% of users who save a Product log at least one session against it within 7 days.
- ≥25% of MAU log ≥3 sessions per month (recurring journaling, not one-time curiosity).

**Quality:**
- Label parse success rate (structured JSON returned, no LLM error) ≥95%.
- Median user-reported correction count per scan ≤1 field.

**Retention (lagging):**
- D30 retention ≥25% of activated users.
- ≥30% of users return to view their analytics dashboard at least once in their second month.

**Explicitly NOT tracked at MVP:** revenue, social shares, ad impressions. Free product.

---

## 2. Scope

### 2.1 In scope (MVP / P0)

- NJ-only adult-use cannabis labels (flower, pre-roll, vape, edible, concentrate — all categories supported by parse)
- PWA on iOS Safari, Android Chrome, desktop browsers (installable to home screen)
- Account creation with email + password (or magic link), 21+ self-attestation
- Camera capture and photo upload of labels
- Claude Sonnet 4.6 vision parse to structured JSON with per-field confidence scoring
- Manual correction UI for any parsed field
- Product library (deduplicated by Metrc package tag when present, by cultivator + strain + batch otherwise)
- Session logging with two modes: **Quick log** (≤4 taps) and **Detailed log** (full session form)
- Personal analytics dashboard
- NJ-CRC license number validation against a seeded license table (sanity check the cultivator/manufacturer license on the label is real and active)
- QR-based COA fetch — if the label has a QR code resolving to a COA URL, store the URL and cache the PDF
- Search/filter own product + session history
- Cloud sync (Supabase, encrypted at rest), required for cross-device + iOS PWA storage eviction resilience
- Data export (JSON + CSV) and account deletion

### 2.2 Out of scope (MVP)

- **Social features** — no public reviews, no friend feed, no shared journals
- **E-commerce** — no ordering, no reservation, no shopping cart, no dispensary deals
- **Consumer-protection regulatory reporting** — no flagging bad labels to NJ-CRC at MVP (deferred to v1.5)
- **Multi-state** — no CO/MA/NY/CA support; rules engine kept NJ-specific
- **Native iOS or Android apps** — PWA only; no App Store or Play Store submission
- **Doctor / caregiver share** — no provider portal, no PDF clinical export (v1.5)
- **In-app strain encyclopedia** — we surface only what the user has personally logged plus public terpene/cannabinoid names; no licensed Leafly/Weedmaps strain DB
- **Recall alerts** — deferred to v1.5
- **Monetization** — free at launch; no ads, no subscriptions, no affiliate links
- **Push notifications** — out of scope for MVP (PWA push is partially supported on iOS but adds complexity; revisit P1)

### 2.3 Constraints

- **Tech stack** locked to Next.js (PWA) + Supabase + Anthropic API per Architecture brief.
- **Privacy posture** is non-negotiable: cloud sync is required (iOS evicts PWA storage after ~7 weeks idle) and all consumption data must be encrypted at rest, auth-gated, and excluded from any third-party analytics SDK.
- **No native app stores** at MVP, which sidesteps Apple/Google cannabis policy review entirely but means we lose push, deep camera APIs, and discoverability via stores.
- **No Metrc public API** — Retail ID QR codes resolve through Metrc URLs but there is no consumer API; we cannot programmatically pull authoritative product data, only opportunistically scrape on user-presented QR.
- **No existing NJ cannabis license dataset** with API access — license seed table must be assembled manually (NJ-CRC website scrape, OPRA request) and refreshed periodically.
- **Single developer** — solo build. Scope must reflect that.

---

## 3. Functional requirements

### 3.1 Onboarding and age gate

#### User story
As a first-time visitor, I want to confirm I'm 21+ and a NJ resident so I can use the app while staying compliant with NJ adult-use law.

#### Acceptance criteria
- [ ] First-launch screen presents the value prop in one sentence and a single primary CTA.
- [ ] Age-gate screen requires user to enter date of birth (date picker, not just "I am 21+" checkbox) and computes 21+.
- [ ] If <21, a polite refusal screen is shown with no path forward; date of birth is **not** persisted.
- [ ] NJ residency is captured by a self-attestation checkbox plus a non-blocking soft geo-check (browser geolocation if granted; IP-based fallback). A user outside NJ sees a "this app is intended for NJ adult-use customers" notice but is not hard-blocked (consistent with discovery brief §1.5 — NJ has no rule against out-of-state use of an informational app, and the user may be traveling).
- [ ] Account creation: email + password OR magic-link email. No social login at MVP (cannabis-data sensitivity).
- [ ] Onboarding ends with a 3-card explainer: (1) Scan a label, (2) Log a session, (3) See what works for you. User can skip.
- [ ] PWA install prompt is shown on supported browsers after first successful Product scan, not on first launch (avoids dismissal before value is demonstrated).

#### Business rules
- Age check uses computed age at "today" against DOB; no rolling 21st-birthday recomputation.
- Self-attestation language: "I confirm I am 21 or older and I am in New Jersey."
- DOB is stored hashed for re-verification only; not used for analytics or marketing.

#### User flow
1. Visitor lands on `/` → marketing splash + "Get started" CTA.
2. Date-of-birth entry → if <21, dead end; else continue.
3. Account creation (email + password or magic link).
4. Email verification (magic link) before any data is saved.
5. NJ self-attestation + optional geo permission.
6. 3-card explainer → Home (empty state with "Scan your first label" CTA).

---

### 3.2 Label capture (camera + photo upload)

#### User story
As a user holding a NJ cannabis package, I want to take 1–2 photos of the label and have the app start parsing immediately, so I can capture a product record in under 30 seconds.

#### Acceptance criteria
- [ ] "Scan a label" CTA opens the device camera via `getUserMedia` with rear camera preferred.
- [ ] Camera UI shows a framing guide (rounded rectangle outline) and a "Capture" button.
- [ ] User can capture up to 3 photos in one session (typical: front + back; some labels need a third for the COA QR code).
- [ ] User can upload from photo library as alternative (`<input type="file" accept="image/*" capture="environment">`).
- [ ] Each captured image is shown as a thumbnail; user can delete and retake before submitting.
- [ ] On submit, images are uploaded to Supabase Storage in a per-user encrypted bucket.
- [ ] If browser does not support `getUserMedia`, fall back to file upload only (no camera button shown).
- [ ] If user grants camera permission then denies, surface a "Camera access blocked — tap here to upload from photos instead" affordance.
- [ ] Image is auto-rotated to upright orientation based on EXIF before upload.
- [ ] Image max dimension 2048px (downscale client-side) to control upload size and LLM cost.

#### User flow
1. Home → "Scan a label" → camera opens.
2. User frames front of label, taps capture → thumbnail appears.
3. User flips package, captures back → second thumbnail.
4. (Optional) User captures COA QR code → third thumbnail.
5. User taps "Parse label" → upload + transition to parse-loading screen.

#### Edge cases
- Low light: surface a "tap to enable flash" toggle if `MediaTrackCapabilities.torch` is supported.
- Blurry photo: no client-side blur detection at MVP; we rely on Claude vision to flag low-confidence parses.
- Wrong product type (user photographs something that isn't a NJ cannabis label): handled at parse step (§3.3) — Claude returns `is_nj_cannabis_label: false` and we show a "this doesn't look like a NJ cannabis label" screen.

---

### 3.3 Label parsing (LLM vision → structured JSON)

#### User story
As a user who just submitted label photos, I want the app to extract every meaningful field into a structured form within 10 seconds, with clear indication of which fields it's confident about and which I should double-check.

#### Acceptance criteria
- [ ] Backend route `/api/labels/parse` accepts 1–3 image URLs (Supabase Storage signed URLs) and returns a JSON envelope with structured fields, per-field confidence (`high` | `medium` | `low`), and an overall `is_nj_cannabis_label` boolean.
- [ ] Parse uses Claude Sonnet 4.6 vision with a structured-output schema (JSON mode) covering at minimum:
  - `is_nj_cannabis_label: boolean`
  - `nj_universal_symbol_detected: boolean`
  - `product_type: enum (flower | pre-roll | vape | edible | concentrate | tincture | topical | other)`
  - `strain_name: string | null`
  - `cultivar_classification: enum (indica | sativa | hybrid | unknown)`
  - `cultivator_name: string | null`
  - `cultivator_license_number: string | null` (e.g., "C000186")
  - `manufacturer_name: string | null`
  - `manufacturer_license_number: string | null`
  - `net_weight_g: number | null`
  - `net_weight_oz: number | null`
  - `cannabinoids: { total_thc_pct, total_thc_mg, total_cbd_pct, total_cbd_mg, thca_pct, cbda_pct, cbn_pct, cbg_pct, ... }` (each field nullable)
  - `terpenes: array of { name, pct, mg_per_g }` — top terpenes printed on label
  - `harvest_date: ISO date | null`
  - `package_date: ISO date | null`
  - `expiration_date: ISO date | null`
  - `batch_number: string | null`
  - `metrc_package_tag: string | null` (24-char alphanumeric)
  - `coa_url: string | null` (if a QR code in the image resolves to one — see §3.7)
  - `servings_per_package: number | null`
  - `mg_per_serving: number | null`
  - `parse_warnings: string[]` (e.g., "Total THC % could not be read", "Two strain names detected")
- [ ] p95 end-to-end parse time (image upload start → JSON returned to client) ≤ 10 seconds; p50 ≤ 5 seconds.
- [ ] If `is_nj_cannabis_label` is `false`, user is shown a confirmation screen: "This doesn't look like a NJ cannabis label. Save anyway, retake, or cancel?"
- [ ] If `nj_universal_symbol_detected` is `false` but other NJ fields are strong, surface a soft warning: "Couldn't find the NJ universal symbol — double-check this is from a NJ-licensed dispensary."
- [ ] All parses are logged (anonymized image hashes + JSON output) so we can audit accuracy over time.
- [ ] If parse errors (LLM timeout, malformed JSON), retry once automatically; on second failure, surface "Parse failed — we saved your photos. Try again or enter manually."

#### Manual correction UI

##### Layout (three-zone form) — MF5

The confirmation form must NOT render as a flat list of 25+ parsed fields. It uses three zones, top to bottom:

1. **Identity card (above fold).** Photo thumbnail + strain name + cultivator + product type. The "is this the right product?" check. Always visible.
2. **Verify-first stack.** Every field with `confidence < 0.7` auto-promoted here, ordered by confidence ascending (lowest confidence first). Inline-editable. This is the only zone the user must engage with before save.
3. **Collapsed accordion ("All parsed fields (N)").** Every other field. Expandable for power users; not required to open.

Save CTA is pinned to the bottom of the viewport (sticky), labeled "Save product." Disabled state per business rules below.

##### Confidence indicators — MF4

Confidence is a multi-channel signal, NOT color-only (WCAG 2.1 SC 1.4.1 compliance):

| Confidence band | Glyph | Text label | Border style | Color (reinforcement) |
|---|---|---|---|---|
| `high` (≥0.7) | ✓ check | "Verified" | Solid 1px | Green |
| `medium` (0.4–0.7) | ? caret-question | "Check this" | Dashed 1px | Yellow |
| `low` (<0.4) or missing | ! exclamation | "Couldn't read — please enter" | Double 2px | Red |

Color is reinforcement, never the only signal. Glyphs and labels are present at every state. Aria-label on each indicator: `"<field name>: <text label>"`.

##### Acceptance criteria

- [ ] Form renders in three zones per Layout above; Identity card is the first thing the user sees.
- [ ] Confidence indicators use the 3-channel pattern (glyph + label + border-style) per the Confidence indicators table; color is reinforcement, not signal.
- [ ] Verify-first zone auto-promotes all `confidence < 0.7` fields, sorted by confidence ascending.
- [ ] User can edit any field in either zone. Edits set a per-field `user_corrected: true` flag (used for accuracy telemetry).
- [ ] Cannabinoid section shows percentages and computes total THC and total CBD using NJ formula (Total THC = THCA × 0.877 + delta-9-THC) if individual values are present; user can override.
- [ ] License-number field auto-validates against the seeded license table (§3.5) on blur. Result rendered with the same 3-channel pattern: ✓ + "Verified active" (green) / ? + "License found but inactive" (yellow) / ! + "License not found in CRC seed" (red).
- [ ] "Save product" CTA is sticky at viewport bottom; disabled until at minimum `strain_name`, `cultivator_name`, and `total_thc_pct` (or `total_thc_mg` for non-flower) are populated.

#### Business rules
- Confidence scoring is from Claude's self-reported confidence per field, not a separate model — keep it simple at MVP.
- We never silently substitute parsed data for what the label says. If user edits, the user value wins and is what gets stored as canonical for that Product.

---

### 3.4 Product library

#### User story
As a user who has scanned multiple labels over months, I want a library of all the products I've owned, deduplicated so the same product across multiple purchases doesn't clutter my list.

#### Acceptance criteria
- [ ] Each saved scan creates or updates a `Product` record.
- [ ] Dedup is **per-user** (scoped to `user_id`), never global. The `metrc_tag` UNIQUE constraint is composite `(user_id, metrc_tag)` (MF3) — two different users scanning the same package each get their own Product row, never a cross-user collision.
- [ ] Dedup logic, in order of preference:
  1. **Metrc package tag** present → exact match within `user_id` → same Product.
  2. **Cultivator + strain + batch number** all present and matching within `user_id` → same Product.
  3. ~~Cultivator + strain + harvest date matching → same Product.~~ **Dropped per MF3** — false-positive merges across distinct batches harvested same day are common in commercial cultivation; tier 3 is too lossy.
  4. Otherwise → new Product.
- [ ] When a duplicate is detected on scan-save, prompt: "Looks like you've scanned this batch before — open existing record?"
- [ ] When a duplicate is detected AND the new parse contradicts the stored fields (e.g., different total THC, conflicting terpenes), surface the conflict to the user explicitly: "We have this batch as 24% THC; new scan says 26%. Keep old / Use new / Keep both as separate Products." The new parse is appended to a `parse_history` child table either way — original parse never silently overwritten.
- [ ] Library list view shows: thumbnail, strain name, cultivator, total THC %, last-session date, session count, average rating. Sortable by recency, rating, THC %.
- [ ] Filter by: product type, cultivator, strain, has-sessions / no-sessions, date range.
- [ ] Product detail view shows: full parsed fields (read-only with "Edit" affordance), original photo carousel, COA link if cached, all sessions logged against this product, "Log new session" CTA.
- [ ] User can delete a Product (and all its sessions, with confirmation).
- [ ] User can mark a Product as "favorite" (heart toggle); favorites get a separate filter.

#### Business rules
- A Product is owned by one user (the scanner). Products are not shared across users at MVP.
- Each user has their own product library; there is no global product DB at MVP.
- If a user re-scans the same Metrc tag, photos from the new scan are appended to the existing Product (so we keep a record of the package over time) but parsed fields don't overwrite — the original parse is preserved.

---

### 3.5 NJ license validation (seeded table)

#### User story
As a user, I want some confidence that the cultivator license number on the label is a real, active NJ license, so I can spot fake or unlicensed product.

#### Acceptance criteria
- [ ] A `nj_cannabis_licenses` table is seeded from NJ-CRC public data (license number, business name, license type, status, address, last_verified_at).
- [ ] On Product save, the parsed `cultivator_license_number` and `manufacturer_license_number` are looked up.
- [ ] Match outcomes:
  - Found + active → green check, "Verified NJ-licensed cultivator: [name]"
  - Found + inactive → yellow warning, "License found but currently inactive — last verified [date]"
  - Not found → red flag, "License number not found in our NJ-CRC seed (last refreshed [date]). Could be a typo, a brand-new license, or a non-NJ product."
- [ ] License match status is stored on the Product record (`license_validation: verified | inactive | not_found | not_checked`).
- [ ] An admin job refreshes the license table monthly. The freshness date is shown in the UI ("License data last refreshed: 2026-04-15").
- [ ] User can override the validation outcome (e.g., dispute a "not found") with a free-text note for their own records.

#### Business rules
- The seed table is read-only from the app's perspective; populated by an out-of-band scraper or OPRA request.
- "Not found" is **not** a hard error — it surfaces as info to the user, never blocks save.

---

### 3.6 Session logging — the heart of the product

This is the deepest part of the product per Decision #6. Most journal apps fail because the form is a wall of fields. Our design principle: **default to fast, allow deep**. Two modes, one shared data model.

#### Two modes

**Quick log mode (default).** Optimized for "I just took a hit and want to record it before I forget." Four taps, 15 seconds.

**Detailed log mode.** Full session form with progressive disclosure — collapsible sections, smart defaults, no required fields beyond timestamp + product. Optimized for medical users and connoisseurs who want the full record.

User can switch between modes mid-entry without losing data; both write to the same `Session` record.

#### User story (Quick log)
As a user about to consume, I want to log a session in 15 seconds with just product, dose, method, and a 1-tap mood check, so the friction never stops me from logging.

#### User story (Detailed log)
As a user who cares about real pattern detection, I want to capture dose, timing, effects, mood deltas, symptoms, side effects, and context, so my analytics actually mean something.

#### Quick log acceptance criteria
- [ ] From any Product detail page or Home, "Quick log" is a single tap.
- [ ] Quick log form shows:
  1. **Product** (pre-filled if launched from Product page; otherwise picker showing recent + favorites)
  2. **Method** (icon row: joint / bowl / vape / dab / edible / tincture / topical / other) — single tap selects
  3. **Amount** (single slider OR three preset chips: "small / medium / large" — units auto-derived from method, e.g., g for flower, mg for edible, puffs for vape)
  4. **How are you feeling?** — five-emoji mood row (great / good / okay / meh / bad), single tap
  5. "Save" button
- [ ] Default timestamp = now; can be backdated by tapping the time chip.
- [ ] Save creates a Session record. User is returned to wherever they came from with a small confirmation toast.
- [ ] User can tap the toast or the saved session row to jump to Detailed log mode and add more.

#### Detailed log acceptance criteria

The detailed form uses **progressive disclosure**: only "Basics" is open by default; everything else is collapsed sections labeled with what they capture, so users see the surface and reveal depth as they want it.

**Section 1 — Basics (always open)**
- [ ] Product (with picker + recent)
- [ ] Start time (defaults to now, editable)
- [ ] Method (joint, bowl, bong, vape pen, vape cartridge, dab, edible, tincture, capsule, topical, other)
- [ ] Amount + unit (smart defaulted by method: g for flower, puffs/mg for vape, mg for edible, drops for tincture)
- [ ] Setting (alone / with one other / small group / large group / public) — single-select chips

**Section 2 — Timing (collapsible)**
- [ ] Onset time — "How long until you felt it?" (chip presets: <5min, 5–15min, 15–30min, 30–60min, 60min+, never)
- [ ] Peak time — "When did it peak?" (chip presets: 15–30min, 30–60min, 1–2hr, 2–4hr, 4hr+)
- [ ] Total duration — "How long did effects last?" (chip presets: <1hr, 1–2hr, 2–4hr, 4–6hr, 6hr+)

**Section 3 — Effects (collapsible)**

A grid of effect dimensions, each on a 1–5 Likert scale (None / Slight / Moderate / Strong / Intense). User can leave any blank.

- [ ] **Positive effects:** relaxation, euphoria, focus, creativity, sociability, energy, sleepiness, appetite, pain relief
- [ ] **Negative effects:** anxiety, paranoia, dry mouth, dry eyes, dizziness, headache, nausea, racing thoughts, lethargy, couch-lock

**Section 4 — Mood before / after (collapsible)**
- [ ] Mood before (5-point: very low → very high)
- [ ] Mood after (5-point: very low → very high)
- [ ] Stress before (5-point)
- [ ] Stress after (5-point)
- [ ] (We compute and display the delta, e.g., "+2 mood, –3 stress" — useful in analytics)

**Section 5 — Symptoms relieved (collapsible, multi-select)**
- [ ] Multi-select chips: sleep, anxiety, depression, chronic pain, acute pain, headache/migraine, nausea, appetite loss, PTSD, muscle spasm, inflammation, focus/ADHD, social anxiety, other (free text)
- [ ] For each selected symptom, a 1–5 "how much did it help?" slider.

**Section 6 — Context & notes (collapsible)**
- [ ] Activity (chips: relaxing, watching TV/movie, music, gaming, social, creative work, exercise, reading, eating, intimacy, sleep prep, other)
- [ ] Combined with alcohol? (yes / no / unsure)
- [ ] Combined with other substances (free text, optional)
- [ ] Free-text notes field (multi-line)
- [ ] Photo attachment (optional — e.g., the joint, the setting; useful for memory)

**Section 7 — Overall (always visible at bottom)**
- [ ] Overall rating 1–10
- [ ] "Would buy again?" (yes / no / maybe)

#### Acceptance criteria — common to both modes
- [ ] All fields in Detailed log are optional except: product, start time, method.
- [ ] User can edit a saved session for up to 30 days; after that it's read-only (preserves data integrity for analytics).
- [ ] User can delete a session with confirmation.
- [ ] Sessions can be logged retroactively (backdated up to 30 days) for users who forgot in the moment.
- [ ] Voice-to-text on the notes field (browser-native `SpeechRecognition` where available).
- [ ] No required fields beyond the three above — we'd rather have a partial session than no session.

#### Business rules
- A session is always tied to exactly one Product. (No "untagged" sessions at MVP.)
- Quick log and Detailed log write to the same `Session` row; the only difference is which fields are populated.
- Total duration field is informational; we don't try to time the session live in MVP.

#### User flow — Detailed log
1. Product detail page → "Log session" → method picker.
2. After picking method, full form opens with Basics expanded; user can save right then or expand other sections.
3. User progressively reveals sections as they want.
4. On save, returns to Product page with the new session in the session list.

---

### 3.7 QR-based COA fetch and cache

#### User story
As a user scanning a label that has a COA QR code, I want the app to follow the QR, store the URL, and cache the COA PDF locally, so I can revisit the lab results even if the dispensary's link expires.

#### Acceptance criteria
- [ ] Label-capture flow attempts to detect QR codes in any submitted image using a client-side library (e.g., `jsQR` / BarcodeDetector API where supported).
- [ ] Detected QR contents are passed to Claude during parse so it can also confirm via vision (defense in depth).
- [ ] If a QR resolves to a URL (any URL — Metrc Retail ID, lab portal, dispensary product page), it's stored on the Product as `coa_url`.
- [ ] If the URL responds with a PDF (or HTML containing a PDF link we can resolve heuristically), the PDF is fetched server-side, virus-scanned/MIME-validated, and cached in Supabase Storage tied to the Product.
- [ ] Product detail view shows "Lab COA available — view / download" if a PDF was cached, "Lab page" with external link icon if only a URL is known.
- [ ] If the original URL goes dead later, user still has the cached PDF.
- [ ] We do **not** parse the COA itself in MVP (no extracting cannabinoid % from the COA to compare to label) — that's v1.5 (label-vs-COA reconciliation).

#### Business rules
- COA fetch is best-effort. Failure to fetch the PDF doesn't block Product save.
- COA URL is preserved verbatim — we do not transform or shorten it.
- We do not attempt to crawl beyond the linked URL (no following links from the COA page).

---

### 3.8 Personal analytics dashboard

#### User story
As a user with 10+ sessions logged, I want a dashboard that shows me patterns I couldn't see by memory alone — what works for me, what doesn't, what I keep coming back to.

#### Acceptance criteria

The dashboard has discrete cards. All compute on the user's own data, client-side or via a Supabase view.

- [ ] **Top strains card** — strains by average overall rating, with session count. Filterable by symptom relieved.
- [ ] **Favorite cultivators card** — cultivators sorted by average rating + purchase frequency. Shows "you've bought from [X] [N] times, average rating [Y]."
- [ ] **Terpene preferences card** — for users with ≥5 logged sessions, shows correlation between top terpenes (myrcene, limonene, pinene, caryophyllene, linalool, terpinolene, humulene, ocimene) and their highest-rated effects. Phrased as **observation, never claim**: "Sessions with high-myrcene products averaged a sleepiness score of 3.8/5 — your highest."
- [ ] **What worked for X card** — for each symptom the user has flagged "helped" on, top 3 products that helped most. E.g., "For sleep, top 3 products were: …"
- [ ] **Potency over time card** — chart of total THC % across products purchased, by month. Helps the user see if they're chasing higher THC and whether ratings track potency. (Spoiler: usually not.)
- [ ] **Tolerance trend card** — for users with ≥10 sessions, plots dose vs. effect-strength over time. Useful signal for tolerance build-up.
- [ ] **Method breakdown card** — donut showing % of sessions by consumption method.
- [ ] **Spend (lite) card** — if user has entered prices on any Products (optional field on Product), shows total spend + $/session. (Pricing is optional in MVP; a fuller $/mg-THC analytics is v1.5.)
- [ ] All charts use a consistent color palette and have an "Empty — log more sessions to unlock" state with a session-count threshold shown.
- [ ] Each card has an "info" affordance explaining what it's based on, with a disclaimer for any health-adjacent observation: "This is your personal data, not medical advice."

#### Business rules
- All correlations are descriptive ("sessions with X averaged Y"), never causal ("X causes Y") and never prescriptive ("you should try X").
- No card surfaces until the user has the minimum data to make it non-trivially populated (defined per-card; defaults at 5 sessions).
- All computation is on the user's own data only — no comparison to other users at MVP (would require a different privacy posture and is a v2 conversation).

---

### 3.9 Search / filter own product + session history

#### User story
As a user with many products and sessions, I want fast search and filtering so I can answer "what did I have last time I had a great night's sleep?" or "show me everything from Fresh Grow."

#### Acceptance criteria
- [ ] Global search bar accessible from main nav. Searches: product strain names, cultivator names, free-text session notes, symptom tags.
- [ ] Filter chips on Product list: product type, cultivator, has-sessions, favorite, date range, terpene-dominant.
- [ ] Filter chips on Session list: product, method, rating range, date range, symptom relieved, setting.
- [ ] Combined view: "Sessions where [filter] ranked Y on [effect]." E.g., "Sessions where I rated sleep ≥4 — sorted by rating."
- [ ] Search results show context (matched field highlighted, snippet of notes if matched).
- [ ] Empty-state copy is helpful, not just "No results" — suggest filters to relax.

---

## 4. Non-functional requirements

### 4.1 Performance

- **Label parse end-to-end** (camera capture submit → structured form ready): p50 ≤ 5s, p95 ≤ 10s. (Anthropic API typical Sonnet 4.6 vision response is 2–6s; image upload + JSON validation adds ~2s.)
- **Page navigation**: p95 ≤ 1s on a mid-tier mobile (iPhone 12 / Pixel 6) over 4G.
- **First contentful paint** on landing: ≤ 2s on 4G.
- **Quick log save**: ≤ 500ms perceived (optimistic UI; reconcile on background).
- **Analytics dashboard initial render**: ≤ 2s for users with ≤ 200 sessions.
- **Image upload size cap**: 2MB per image post-downscale.

### 4.2 Scalability

- Designed for 10k–50k MAU at v1.0. Beyond that triggers an architecture revisit.
- Anthropic API rate limits — batch / queue if a single user exceeds 5 parses in 60s.
- Supabase row-level security policies must scale linearly per user; no global tables that grow unbounded except the seeded `nj_cannabis_licenses` (~hundreds of rows) and `parse_log` (rotated every 90 days).

### 4.3 Security

- **Auth:** Supabase Auth (email + password, magic link). MFA optional (TOTP) at MVP, mandatory if account holds >100 sessions (encourages security for power users).
- **Authorization:** Supabase row-level security on every user-owned table. Server routes verify Supabase JWT.
- **At-rest encryption:** Supabase default + application-layer encryption for free-text notes and sensitive symptom data using a per-user derived key (so even a Supabase ops compromise reveals minimal). Acceptable to defer app-layer encryption to P1 if it slows MVP — call this out explicitly in the architecture doc.
- **In-transit:** TLS 1.3, HSTS preload.
- **Secrets:** Anthropic API key server-side only. No client-side LLM calls.
- **Image storage:** signed URLs, expiring 1h. No public buckets.
- **No third-party analytics SDKs** that can touch consumption data. If we run product analytics at all, it must be a self-hosted instance (e.g., PostHog self-hosted) or strictly aggregated funnel events with no payload data.
- **No password reset by SMS** (SIM swap risk). Email magic link only.

### 4.4 Reliability

- Target 99.5% uptime in MVP (Supabase + Vercel default postures get us most of this).
- Anthropic API failures must degrade gracefully — saved photos with "parse failed, try again" state, never silent loss.
- Cloud sync must be idempotent and conflict-resolvable: if a user saves a session offline (PWA), the sync resolves on reconnect using last-write-wins on field-level merge for the Session row.
- Data backup: rely on Supabase point-in-time recovery; document the user-facing impact of any restore.

### 4.5 Accessibility

- **WCAG 2.1 AA** target across all flows.
- All interactive elements keyboard-navigable; focus indicators visible.
- Color contrast ≥ 4.5:1 on text, 3:1 on large text.
- Camera capture has a manual photo-upload alternative for users who can't operate the camera UI (already in §3.2).
- Likert sliders have keyboard arrow-key support and accessible labels per step.
- Voice-to-text on notes field (already in §3.6) doubles as accessibility win.
- Effect grids announce row+column+value to screen readers.
- App must be usable in landscape and portrait.
- High-contrast mode and prefers-reduced-motion respected.

### 4.6 Privacy

- **Data classification:** consumption data, symptom data, and DOB are highly sensitive. Treated as the highest tier.
- **Data export:** user can download a full export of their data (Products + Sessions + Photos + COA cache) as a ZIP (JSON + CSV + image files) in <60s. Discoverable from Settings.
- **Account deletion:** user-initiated; deletes all rows + storage objects within 30 days, with a 7-day undo window. No retention of "anonymized" copies.
- **No third-party trackers, no marketing pixels, no Meta/TikTok/Google Ads SDKs.** Period.
- **Consent log:** age-gate confirmation, NJ self-attestation, and any future opt-ins are timestamped and stored.
- **Privacy policy** and **Terms of Service** are NJ-tailored and surfaced before account creation.

---

## 5. Technical requirements

The Architecture brief is the source of truth; this section summarizes what the PRD assumes.

### 5.1 Stack (per Architecture brief)

- **Frontend:** Next.js (App Router), React, TypeScript, Tailwind. PWA via `next-pwa` or equivalent.
- **Backend:** Next.js API routes (server actions) on Vercel (or comparable).
- **DB + auth + storage:** Supabase (Postgres + Supabase Auth + Supabase Storage).
- **LLM:** Anthropic API, model = `claude-sonnet-4-6` (vision), invoked server-side only.
- **QR / barcode:** `BarcodeDetector` API where available, `jsQR` fallback.

### 5.2 Integrations

- **Anthropic API** — label parsing. Failure mode: graceful degradation (§4.4). Cost-monitored.
- **Supabase** — DB, auth, storage. Failure mode: app unusable; depend on Supabase status.
- **NJ-CRC license data (offline pipeline)** — manual or scripted ingest into a seed table; refreshed monthly; not a runtime dependency.
- **No Metrc API integration** at MVP — only opportunistic QR-URL capture (§3.7).
- **No Leafly / Weedmaps / Hytiva** strain DB integration at MVP.

### 5.3 Data model (high level)

Detailed in the Architecture brief. The PRD requires support for:
- `users`, `accounts` (Supabase Auth)
- `products` (per-user library, dedup keys on metrc tag and cultivator+strain+batch)
- `product_photos` (1:N to product)
- `sessions` (1:N to product)
- `session_effects` (the Likert grid; either denormalized columns on `sessions` or a normalized child table — architect's call)
- `coa_cache` (1:1 to product, optional)
- `nj_cannabis_licenses` (seed table, global)
- `parse_log` (audit, 90d retention)
- `consent_log` (audit, indefinite)

### 5.4 Infrastructure

- **Hosting:** Vercel (frontend + API routes), Supabase managed, Anthropic SaaS.
- **Environments:** local dev → preview (per-PR via Vercel) → prod.
- **Region:** US East (Supabase + Vercel) for latency; data residency disclosed in privacy policy.
- **CI:** GitHub Actions; lint, typecheck, unit tests, PR previews.

---

## 6. User experience

### 6.1 Key user journeys

#### Journey 1 — First scan (the wedge moment)

A new user, just bought a quarter ounce, opens the app for the first time.

1. Lands on splash → "Get started."
2. DOB → 21+ confirmed.
3. Email + password → magic link verify.
4. NJ self-attest, geo permission optional.
5. 3-card explainer.
6. Empty Home with "Scan your first label" CTA.
7. Camera opens → user captures front + back of label (~15s).
8. "Parse label" → loading state with friendly progress copy ("Reading the label… checking the NJ universal symbol… extracting cannabinoids…") for 4–6s.
9. Parsed form appears with green/yellow/red dots. User reviews; maybe edits one terpene name. Hits Save.
10. Product saved. User sees Product detail page with a prominent "Log a session" CTA.
11. Optional PWA install prompt: "Add to Home Screen so it's there next time you light up."

**Success criterion:** user reached step 10 within 5 minutes of step 1.

#### Journey 2 — Repeat scan of same product

User finishes the bag, opens a new one of the same strain from the same cultivator a week later.

1. Home → "Scan a label" → captures.
2. Parse returns.
3. Save → dedup logic detects same Metrc-tag / cultivator+strain+batch.
4. Modal: "Looks like you've scanned this before. Open existing record?" — user taps yes.
5. New photos appended; Product opens with all prior sessions visible.
6. User taps "Quick log" and records the session in 15 seconds.

#### Journey 3 — Detailed session log (the journal moment)

User just consumed and wants the full record.

1. From Product detail → "Log session" → method picker → form opens with Basics expanded.
2. User taps method (vape pen), drags amount slider (3 puffs), picks setting (alone), notes start time = now.
3. Saves immediately as a Quick log? Or expands sections.
4. Expands Effects → marks relaxation 4, sleepiness 3, dry mouth 2.
5. Expands Mood → before "low," after "moderate."
6. Expands Symptoms → flags "anxiety" with a 4 helped score.
7. Expands Notes → dictates a sentence via voice-to-text.
8. Overall rating 8 → Save.
9. Returns to Product page; new session appears at top of session list.

**Success criterion:** Detailed log can be filled in under 90 seconds without feeling rushed.

#### Journey 4 — Weekly review (the analytics moment)

User on Sunday evening reviews the week.

1. Opens app → bottom nav "Insights."
2. Sees "Top strains this month," "Favorite cultivators," "Terpene preferences."
3. Taps "Terpene preferences" → reads "Sessions with high-myrcene products averaged sleepiness 3.8/5 — your highest."
4. Taps through to filter Products by myrcene-dominant → considers what to buy next.
5. Taps "What worked for sleep" → top 3 products with session counts.

**Success criterion:** user comes back monthly to view at least one card.

### 6.2 UI / UX guidelines

- **Tone:** calm, knowledgeable, not stoner-coded. We're a journaling tool, not a meme.
- **Color:** dark-mode-first (most consumption journaling happens at night); a light mode is supported but the primary brand expression is dark.
- **Typography:** sans-serif system font stack for performance; one display font for headers if budget allows.
- **Imagery:** abstract botanical / molecular motifs are fine; avoid photographed bud / smoke imagery to keep app-store-adjacent reviewers comfortable even though we're not on stores.
- **Iconography:** custom set for consumption methods (joint, bowl, vape pen, dab, gummy, oil) — recognizable at 24px.
- **Information density:** dense enough that a Product detail screen shows photo, key fields, and recent sessions above the fold on a 6.1" phone. Forms breathe.
- **No gamification at MVP** — no streaks, no badges, no points. Cannabis + gamification is an ethics conversation we're not having yet.

### 6.3 Error handling

- **Camera permission denied** → "Camera blocked. You can still upload a photo from your library."
- **Network offline** → optimistic UI; sessions and Product edits queued and synced on reconnect; status indicator in header.
- **Parse failure** → "We couldn't read that label. Your photos are saved. Try again or enter the details manually."
- **Auth expired** → silent refresh; if refresh fails, prompt re-login with current state preserved.
- **Validation failure on save** → inline errors near the offending field, not toast.
- **Unrecoverable error** → friendly error page with a "report this" affordance that opens a pre-filled email to support, including a redacted error trace.

---

## 7. Dependencies & assumptions

### 7.1 Dependencies

- **Anthropic API availability and pricing.** Hard runtime dependency for label parsing. Mitigation: graceful degradation + manual entry path means the app is still usable if Anthropic is down, just slower to onboard new products.
- **Supabase availability.** Hard runtime dependency for data, auth, storage.
- **NJ-CRC license registry.** Soft dependency — we seed manually. If the registry format changes, ingest pipeline breaks; impact is stale validation, not app failure.
- **iOS Safari and Android Chrome PWA capabilities.** We rely on `getUserMedia`, `BarcodeDetector` (where supported), Service Workers, IndexedDB. Browser-vendor regressions are out of our control.
- **Device camera quality.** Low-end devices may produce labels Claude can't reliably parse; mitigation = manual edit UI.

### 7.2 Assumptions

- Users are willing to create an account (decision #5 confirms cloud sync is required).
- Users will primarily access the app from a phone in front of the product (not retrospectively from desktop).
- NJ-CRC will not introduce a rule prohibiting third-party informational apps cataloging consumer purchases. (See discovery brief §1.5; current rules don't.)
- Metrc Retail ID QR codes will continue to resolve via the URLs printed on labels for the foreseeable future. (No formal SLA.)
- Claude Sonnet 4.6 vision can reliably parse a NJ cannabis label in p95 ≤ 8s (need to validate in technical spike — see §8 OQ).
- The user wants this app for themselves personally; if a v1 broader rollout is desired, success metrics may shift.
- Free-at-launch is sustainable while user volume is bounded; we'll monitor Anthropic + Supabase costs and revisit monetization when users >5k.

---

## 8. Open questions

- [ ] **Anthropic vision accuracy on real NJ labels** — what's the actual structured-output accuracy on the messy, glossy, sometimes-printed-poorly NJ labels we'll encounter? Needs a technical spike before commit on the p95 ≤ 10s SLO. (Technical, P0.)
- [ ] **NJ-CRC license data source** — which exact list/page do we scrape, and is OPRA a more reliable channel? (Operational, P0 before MVP launch.)
- [ ] **App-layer encryption of session notes** — encrypt with per-user-derived key at MVP, or punt to P1? Trade-off: real privacy vs. complexity (key management, search-over-encrypted-data is hard).
- [ ] **Backdating window** — 30 days is a guess. Is that the right cap? (Could cap at 7 to discourage retroactive fabrication, or remove cap entirely for medical users.)
- [ ] **Expiring sessions to read-only** — do we actually want sessions to lock after 30 days? Pro: data integrity for analytics. Con: users will edit anyway and we'll get bug reports.
- [ ] **PWA push notifications on iOS** — iOS 16.4+ supports web push when installed. Worth implementing for "Hey, you logged a session — want to log how it ended?" 90 minutes later? Or distracting? (UX.)
- [ ] **Photo retention** — keep all label photos forever or compress/delete originals after parse + thumbnail? (Storage cost vs. user expectation.)
- [ ] **Pricing data on Products** — do we capture price at Product save (optional field) or as a separate "Purchase" record? Affects how $/mg-THC is reported in v1.5.
- [ ] **Onboarding example** — should we ship a sample Product (real or demo) so first-time users can see the app populated? Or empty-state-first to push the first scan?
- [ ] **Multi-account households** — v2-ish, but is there a sharing model envisioned? (E.g., spouses both log against the same Product.)
- [ ] **Minimum browser support** — iOS Safari 16+? Chrome 110+? Document and enforce.

---

## 9. Phasing

### P0 — MVP (target: ship for personal use)

Everything in §3.1 through §3.9, §4 NFRs at the levels stated.

The gate for "MVP done": user can complete Journeys 1, 2, and 3 end-to-end with ≥80% parse acceptance and Quick log under 30s. Analytics dashboard (§3.8) cards are present but allowed to be skeletal — must include Top strains, Favorite cultivators, Method breakdown, and Potency over time at minimum; Terpene preferences and What-worked-for-X can launch with a "log more sessions to unlock" gate.

### P1 — v1.0 polish

- Push notifications (post-session prompt, weekly review prompt)
- App-layer encryption of session notes (if punted from P0)
- Backdating UX refinements
- Multi-photo gallery and photo gestures
- Search ranking improvements (semantic search over notes via small embedding model)
- Spend / pricing field on Products
- "Sessions like this" recommendation (find sessions in user's own history with similar terpene profile + dose + method)
- Symptom-trend chart (time series of "how much did weed help my sleep?" over months)
- Onboarding-time demo Product
- A11y audit and remediation pass

### P2 — v1.5

- **Consumer-protection reporting (the deferred "Reporter").** One-tap "report this label to NJ-CRC" with pre-filled email to `crc.compliance@crc.nj.gov`, attached photos, structured findings. Also enables label-vs-COA reconciliation (parse the cached COA, compare to label, surface deltas).
- **Recall cross-reference.** Cross-check saved Metrc tags + cultivators against any NJ-CRC recall feed we can scrape; alert affected users.
- **$/mg-THC analytics.** Full cost tracking across dispensaries and cultivators.
- **Doctor / caregiver export.** PDF clinical export with a curated symptom-trend summary.
- **Cultivator profile pages.** Aggregate own history per cultivator with terpene fingerprint comparison.
- **Light social — invite-only sharing.** Share a single Product card to a friend via link (read-only). No public feed. Decision deferred until usage data justifies.
- **Multi-state pluggable rules engine.** Only if user demand or business case appears. Revisit after MVP+P1.
- **Native iOS app (App Store).** Considered only if PWA limits become binding (push, camera fidelity, app-store discoverability). Apple cannabis policy permits with geo-restriction.

---

## 10. Revision history

| Version | Date | Author | Changes |
|---|---|---|---|
| 0.1 | 2026-05-05 | Nick D. + Product Requirements specialist | Initial draft. Builds on discovery brief 2026-05-05. Reflects user decisions on NJ-only scope, PWA platform, journal-only "Reporter" interpretation, free monetization, cloud-sync privacy posture, session-level logging depth, 21+ self-attestation. |
