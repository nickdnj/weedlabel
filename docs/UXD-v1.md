# UX Design: HighNotes (iOS)

**Version:** 1.0
**Last Updated:** 2026-05-27
**Author:** Nick DeMarco with Claude (AI assist)
**Status:** Living — reflects the device-tested v1 spike
**PRD:** [`PRD-v1.md`](./PRD-v1.md) · **SAD:** [`SAD-v1.md`](./SAD-v1.md)

---

## 1. Design principles

1. **Confidence, not clutter.** Lead with what we're sure of (strain, character).
   Surface chemistry when legible; flag it when not; never fake it.
2. **Reliable capture beats fancy capture.** Confirm we're reading a real label
   (content), guide framing (viewfinder), then take a sharp photo. No fragile
   document-edge detection.
3. **Honest tone, warm voice.** "Your AI budtender" — bold, playful, generous.
   Privacy stated plainly. No medical or salesy language.
4. **Always something to read.** The result screen is the hero; it's never blank.

Visual direction (per `Brand.swift`): bold-&-playful, vivid green→violet
gradient, heavy rounded type, emoji-forward but App-Store-safe copy. **Portrait
only.**

---

## 2. Screen flow

```
Onboarding (first run only)
   └─► Idle  ──Scan──►  Scanning  ──confirm──►  Capturing  ──►  Preview/Confirm
                                                                   │
                                            ┌──Re-scan─────────────┘
                                            │
                                       Process │
                                            ▼
              Parsing → Checking → Summarizing → Result (PostScan)
                                                     │
                                              Save & scan another
                                                     ▼
                                                   Idle
```

Failure at any processing step → a friendly **Failed** screen with "Try again."

---

## 3. Screens

### 3.1 Onboarding (first run)
One screen, one job: what HighNotes is + the privacy promise ("100% on-device,
no accounts, no tracking; the only thing that leaves your phone is a link you
tap"). Single CTA. Persists only a "seen it" flag. (`OnboardingView`/`RootView`.)

### 3.2 Idle
- App mark + tagline ("Your AI budtender").
- FM-availability copy if AI is unavailable (older hardware / AI off / not ready)
  — scanning still works, AI summary is gated.
- Primary CTA: **Scan a label**.
- Debug-only row: **Run canary**, **Prompt Lab** (`#if DEBUG`).

### 3.3 Scanning  *(the bank-check-inspired capture)*
- Live camera, full screen.
- **Viewfinder**: dimmed mask with a punched-out rounded rectangle + white corner
  brackets — "line the label up in here." OCR is constrained to this region.
- **Field chips** (top): `License · Metrc · Potency · Terpenes · QR`, each filling
  green with a checkmark as that signature is detected. This is the "we're
  looking at the right thing" signal.
- **Guidance text** adapts: "Center the label" → "Almost there" → "Looks good —
  tap to capture, or wait for all fields" → "Hold steady — auto-capturing…".
- **Shutter button** (bottom center): disabled until ≥3 chips lit. When all 5 are
  detected, a **green countdown ring** fills around it over ~1s and then
  auto-fires; the user can tap any time to capture early. **Cancel** at bottom-left.

### 3.4 Capturing
Brief progress overlay — "Capturing… taking a sharp photo of the label" — while
the high-res still is grabbed and OCR'd.

### 3.5 Preview / Confirm
Check-deposit-style confirmation:
- The **captured photo** at the top (so you see exactly what was shot).
- A capture summary ("Captured N characters, K QR") + the **field chips**.
- The raw **OCR text** (monospace, selectable) for transparency.
- Bottom actions: **Re-scan** (back to camera) and **Process** (run the pipeline).

### 3.6 Processing states
Sequential progress overlays: "Reading label…", "Checking values…", "Generating
AI summary… (on-device, nothing leaves your phone)".

### 3.7 Result (PostScanView) — the hero
Top to bottom:
1. **Product header** — strain name + cultivator.
2. **Verify banner** (only if a sanity rule fired) — orange "Verify against the
   printed label" + the specific reason (e.g. Total-THC mismatch). Non-blocking.
3. **High-potency warning** (only if Total THC > 40%) — the NJAC wording.
4. **Profile card** — the strain's sativa/indica/hybrid read with an icon
   (sun / moon / split-circle / horizon / haze), the character note
   (e.g. "earthy, pine-and-hash"), effect direction, time-of-day, and a
   provenance line ("from label marking" / "inferred from name (kush)" / "your
   correction"). A pencil opens the inline **strain-type editor**. If we have no
   classification, this becomes a **"Strain type unknown — tap to set"** prompt.
5. **AI Summary** — the visual hero (gradient card). 2–3 sentence informational
   description grounded in real fields; falls back to a grounded, character-led
   line if the model is unavailable/blocked (badged "Field summary").
6. **"BASED ON" chips** — the terpenes/cannabinoids the read leaned on.
7. **Learn more** — tappable rows: the label's QR/COA link (if any) and a
   "Search {cultivator}" web search. Opening hands off to Safari.
8. **Disclaimer** — NJAC §17:30-16.3(c)(5) wording.
9. **Source data** (collapsible) — the full parsed field list.
10. Sticky **Save & scan another**.

### 3.8 Strain-type editor (inline)
A vertical list of the 5 classes — **Sativa, Indica, Hybrid (balanced), Hybrid
Sativa-leaning, Hybrid Indica-leaning** — each with its icon/tint and a checkmark
on the current value. Selecting one saves the correction (persists, outranks
inference) and collapses the editor. If the current value *is* a user
correction, a "Remove my correction" option reverts to marker/lineage.

### 3.9 Failed
Friendly message + "Try again." Used for empty OCR, extraction errors, etc.

### 3.10 Debug surfaces (not shipped)
- **Prompt Lab** — edit extraction/summary prompts + OCR, toggle preprocessor,
  Run vs Baseline A/B, copy prompts/JSON, view parsed result.
- **Run canary** — fixture-driven full pipeline for Simulator testing.

---

## 4. Interaction details that carry weight

- **Auto-capture with override.** The countdown ring makes auto-capture
  legible and cancellable; manual tap always wins. Flicker (a field dropping)
  resets the ring.
- **High-res still, not live frames.** The user feels this as a sharper preview
  image and better results — the capture moment is a deliberate "snap," not a
  silent scrape of blurry frames.
- **Corrections feel owned.** "Your correction" provenance + persistence makes
  the strain DB feel like the user's, not a black box.
- **The result never disappoints.** Even a hard, unreadable label yields a
  name-led, character-rich card rather than an error or a blank.

---

## 5. Copy guidelines

- Warm, plain, a little playful. Emoji okay in product chrome, not in
  field/data rows.
- **Never** medical ("treats", "relieves"), dosing ("Nmg", "recommended dose"),
  or second-person directives ("you should") in any AI or fallback text — these
  are enforced by the P6 validator, but write to them too.
- Privacy promise stated on onboarding and reinforced on the summarizing state.
- Flag uncertainty honestly: "the lab figures weren't legible in this scan —
  check the printed label."

---

## 6. Open UX questions

- Should the Profile card's strain-type editor also let the user correct the
  **strain name** (the lot-code confusion case)?
- Where does session/consumption **journaling** live when it returns (a tab? a
  post-save prompt)?
- Tipping placement *if/when* added (deferred; keep generous, never a wall).
