# Software Architecture: HighNotes (iOS, on-device)

**Version:** 1.0
**Last Updated:** 2026-05-27
**Author:** Nick DeMarco with Claude (AI assist)
**Status:** Living — reflects the device-tested v1 spike
**Supersedes:** `docs/legacy/SAD-v0.1.md` (PWA + Supabase — dead architecture)
**PRD:** [`PRD-v1.md`](./PRD-v1.md) · **UXD:** [`UXD-v1.md`](./UXD-v1.md)

---

## 1. System overview

A single native iOS app. All processing — OCR, structured extraction, summary
generation, interpretation, persistence — happens **on-device**. There is no
server, no account, no analytics SDK. The app makes **no network calls itself**;
the only egress is the user tapping an external link, which hands off to Safari.

Two Apple on-device ML systems do the heavy lifting:
- **Vision / VisionKit** — live text + barcode recognition (DataScanner) and
  still-image OCR (`VNRecognizeTextRequest` / `VNDetectBarcodesRequest`).
- **Foundation Models** — `@Generable` structured extraction and free-form
  summary generation via `LanguageModelSession`.

Everything between those two — noise cleanup, field detection, classification,
safety validation, corrections — is **deterministic Swift**, which is where the
trust and testability live.

### 1.1 Key architectural decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Platform | **Native iOS 26+, SwiftUI** | Foundation Models `@Generable` is iOS 26+; on-device removes the entire cloud-cost/privacy/policy surface |
| 2 | Backend | **None** | "100% on-device" is a load-bearing product claim |
| 3 | Extraction | **Two-pass FM** (`LabelMetadata` + `LabelChemistry`) | A single combined `@Generable` schema overran the 4096-token context; splitting halves per-call schema reflection |
| 4 | Live capture | **VisionKit `DataScannerViewController`** | One component for live OCR + barcodes; feeds the field-detection chips |
| 5 | Final capture | **`DataScannerViewController.capturePhoto()` → still OCR** | High-res still OCRs far cleaner than live preview frames — the biggest quality lever |
| 6 | "Right thing?" signal | **Content (field chips), not geometry** | Document/rectangle detection empirically fails on labels fused to packaging |
| 7 | Noise handling | **Deterministic `OCRPreprocessor`**, not prompt | The model is conservative under noise; deterministic cleanup removes ambiguity and saves context tokens |
| 8 | Strain interpretation | **On-device knowledge base**, not FM | Zero hallucination risk, no network; marker > lineage > unknown |
| 9 | Corrections | **Local JSON override store** behind a protocol | User corrections persist and outrank inference; migratable to SwiftData |
| 10 | Safety | **Layered**: P6 regex + regen, hallucination guard, sanity checker, Apple guardrail | Defense in depth; never fabricate, never make medical claims |
| 11 | Testability | **Protocol seams** for FM/availability/store | Lets the pipeline be unit-tested without invoking FM |
| 12 | Persistence | **JSON file in Documents** (overrides); `@AppStorage` (onboarding flag) | SwiftData deferred until the data model grows (journaling) |

### 1.2 Technology stack

| Layer | Technology |
|---|---|
| UI | SwiftUI, `@Observable`, `NavigationStack` |
| Live capture | VisionKit `DataScannerViewController` |
| Still OCR / barcodes | Vision (`VNRecognizeTextRequest`, `VNDetectBarcodesRequest`) |
| Structured extraction / summary | FoundationModels (`@Generable`, `LanguageModelSession`) |
| Persistence | Foundation `Codable` → JSON (Documents); `@AppStorage` |
| Project gen | xcodegen (`project.yml`) |
| Tests | swift-testing (`@Test`/`@Suite`), 199 tests |

---

## 2. The pipeline (state machine)

`ScanModel` (`@MainActor @Observable`) drives a single-screen state machine:

