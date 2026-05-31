# SPEC — Beta scan-feedback (TestFlight only)

**Status:** planned · **Date:** 2026-05-30 · **Scope:** beta builds only, removed at ship

## Why

During TestFlight we want opted-in testers to share real scans so we can improve
extraction and act on feedback. The production app's headline claim is **"No Data
Collected"** (APP-STORE-CHECKLIST §5) and the pre-submit smoke test verifies a silent
wire (§9). So this whole feature **must compile out of the App Store build** — it is a
beta-only instrument, not a product feature.

No backend, no embedded secrets, nothing to dismantle from a server: the structured
data rides out over the user's own mail client via `MFMailComposeViewController`, with
a share-sheet fallback. TestFlight's native feedback (automatic crash logs + screenshot
notes) is the always-on baseline that covers "it broke"; this spec covers "the
extraction was wrong / here's the scan."

## Decisions (locked)

- **Transport:** email composer → `vistter2@gmail.com` (dedicated public-facing inbox, not personal mail). Fallback to `UIActivityViewController`
  when `MFMailComposeViewController.canSendMail()` is false (no Mail account, or Simulator).
- **Trigger:** after **every** scan, *only when the tester has opted in*. A lightweight
  "How did we do? 👍 / 👎" sheet with an optional note and a **Share details** button.
- **Opt-out (beta pushes harder):** sharing is **ON by default in beta builds**. A toggle in
  About lets a tester turn it off. A one-time first-run notice discloses what's shared
  (including the label photo), that it's beta-only, and how to disable it — disclosure, not a
  gate. The actual email send is still always an explicit tap in the composer, never silent.
- **Payload:** OCR text, parsed `CannabisLabel`, pick-from-label corrections, AI summary,
  the 👍/👎 + note, triage metadata. Label photo attached as a separate JPEG.
- **Gating:** `#if BETA`. The flag is defined for Debug and a new **Beta** archive config,
  and is **absent** from Release (App Store). Nothing in this spec exists in the store binary.

## Build gating

TestFlight distributes a Release-config archive by default, so `#if DEBUG` is *not* enough —
it would strip the feature from TestFlight too. Add a dedicated config:

`project.yml`:
```yaml
configs:
  Debug: debug
  Release: release
  Beta: release            # release optimisation, beta capabilities

# in targets.weedlabel.settings:
configs:
  Debug:
    SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) BETA"
  Beta:
    SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) BETA"
  # Release: (no BETA — feature compiles out)
```

Add a scheme archive path that uses **Beta** for TestFlight uploads; the final App Store
submission archives with **Release**. Net: upload the Beta archive to test, the Release
archive to ship. Verify with the §9 proxy that the Release build makes zero network calls.

> Alternative considered: runtime TestFlight detection via the sandbox receipt
> (`Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"`). Rejected as
> primary because the user asked for the feature *removed* at ship, and compile-out is the
> only thing that makes the "no data on the wire" smoke test provably true.

## Components

All new files gated `#if BETA … #endif`.

1. **`weedlabel/Services/BetaFeedback.swift`**
   - `struct ScanFeedback: Codable` — `ocrText`, `label: CannabisLabel`, `summaryText`,
     `summaryDidFallback`, `corrections: [String]` (strain-name / class / product-type /
     cannabinoid edits applied this session), `rating: Int` (👍 = 1 / 👎 = -1 / unset = 0),
     `note: String`, and triage metadata: `appVersion`, `buildNumber`, `iosVersion`,
     `deviceModel`, `fmAvailability`, `scannedAt`.
   - `enum FeedbackTransport` — builds the mail (subject `Pocketbud beta — scan feedback (v<build>)`,
     body = note, attachments = `feedback.json` + `label.jpg`), exposes `canUseMail`, and the
     share-sheet fallback payload.
   - `@AppStorage("beta.feedback.shareEnabled") var shareEnabled = true` — **default ON** in
     beta (opt-out). About's toggle flips it; the first-run notice only discloses, doesn't gate.

2. **`weedlabel/Views/BetaFeedbackPrompt.swift`**
   - The post-scan 👍/👎 + note sheet. Calls into `BetaFeedback` to present the composer.
   - `MailComposeView: UIViewControllerRepresentable` wrapping `MFMailComposeViewController`.

3. **`weedlabel/Views/BetaConsentView.swift`** — one-time first-run **notice** (not a gate)
   listing the payload and how to turn sharing off; "Got it" dismisses. Sharing is already on.

4. **About** (`AboutView.swift`) — `#if BETA` section with the opt-out toggle (default ON) and
   a one-line "Beta only — never in the App Store build" caption.

5. **Scan flow** (`ContentView.swift` `.ready` case / `PostScanView`) — when `shareEnabled`, present
   `BetaFeedbackPrompt` after the result renders. Pull `label`, `ocrText`, `summary`, and the
   captured/ isolated `UIImage` from `ScanModel`'s `.ready` state; corrections come from the
   override stores touched this session.

## Capabilities / Info.plist

- No new entitlements. `MFMailComposeViewController` needs no permission.
- The share-sheet fallback needs nothing extra.
- Do **not** add any network entitlement — there is no network code; mail/share hand off to
  the OS. This keeps the Release build's "no data" claim trivially auditable.

## Inbox hygiene

"Always-prompt" on an active cohort can mean many emails. Suggested Gmail filter:
`subject:"Pocketbud beta — scan feedback"` → label `pocketbud-beta`, skip inbox, mark important.
If the cohort grows past ~10–15 active testers, revisit CloudKit (scales without inbox load);
not building it now.

## Removal at ship (checklist)

- [ ] Final App Store archive uses **Release** config (no `BETA`) → feature compiles out.
- [ ] §9 proxy smoke test on the Release build shows **zero** network traffic.
- [ ] App Privacy label stays **Data Not Collected**; privacy policy unchanged.
- [ ] (Optional, post-beta) delete the `#if BETA` files + `project.yml` Beta config once done.

## Test notes

- `canUseMail` false on Simulator → exercise the share-sheet fallback path there.
- Unit-test `ScanFeedback` JSON encoding (stable keys, photo excluded from JSON).
- Per `work-sequentially-on-device-code`: edit → build → verify → commit per file; the FM/
  camera paths need a real AI-capable device, but the feedback plumbing builds in the sim.
