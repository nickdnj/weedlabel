import Foundation
import SwiftUI
import UIKit

// ScanModel — the spike's state machine. Drives the single-screen flow:
//   idle → scanning → parsing → sanity → summarizing → complete
//                                ↘ verifyHint (suppress AI)
//   Any error → failed
// The pipeline is sequential per the v1 eng spec.

#if DEBUG
@inline(__always)
private func canaryLog(_ message: String) {
    print("[CANARY] \(message)")
}
#endif

@Observable
@MainActor
final class ScanModel {
    enum Phase {
        case idle(availability: FMAvailability)
        case scanning
        case capturing
        case previewing(ocrText: String, qrCodes: [String])
        case parsing(rawOcrText: String)
        case sanityChecking(label: CannabisLabel)
        case summarizing(label: CannabisLabel)
        /// Terminal success-ish state. `sanityWarning` is non-nil when the
        /// sanity checker found a problem — the UI surfaces it as a banner
        /// on the result screen but doesn't block the AI summary (the
        /// hallucination guard in SummaryService is the safety net against
        /// fake summaries on bad data). `strainInsight` is the deterministic
        /// sativa/indica/hybrid read derived on-device from the name + label
        /// marker (no FM, no hallucination risk).
        case ready(label: CannabisLabel, summary: SummaryOutcome?, sanityWarning: String?, strainInsight: StrainInsight?)
        case failed(message: String)
    }

    var phase: Phase {
        didSet {
            #if DEBUG
            canaryLog("phase → \(phase.diagnosticLabel)")
            #endif
        }
    }

    /// Live OCR snapshot from the running DataScannerView. Updated on every
    /// recognition event. When the user taps Capture, this is the payload
    /// that moves into the .previewing phase.
    private(set) var lastSeenOcr: String = ""
    private(set) var lastSeenQRs: [String] = []
    /// The high-res still captured at confirm time, shown on the preview screen.
    private(set) var capturedImage: UIImage?
    /// Bridge to the live scanner for high-res photo capture. Passed to
    /// DataScannerView, which populates its weak controller reference.
    let scannerController = ScannerController()
    /// Derived field-presence set; UI reads this to render the chip row and
    /// to decide whether to enable the Capture button.
    var detectedFields: Set<DetectedField> {
        FieldDetector.detect(ocrText: lastSeenOcr, qrCodes: lastSeenQRs)
    }
    var canCapture: Bool {
        FieldDetector.meetsCaptureThreshold(detectedFields)
    }
    var allFieldsDetected: Bool {
        detectedFields.count == DetectedField.allCases.count
    }
    /// True while the auto-capture debounce timer is running. UI uses this to
    /// render the countdown ring around the shutter button.
    private(set) var isAutoCapturePending: Bool = false
    /// Debounce window before auto-firing the shutter once all fields are
    /// detected. Long enough to ride out brief OCR flicker, short enough to
    /// feel responsive. Exposed for UI animation timing.
    static let autoCaptureDebounceSeconds: Double = 1.0

    private let extraction: LabelExtracting
    private let summary: LabelSummarizing
    private let availability: AvailabilityProviding
    private let strainOverrides: StrainOverrideStoring
    private let productTypeOverrides: ProductTypeOverrideStoring
    private let nameOverrides: StrainNameOverrideStoring
    private let logStore: LogStoring
    private var pipelineTask: Task<Void, Never>?
    private var autoCaptureTask: Task<Void, Never>?

    init(
        extraction: LabelExtracting = ExtractionService(),
        summary: LabelSummarizing = SummaryService(),
        availability: AvailabilityProviding = DefaultAvailabilityProvider(),
        strainOverrides: StrainOverrideStoring = FileStrainOverrideStore(),
        productTypeOverrides: ProductTypeOverrideStoring = FileProductTypeOverrideStore(),
        nameOverrides: StrainNameOverrideStoring = FileStrainNameOverrideStore(),
        logStore: LogStoring = FileLogStore()
    ) {
        self.extraction = extraction
        self.summary = summary
        self.availability = availability
        self.strainOverrides = strainOverrides
        self.productTypeOverrides = productTypeOverrides
        self.nameOverrides = nameOverrides
        self.logStore = logStore
        self.phase = .idle(availability: availability.current())
    }

    // MARK: - Lifecycle