```
idle(availability)
  → scanning ──(live OCR feeds field chips; auto- or manual-confirm)──┐
  → capturing  (high-res capturePhoto → still OCR)                     │
  → previewing(ocr, qrCodes)   (user confirms or re-scans) ───────────┘
  → parsing(ocr)
  → sanityChecking(label)
  → summarizing(label)
  → ready(label, summary?, sanityWarning?, strainInsight?)
  → failed(message)
```

Notes:
- The **sanity check no longer blocks**. A failed rule rides through to `.ready`
  as `sanityWarning` (rendered as a banner). The hallucination guard is the
  backstop against bad summaries.
- **`strainInsight`** is computed deterministically in the pipeline (override →
  marker → lineage) and threaded into both `.ready` and the summary prompt.
- The auto-capture debounce (~1s of all-fields-detected) is the stability gate.
- The `.capturing` task is **race-guarded**: if the user backs out, the in-flight
  capture won't clobber the new phase.

### 2.1 Data flow

```
Camera ──DataScanner──> live OCR text ──> FieldDetector ──> chips / capture gate
                                   │
                      confirmCapture│ (manual tap or auto-fire)
                                   ▼
        capturePhoto() ──> UIImage ──> StaticImageOCR ──> ocrText + qrCodes
                                   │  (fallback: live OCR)
                                   ▼
                          OCRPreprocessor.clean
                                   ▼
            ExtractionService (2 passes) ──> LabelMetadata + LabelChemistry
                                   ▼
                          CannabisLabel (composed, flat)
                            ├─ post-fixes (THC swaps, strain name)
                            ├─ LabelSanityChecker ──> warning?
                            ├─ StrainKnowledgeBase(+overrides) ──> StrainInsight
                            └─ SummaryService ──> SummaryOutcome
                                   │   (P6 regen → hallucination guard → fallback)
                                   ▼
                                 .ready  ──> PostScanView
```

---

## 3. Components

### 3.1 Models
- **`CannabisLabel`** — the flat, consumer-facing struct. **Not `@Generable`**;
  composed from the two extraction passes. Carries regulatory derivations
  (`computedTotalThc`, `computedTotalCbd`, `chemotype`, `isHighPotency`) and the
  post-fix `fixSwappedThcFields()`.
- **`LabelMetadata` / `LabelChemistry`** — the two `@Generable` extraction
  schemas (each focused, to fit the context window). `ProductType` enum.
- **`LabelSanityChecker`** — product-type-aware OOD rules → `.ok` /
  `.verifyHint(reason)`. Total-THC formula check is ordered first (most
  diagnostic).

### 3.2 Services
- **`ExtractionService`** (actor) — two warmed `LanguageModelSession`s (metadata,
  chemistry); `extract()` runs both and composes. Debug
  `extractWithCustomInstructions` powers the Prompt Lab.
- **`SummaryService`** (actor) — FM summary with the P6 regex denylist +
  ≤2 regenerations, the **hallucination guard**
  (`summaryMentionsHallucinatedPercentages`), and a deterministic
  `buildFallback` that leads with strain character. Carries the terpene **aroma**
  table.
- **`OCRPreprocessor`** — per-line scoped % fixes, terpene/cannabinoid name
  fixes, regulatory **boilerplate stripping**, and line **dedup**.
- **`FieldDetector`** — presence checks (license, Metrc, potency, terpenes, QR)
  → drives chips + the capture threshold (≥3 of 5).
- **`StrainKnowledgeBase`** — printed-marker detection, name-lineage table
  (→ lean), lineage flavor/character table, and the `StrainInsight` resolver.
- **`StrainNameFixer`** — replaces strain names that are chemical fragments
  (e.g. "Limonene", "Beicaropa") with the first plausible OCR line.
- **`StrainOverrideStore`** — `StrainOverrideStoring` protocol with a
  file-backed JSON impl (Documents) + in-memory impl for tests. User correction
  outranks inference.
- **`ProductLinks`** — URL detection from QR payloads (uppercase-scheme tolerant)
  + cultivator web search.
- **`StaticImageOCR`** — Vision still OCR with auto-orientation (tries multiple
  orientations, picks the densest) + barcode pass. Throws on total failure.
- **`AvailabilityGate`** — maps `SystemLanguageModel.availability` to a
  product-shaped `FMAvailability`.
- **`PipelineProtocols`** — `LabelExtracting`, `LabelSummarizing`,
  `AvailabilityProviding` seams; production conformances + `DefaultAvailabilityProvider`.

### 3.3 Views
- **`RootView` / `OnboardingView`** — first-run gate (`@AppStorage`).
- **`ContentView`** — phase dispatcher.
- **`ScanningView`** + `DataScannerView` + `ScannerController` — live capture,
  viewfinder, chips, shutter (countdown ring), high-res photo bridge.
- **`PreviewView`** — captured image + chips + OCR + Process/Re-scan.
- **`PostScanView`** — result: header, verify banner, high-potency warning,
  **Profile card** (strain insight + inline editor), AI-summary hero, chips,
  **Learn more** links, disclaimer, source data.
- **`PromptLabView`** (Debug) — prompt iteration with A/B baseline.
- **`Brand.swift`** — centralized HighNotes visual system.

---

## 4. Safety architecture (defense in depth)

1. **Deterministic preprocessing** removes noise before the model sees it.
2. **Two-pass extraction** keeps each call within context (no truncation/failure).
3. **Post-fixes** correct the model's recurring field-assignment errors.
4. **Sanity checker** flags out-of-distribution values (non-blocking banner).
5. **P6 regex validator** (+ ≤2 regenerations) blocks medical/dosing/2nd-person
   language in AI text.
6. **Hallucination guard** rejects any AI percentage not in the parsed label →
   grounded deterministic fallback.
7. **Apple's built-in FM guardrail** is the outer ceiling; on `guardrailViolation`
   the pipeline degrades to the grounded fallback.
8. **Never fabricate** — when chemistry is absent, the result leans on
   name-derived character and says so honestly.

---

## 5. Persistence & privacy

- **Strain overrides** → `strain-overrides.json` in the app's Documents
  directory (Codable). Keyed by normalized strain name.
- **Onboarding flag** → `@AppStorage("highnotes.hasSeenWelcome.v1")`.
- **Canary assets** → bundled `validation/` folder (Debug fixture path).
- No PII, no scan history persisted yet (journaling deferred). Camera-only
  permission (`NSCameraUsageDescription`).

---

## 6. Build, signing, test

- **xcodegen** generates `weedlabel.xcodeproj` from `project.yml`.
  `DEVELOPMENT_TEAM: 5VPR237YHV` is set in `settings.base` so regens preserve
  device signing (previously a recurring "signing issue").
- **Portrait-locked** (`UISupportedInterfaceOrientations: Portrait`).
- **Tests:** 199 across 11 suites, all deterministic (FM is mocked via the
  protocol seams). FM works in the iOS-26 Simulator; Vision still-OCR and
  `capturePhoto()` are device-only, so those paths are exercised on hardware and
  the Simulator uses the bundled OCR fixture (`-AutoRunCanary`).

### 6.1 Debug-only surface (remove before App Store)
- `PromptLabView.swift` + the `#if DEBUG` button/sheet wiring in `ContentView`.
- `ScanModel.runBundledCanary()` / `runBundledCanaryLiveOCR()` + launch args.
- `extractWithCustomInstructions` / `summarizeWithCustomInstructions`.
- `CannabisLabel.diagnosticJSON`, `[CANARY]` logging.

---

## 7. Known technical risks / debt

- **Strain-name vs lot-code** mis-pick (see PRD §7).
- **`StaticImageOCR` is Simulator-incompatible** ("Could not create inference
  context") — by design we fixture in the Simulator.
- **Override store is unbounded JSON** — fine at current scale; revisit with
  SwiftData when journaling adds volume.
- **Repo/target still named `weedlabel`** while the product is HighNotes.