    func refreshAvailability() {
        if case .idle = phase {
            phase = .idle(availability: availability.current())
        }
    }

    func startScan() {
        cancelAutoCaptureCountdown()
        lastSeenOcr = ""
        lastSeenQRs = []
        capturedImage = nil
        phase = .scanning
        let extraction = self.extraction
        let summary = self.summary
        Task.detached(priority: .userInitiated) {
            await extraction.warm()
            await summary.warm()
        }
    }

    // MARK: - Live scanner updates

    /// Called by DataScannerView on every recognition event. We stash the
    /// snapshot; the UI reacts via `detectedFields` / `canCapture` computed
    /// properties. Also drives auto-capture: when all 5 fields are detected
    /// and remain detected for `autoCaptureDebounceSeconds`, the shutter
    /// fires on its own.
    func handleTextUpdate(ocr: String, qrCodes: [String]) {
        guard case .scanning = phase else { return }
        lastSeenOcr = ocr
        lastSeenQRs = qrCodes

        if allFieldsDetected {
            startAutoCaptureCountdown()
        } else {
            cancelAutoCaptureCountdown()
        }
    }

    /// User tapped the shutter, or the auto-capture timer fired. Capture a
    /// high-resolution still and OCR THAT (much cleaner than the live preview
    /// frames), then move to .previewing. Falls back to the live OCR snapshot
    /// if the still capture or its OCR fails (e.g. in the simulator).
    func confirmCapture() {
        guard case .scanning = phase else { return }
        cancelAutoCaptureCountdown()
        let liveOcr = lastSeenOcr.trimmingCharacters(in: .whitespacesAndNewlines)
        let liveQRs = lastSeenQRs
        phase = .capturing
        Task { [weak self] in
            guard let self else { return }

            // High-res capture + OCR.
            var image: UIImage?
            var stillResult: StaticImageOCR.Result?
            if let captured = await self.scannerController.capturePhoto() {
                image = captured
                stillResult = try? await StaticImageOCR.recognize(in: captured)
            }

            // If the user backed out (rescan/cancel) while we were capturing,
            // don't clobber the new phase.
            guard case .capturing = self.phase else { return }

            if let image { self.capturedImage = image }
            if let result = stillResult {
                let text = result.ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    #if DEBUG
                    canaryLog("High-res capture OCR — \(text.count) chars, qrs=\(result.qrCodes.count)")
                    #endif
                    // Merge QRs from the still with any seen live (the still
                    // pass is authoritative but live may have caught more).
                    let qrs = (result.qrCodes + liveQRs).reduced
                    self.phase = .previewing(ocrText: text, qrCodes: qrs)
                    return
                }
            }

            // Fallback: use the live preview OCR snapshot.
            #if DEBUG
            canaryLog("High-res capture unavailable — falling back to live OCR")
            #endif
            guard !liveOcr.isEmpty else {
                self.phase = .failed(message: "No text detected. Hold the label inside the frame.")
                return
            }
            self.phase = .previewing(ocrText: liveOcr, qrCodes: liveQRs)
        }
    }

    /// User accepted the preview — run the FM pipeline.
    func processCapture() {
        guard case .previewing(let ocr, let qrs) = phase else { return }
        phase = .parsing(rawOcrText: ocr)
        runPipeline(ocr: ocr, qrCodes: qrs)
    }

    /// Import a photo from the user's library and run it through the same path
    /// as a high-res capture: OCR the still, then show the confirm screen so the
    /// user can verify the text before extraction. OCR uses Vision, so this
    /// needs a real device (Vision still-OCR is unreliable in the Simulator).
    func importPickedImage(_ image: UIImage) {
        cancelAutoCaptureCountdown()
        pipelineTask?.cancel()
        lastSeenOcr = ""
        lastSeenQRs = []
        capturedImage = image
        phase = .capturing
        Task { [weak self] in
            guard let self else { return }
            let result = try? await StaticImageOCR.recognize(in: image)
            // Bail if the user navigated away while OCR was running.
            guard case .capturing = self.phase else { return }
            if let result {
                let text = result.ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    self.phase = .previewing(ocrText: text, qrCodes: result.qrCodes.reduced)
                    return
                }
            }
            self.phase = .failed(message: "No label text found in that photo. Try one where the label fills the frame.")
        }
    }

    /// User rejected the preview — return to scanning.
    func rescan() {
        cancelAutoCaptureCountdown()
        lastSeenOcr = ""
        lastSeenQRs = []
        capturedImage = nil
        phase = .scanning
    }

    // MARK: - Auto-capture

    private func startAutoCaptureCountdown() {
        guard autoCaptureTask == nil else { return }
        isAutoCapturePending = true
        autoCaptureTask = Task { [weak self] in
            let delay = UInt64(ScanModel.autoCaptureDebounceSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard let self else { return }
            if Task.isCancelled {
                self.isAutoCapturePending = false
                self.autoCaptureTask = nil
                return
            }
            // Re-verify state — the snapshot might have changed during sleep.
            guard case .scanning = self.phase, self.allFieldsDetected else {
                self.isAutoCapturePending = false
                self.autoCaptureTask = nil
                return
            }
            self.autoCaptureTask = nil
            self.isAutoCapturePending = false
            self.confirmCapture()
        }
    }

    private func cancelAutoCaptureCountdown() {
        autoCaptureTask?.cancel()
        autoCaptureTask = nil
        isAutoCapturePending = false
    }

#if DEBUG
    /// Debug-only fixture path: feed the canary's pre-captured OCR text directly
    /// into the FM pipeline. Useful in Simulator where Vision OCR can fail with
    /// "Could not create inference context" but FM itself is available.
    func runBundledCanary() {
        canaryLog("runBundledCanary(fixture) — availability=\(availability.current())")
        guard let url = Bundle.main.url(
            forResource: "zips-blue-candy-rain.ocr",
            withExtension: "txt",
            subdirectory: "validation"
        ) else {
            canaryLog("Fixture OCR file not found in bundle")
            phase = .failed(message: "Canary fixture missing from bundle")
            return
        }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            canaryLog("Fixture loaded — text=\(text.count)chars")
            canaryLog("OCR text begin ===\n\(text)\n=== OCR text end")
            // The macOS-Vision capture authoritatively decoded the QR as the Metrc tag.
            let qrs = ["1A4110300003C8D000041730"]
            phase = .parsing(rawOcrText: text)
            runPipeline(ocr: text, qrCodes: qrs)
        } catch {
            canaryLog("Fixture load FAILED: \(error)")
            phase = .failed(message: "Fixture load failed: \(error.localizedDescription)")
        }
    }

    /// Debug-only live-OCR path: load the bundled canary JPEG, run Vision OCR
    /// against it, then feed the pipeline. Works on device; may fail in some
    /// simulators due to Vision/Neural-Engine constraints.
    func runBundledCanaryLiveOCR() {
        canaryLog("runBundledCanaryLiveOCR() — availability=\(availability.current())")
        phase = .parsing(rawOcrText: "")
        Task { [weak self] in
            guard let self else { return }
            do {
                canaryLog("Live OCR start — loading bundled canary JPEG")
                let result = try await StaticImageOCR.bundled(
                    named: "zips-blue-candy-rain",
                    withExtension: "jpeg"
                )
                canaryLog("Live OCR done — text=\(result.ocrText.count)chars, qrs=\(result.qrCodes.count)")
                canaryLog("OCR text begin ===\n\(result.ocrText)\n=== OCR text end")
                if !result.qrCodes.isEmpty {
                    canaryLog("QR payloads: \(result.qrCodes)")
                }
                self.phase = .parsing(rawOcrText: result.ocrText)
                self.runPipeline(ocr: result.ocrText, qrCodes: result.qrCodes)
            } catch {
                canaryLog("Live OCR FAILED: \(error)")
                self.phase = .failed(message: "Canary live OCR failed: \(error.localizedDescription)")
            }
        }
    }
#endif

    func cancel() {
        cancelAutoCaptureCountdown()
        pipelineTask?.cancel()
        phase = .idle(availability: availability.current())
    }

    // MARK: - Strain classification corrections

    /// Save a user correction for the current product's strain and refresh the
    /// result screen's Profile card in place. Persists so future scans of the
    /// same strain pick it up.
    func setStrainClass(_ lean: StrainLean) {
        guard case .ready(let label, let summary, let warning, _) = phase else { return }
        strainOverrides.setLean(lean, forStrainName: label.strainName)
        let insight = StrainInsight(lean: lean, source: .userOverride)
        phase = .ready(label: label, summary: summary, sanityWarning: warning, strainInsight: insight)
    }

    /// Remove a saved correction for the current strain and fall back to the
    /// marker/lineage inference (or nothing).
    func clearStrainClass() {
        guard case .ready(let label, let summary, let warning, _) = phase else { return }
        strainOverrides.removeOverride(forStrainName: label.strainName)
        let insight = StrainKnowledgeBase.insight(strainName: label.strainName, ocrText: lastSeenOcr)
        phase = .ready(label: label, summary: summary, sanityWarning: warning, strainInsight: insight)
    }

    // MARK: - Product-type correction

    /// Apply a user correction to the product type (the FM occasionally mis-reads
    /// e.g. a flower package as an edible) and re-run the productType-aware
    /// sanity check, since the cannabinoid ceilings differ by type. In-session
    /// only — the AI summary isn't regenerated.
    func setProductType(_ type: ProductType) {
        guard case .ready(let label, let summary, _, let insight) = phase else { return }
        productTypeOverrides.setProductType(type, forStrainName: label.strainName)
        var updated = label
        updated.productType = type
        let verdict = LabelSanityChecker.check(updated)
        let warning: String?
        if case .verifyHint(let reason) = verdict { warning = reason } else { warning = nil }
        phase = .ready(label: updated, summary: summary, sanityWarning: warning, strainInsight: insight)
    }

    // MARK: - Strain-name correction

    /// Apply a user correction to the strain name (the model can mis-read names
    /// on worst-case OCR). Persists keyed by the *extracted* name, so future
    /// scans that produce the same misread auto-correct. In-session it updates
    /// the displayed name; the existing strain insight and product type stand.
    func setStrainName(_ newName: String) {
        guard case .ready(let label, let summary, let warning, let insight) = phase else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != label.strainName else { return }
        nameOverrides.setCorrectedName(trimmed, forExtractedName: label.strainName)
        var updated = label
        updated.strainName = trimmed
        phase = .ready(label: updated, summary: summary, sanityWarning: warning, strainInsight: insight)
    }

    // MARK: - Log Book

    /// Save the current result to the Log Book ("your HighNotes"), then return
    /// to idle. Stores the label + the summary text as shown + the strain lean;
    /// the user adds a note/rating later in the entry detail.
    func saveToLogBook() {
        guard case .ready(let label, let summary, _, let insight) = phase else { return }
        let text = summary?.text ?? SummaryService.buildFallback(label, strainInsight: insight)
        // Persist the scanned/imported image alongside the entry (deleted with it
        // in FileLogStore.delete). Keyed by the entry id so the two stay matched.
        let id = UUID()
        let imageFilename = capturedImage.flatMap { LogImageStore.save($0, id: id) }
        let entry = LogEntry(
            id: id,
            label: label,
            summaryText: text,
            summaryDidFallback: summary?.didFallback ?? true,
            strainLean: insight?.lean,
            strainSourceNote: insight?.sourceNote,
            imageFilename: imageFilename
        )
        logStore.add(entry)
        cancel()
    }

    // MARK: - Local data

    /// Wipe all locally-saved corrections (strain lean, product type, and name).
    /// Backs the "Clear local data" action. Strain overrides are cleared through
    /// the existing protocol so this stays decoupled from that store's internals.
    func clearLocalData() {
        for override in strainOverrides.allOverrides() {
            strainOverrides.removeOverride(forStrainName: override.displayName)
        }
        productTypeOverrides.removeAll()
        nameOverrides.removeAll()
    }

    // MARK: - Capture handoff

    func handleCapture(ocr: String, qrCodes: [String]) {
        let trimmed = ocr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            phase = .failed(message: "No text detected. Try again with the label flat in frame.")
            return
        }

        phase = .parsing(rawOcrText: trimmed)
        runPipeline(ocr: trimmed, qrCodes: qrCodes)
    }

    private func runPipeline(ocr: String, qrCodes: [String]) {
        pipelineTask?.cancel()
        pipelineTask = Task { [weak self] in
            guard let self else { return }

            // 1. Extract via FM Generable
            let label: CannabisLabel
            do {
                #if DEBUG
                canaryLog("FM extract start")
                #endif
                let extracted = try await self.extraction.extract(rawOcrText: ocr)
                // Merge in QR codes captured by VisionKit (FM doesn't see them)
                var withQRs = extracted
                withQRs.qrCodes = (extracted.qrCodes + qrCodes).reduced
                // Post-fix: model frequently mis-assigns Total THC into
                // delta9thc on labels where they appear adjacent in OCR.
                withQRs.fixSwappedThcFields()
                // Post-fix: null out impossible magnitudes (e.g. a batch code
                // mis-parsed as "120925% cannabinoids") rather than display them.
                withQRs.clampImplausibleValues()
                // Post-fix: re-read terpenes straight from the OCR — the model
                // mis-slots them under dense panels (and pinene is split across
                // Alpha-/Beta-Pinene lines). Deterministic; the values are
                // unambiguous on the label.
                withQRs.reconcileTerpenes(ocrText: ocr)
                // Post-fix: model sometimes picks a terpene/cannabinoid name
                // as strainName (e.g. "Limonene"). Override with first
                // plausible OCR line when this happens.
                let fixedStrain = StrainNameFixer.fix(strain: withQRs.strainName, cultivator: withQRs.cultivator, ocrText: ocr)
                if fixedStrain.didFix {
                    #if DEBUG
                    canaryLog("Strain post-fix: '\(withQRs.strainName)' → '\(fixedStrain.strain)'")
                    #endif
                    withQRs.strainName = fixedStrain.strain
                }
                // Apply a saved name correction (chained, so re-edits compose),
                // keyed by the extracted name — fixes worst-case OCR names the
                // model can't reassemble. Done first so the corrected name drives
                // the product-type and strain-lean lookups below.
                let resolvedName = self.nameOverrides.resolve(extractedName: withQRs.strainName)
                if resolvedName != withQRs.strainName {
                    #if DEBUG
                    canaryLog("Name override applied: '\(withQRs.strainName)' → '\(resolvedName)'")
                    #endif
                    withQRs.strainName = resolvedName
                }
                // Deterministic product-type correction from explicit label
                // wording (e.g. "Inhalable Product" → not an edible), overriding
                // a name-biased FM guess. A saved user override still wins below.
                if let inferredType = ProductTypeInference.infer(ocrText: ocr), inferredType != withQRs.productType {
                    #if DEBUG
                    canaryLog("Product-type inference: \(withQRs.productType.storageKey) → \(inferredType.storageKey) (from label text)")
                    #endif
                    withQRs.productType = inferredType
                }
                // Apply a saved product-type correction for this strain, if any,
                // so the user's fix survives across future scans.
                if let savedType = self.productTypeOverrides.productType(forStrainName: withQRs.strainName) {
                    #if DEBUG
                    if savedType != withQRs.productType {
                        canaryLog("Product-type override applied: \(withQRs.productType.storageKey) → \(savedType.storageKey)")
                    }
                    #endif
                    withQRs.productType = savedType
                }
                label = withQRs
                #if DEBUG
                canaryLog("FM extract OK")
                canaryLog("Parsed label JSON ===\n\(label.diagnosticJSON)\n=== Parsed label JSON end")
                #endif
            } catch is CancellationError {
                return
            } catch {
                #if DEBUG
                canaryLog("FM extract FAILED: \(error)")
                #endif
                self.phase = .failed(message: "Couldn't read this label. \(error.localizedDescription)")
                return
            }
            if Task.isCancelled { return }

            self.phase = .sanityChecking(label: label)

            // 2. Sanity check — does NOT block summary. Reason (if any) is
            //    surfaced as a banner on the result screen. The hallucination
            //    guard in SummaryService is the backstop against fake content
            //    on bad data.
            let verdict = LabelSanityChecker.check(label)
            let sanityWarning: String? = {
                if case .verifyHint(let reason) = verdict { return reason }
                return nil
            }()
            #if DEBUG
            canaryLog("Sanity verdict: \(sanityWarning.map { "warning — \($0)" } ?? "ok")")
            #endif
            if Task.isCancelled { return }

            // 2b. Deterministic strain insight (sativa/indica/hybrid). Computed
            //     on-device from a saved user override, the label marker, or
            //     name-based lineage — no FM, so it's always trustworthy and
            //     free of hallucination risk.
            let savedOverride = self.strainOverrides.lean(forStrainName: label.strainName)
            let strainInsight = StrainKnowledgeBase.insight(
                strainName: label.strainName,
                ocrText: ocr,
                override: savedOverride
            )
            #if DEBUG
            if let strainInsight {
                canaryLog("Strain insight: \(strainInsight.headline) [\(strainInsight.sourceNote)]")
            }
            #endif

            // 3. Summarize via FM, IF availability is OK
            let currentAvailability = self.availability.current()
            guard currentAvailability == .available else {
                #if DEBUG
                canaryLog("Summary skipped — availability=\(currentAvailability)")
                #endif
                self.phase = .ready(label: label, summary: nil, sanityWarning: sanityWarning, strainInsight: strainInsight)
                return
            }

            self.phase = .summarizing(label: label)
            do {
                #if DEBUG
                canaryLog("FM summarize start")
                #endif
                let outcome = try await self.summary.summarize(label, strainInsight: strainInsight)
                if Task.isCancelled { return }
                #if DEBUG
                canaryLog("FM summarize OK — fallback=\(outcome.didFallback), text=\(outcome.text)")
                #endif
                self.phase = .ready(label: label, summary: outcome, sanityWarning: sanityWarning, strainInsight: strainInsight)
            } catch is CancellationError {
                return
            } catch {
                // Summary failed — still surface the parsed label
                #if DEBUG
                canaryLog("FM summarize FAILED: \(error)")
                #endif
                self.phase = .ready(label: label, summary: nil, sanityWarning: sanityWarning, strainInsight: strainInsight)
            }
        }
    }
}

#if DEBUG
extension ScanModel.Phase {
    var diagnosticLabel: String {
        switch self {
        case .idle(let a): return "idle(availability=\(a))"
        case .scanning: return "scanning"
        case .capturing: return "capturing"
        case .previewing(let t, let q): return "previewing(ocr=\(t.count)chars, qrs=\(q.count))"
        case .parsing(let t): return "parsing(ocr=\(t.count)chars)"
        case .sanityChecking: return "sanityChecking"
        case .summarizing: return "summarizing"
        case .ready(_, let s, let w, let insight):
            let summaryDesc: String
            if let s { summaryDesc = "summary=\(s.didFallback ? "fallback" : "ai")" }
            else { summaryDesc = "summary=none" }
            var parts = [summaryDesc]
            if let w { parts.append("warn=\(w)") }
            if let insight { parts.append("strain=\(insight.lean.rawValue)") }
            return "ready(\(parts.joined(separator: ", ")))"
        case .failed(let m): return "failed(\(m))"
        }
    }
}

extension CannabisLabel {
    /// JSON-ish diagnostic dump for canary logs. Not for production use.
    var diagnosticJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        struct Wire: Encodable {
            let strainName: String
            let cultivator: String
            let licenseNumber: String?
            let metrcTag: String?
            let netWeight: String?
            let harvestDate: String?
            let expirationDate: String?
            let productType: String
            let cannabinoids: [String: Double?]
            let terpenes: [String: Double?]
            let qrCodes: [String]
        }
        let wire = Wire(
            strainName: strainName,
            cultivator: cultivator,
            licenseNumber: licenseNumber,
            metrcTag: metrcTag,
            netWeight: netWeight,
            harvestDate: harvestDate,
            expirationDate: expirationDate,
            productType: String(describing: productType),
            cannabinoids: [
                "thca": thca,
                "delta9thc": delta9thc,
                "cbd": cbd,
                "cbg": cbg,
                "totalCannabinoids": totalCannabinoids,
                "totalThc": totalThc,
                "totalCbd": totalCbd
            ],
            terpenes: [
                "myrcene": myrcene,
                "limonene": limonene,
                "linalool": linalool,
                "betaCaryophyllene": betaCaryophyllene,
                "pinene": pinene,
                "humulene": humulene,
                "total": totalTerpenes
            ],
            qrCodes: qrCodes
        )
        if let data = try? encoder.encode(wire), let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "<encode failed>"
    }
}
#endif

// Small helper to dedupe QR strings while preserving order.
private extension Array where Element == String {
    var reduced: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for s in self {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !seen.contains(trimmed) {
                seen.insert(trimmed)
                out.append(trimmed)
            }
        }
        return out
    }
}
