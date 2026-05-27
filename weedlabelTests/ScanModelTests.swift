import Testing
import Foundation
@testable import weedlabel

// ScanModel pipeline tests — verify the deterministic post-extraction forks
// (sanity-fail, availability gate, summary success/failure) without
// invoking Foundation Models. Mocks injected via the LabelExtracting /
// LabelSummarizing / AvailabilityProviding protocols.

@Suite("ScanModel pipeline")
@MainActor
struct ScanModelTests {

    // MARK: - Fixtures

    /// A plausible, sanity-check-clean flower label.
    static func cleanFlowerLabel() -> CannabisLabel {
        CannabisLabel(
            strainName: "Test Strain",
            cultivator: "Test Cultivator",
            licenseNumber: "C000999",
            metrcTag: "1A4000000000000000000000",
            netWeight: "3.5g",
            harvestDate: nil,
            expirationDate: nil,
            productType: .flower,
            thca: 22.0, delta9thc: 0.5, cbd: nil, cbg: nil,
            totalCannabinoids: 24.5, totalThc: nil, totalCbd: nil,
            myrcene: 0.5, limonene: 0.4, linalool: 0.2, betaCaryophyllene: 0.3,
            pinene: 0.1, humulene: 0.05, totalTerpenes: 1.55,
            qrCodes: []
        )
    }

    /// A label that should trip LabelSanityChecker (flower with >40% total
    /// cannabinoids — way out of plausible range).
    static func sanityFailFlowerLabel() -> CannabisLabel {
        var l = cleanFlowerLabel()
        l.totalCannabinoids = 99.0
        return l
    }

    // MARK: - Pipeline transitions

    @Test func successPathReachesReadyWithSummary() async throws {
        let model = ScanModel(
            extraction: MockExtractor(result: .success(Self.cleanFlowerLabel())),
            summary: MockSummarizer(result: .success(.ai(text: "fine.", regenerationsTried: 0))),
            availability: MockAvailability(value: .available)
        )
        model.handleCapture(ocr: "fake ocr input", qrCodes: [])
        try await waitForPipeline(model)
        guard case .ready(_, let summary, _, _) = model.phase else {
            Issue.record("expected .ready, got \(model.phase)")
            return
        }
        guard case .ai(let text, _) = summary else {
            Issue.record("expected .ai summary, got \(String(describing: summary))")
            return
        }
        #expect(text == "fine.")
    }

    @Test func saveToLogBookPersistsThenReturnsToIdle() async throws {
        let logStore = InMemoryLogStore()
        let model = ScanModel(
            extraction: MockExtractor(result: .success(Self.cleanFlowerLabel())),
            summary: MockSummarizer(result: .success(.ai(text: "fine.", regenerationsTried: 0))),
            availability: MockAvailability(value: .available),
            logStore: logStore
        )
        model.handleCapture(ocr: "fake ocr input", qrCodes: [])
        try await waitForPipeline(model)
        #expect(logStore.entries().isEmpty) // nothing saved until the user opts in

        model.saveToLogBook()
        let entries = logStore.entries()
        #expect(entries.count == 1)
        #expect(entries.first?.label.strainName == "Test Strain")
        #expect(entries.first?.summaryText == "fine.")
        if case .idle = model.phase {} else {
            Issue.record("expected .idle after save, got \(model.phase)")
        }
    }

    @Test func sanityFailStillRunsSummaryAndPassesWarning() async throws {
        // Behavior changed 2026-05-27: a sanity failure no longer routes to
        // a dead-end verifyHint screen. Instead the pipeline always continues
        // to the AI summary (the hallucination guard is the backstop for bad
        // data) and the sanity reason rides through to .ready as a warning
        // banner the UI surfaces.
        let summarizer = MockSummarizer(result: .success(.ai(text: "fine.", regenerationsTried: 0)))
        let model = ScanModel(
            extraction: MockExtractor(result: .success(Self.sanityFailFlowerLabel())),
            summary: summarizer,
            availability: MockAvailability(value: .available)
        )
        model.handleCapture(ocr: "fake ocr input", qrCodes: [])
        try await waitForPipeline(model)
        guard case .ready(_, let summary, let warning, _) = model.phase else {
            Issue.record("expected .ready, got \(model.phase)")
            return
        }
        #expect(summary != nil)
        #expect(warning != nil, "expected a sanity warning to ride through")
        let summarizeCalls = await summarizer.callCount
        #expect(summarizeCalls == 1, "summary should still be generated on sanity-fail")
    }

    @Test func availabilityGateOffRoutesToReadyWithoutSummary() async throws {
        let summarizer = MockSummarizer(result: .success(.ai(text: "should not run", regenerationsTried: 0)))
        let model = ScanModel(
            extraction: MockExtractor(result: .success(Self.cleanFlowerLabel())),
            summary: summarizer,
            availability: MockAvailability(value: .deviceNotEligible)
        )
        model.handleCapture(ocr: "fake ocr input", qrCodes: [])
        try await waitForPipeline(model)
        guard case .ready(_, let summary, _, _) = model.phase else {
            Issue.record("expected .ready, got \(model.phase)")
            return
        }
        #expect(summary == nil)
        let summarizeCalls = await summarizer.callCount
        #expect(summarizeCalls == 0)
    }

    @Test func extractionFailureRoutesToFailed() async throws {
        struct ExtractFailed: Error {}
        let model = ScanModel(
            extraction: MockExtractor(result: .failure(ExtractFailed())),
            summary: MockSummarizer(result: .success(.ai(text: "x", regenerationsTried: 0))),
            availability: MockAvailability(value: .available)
        )
        model.handleCapture(ocr: "fake ocr input", qrCodes: [])
        try await waitForPipeline(model)
        guard case .failed = model.phase else {
            Issue.record("expected .failed, got \(model.phase)")
            return
        }
    }

    @Test func summaryFailureStillSurfacesParsedLabel() async throws {
        struct SummaryFailed: Error {}
        let model = ScanModel(
            extraction: MockExtractor(result: .success(Self.cleanFlowerLabel())),
            summary: MockSummarizer(result: .failure(SummaryFailed())),
            availability: MockAvailability(value: .available)
        )
        model.handleCapture(ocr: "fake ocr input", qrCodes: [])
        try await waitForPipeline(model)
        guard case .ready(_, let summary, _, _) = model.phase else {
            Issue.record("expected .ready, got \(model.phase)")
            return
        }
        #expect(summary == nil)
    }

    @Test func qrCodesFromVisionKitAreMergedAndDeduped() async throws {
        var label = Self.cleanFlowerLabel()
        // Simulate FM returning one QR; VisionKit captures the same one plus
        // another. Final array should be deduped, preserving order, with both
        // unique values present.
        label.qrCodes = ["FROM_FM"]
        let model = ScanModel(
            extraction: MockExtractor(result: .success(label)),
            summary: MockSummarizer(result: .success(.ai(text: "ok.", regenerationsTried: 0))),
            availability: MockAvailability(value: .available)
        )
        model.handleCapture(ocr: "fake ocr", qrCodes: ["FROM_FM", "FROM_VISIONKIT"])
        try await waitForPipeline(model)
        guard case .ready(let final, _, _, _) = model.phase else {
            Issue.record("expected .ready, got \(model.phase)")
            return
        }
        #expect(final.qrCodes == ["FROM_FM", "FROM_VISIONKIT"])
    }

    @Test func emptyOcrShortCircuitsToFailedBeforeFM() async throws {
        let extractor = MockExtractor(result: .success(Self.cleanFlowerLabel()))
        let model = ScanModel(
            extraction: extractor,
            summary: MockSummarizer(result: .success(.ai(text: "x", regenerationsTried: 0))),
            availability: MockAvailability(value: .available)
        )
        model.handleCapture(ocr: "   \n  ", qrCodes: [])
        // No async wait needed — the guard fires synchronously.
        guard case .failed = model.phase else {
            Issue.record("expected .failed, got \(model.phase)")
            return
        }
        let extractCalls = await extractor.callCount
        #expect(extractCalls == 0)
    }

    // MARK: - Live-scanning preview flow

    @Test func liveScanFlowMovesScanningPreviewingParsingReady() async throws {
        let model = ScanModel(
            extraction: MockExtractor(result: .success(Self.cleanFlowerLabel())),
            summary: MockSummarizer(result: .success(.ai(text: "ok.", regenerationsTried: 0))),
            availability: MockAvailability(value: .available)
        )
        model.startScan()
        guard case .scanning = model.phase else {
            Issue.record("expected .scanning after startScan, got \(model.phase)")
            return
        }
        // Simulate live OCR updates from the DataScannerView.
        model.handleTextUpdate(ocr: "License # C000186\nTHCA: 29.73%\nMyrcene 1.83%", qrCodes: ["1A4123"])
        #expect(model.detectedFields.count >= 3)
        #expect(model.canCapture)
        model.confirmCapture()
        // confirmCapture is now async (high-res capture → OCR, with a fallback
        // to the live OCR when no scanner is attached, as in tests). Wait for
        // it to land in .previewing.
        try await waitForPhase(model) { phase in
            if case .previewing = phase { return true }
            if case .failed = phase { return true }
            return false
        }
        guard case .previewing(let ocr, let qrs) = model.phase else {
            Issue.record("expected .previewing, got \(model.phase)")
            return
        }
        #expect(ocr.contains("THCA"))
        #expect(qrs == ["1A4123"])
        model.processCapture()
        try await waitForPipeline(model)
        guard case .ready = model.phase else {
            Issue.record("expected .ready, got \(model.phase)")
            return
        }
    }

    @Test func confirmCaptureWithEmptyOcrRoutesToFailed() async throws {
        let model = ScanModel(
            extraction: MockExtractor(result: .success(Self.cleanFlowerLabel())),
            summary: MockSummarizer(result: .success(.ai(text: "ok.", regenerationsTried: 0))),
            availability: MockAvailability(value: .available)
        )
        model.startScan()
        model.confirmCapture() // no text update fed yet
        try await waitForPhase(model) { phase in
            if case .failed = phase { return true }
            return false
        }
        guard case .failed = model.phase else {
            Issue.record("expected .failed, got \(model.phase)")
            return
        }
    }

    @Test func rescanFromPreviewingReturnsToScanning() async throws {
        let model = ScanModel(
            extraction: MockExtractor(result: .success(Self.cleanFlowerLabel())),
            summary: MockSummarizer(result: .success(.ai(text: "ok.", regenerationsTried: 0))),
            availability: MockAvailability(value: .available)
        )
        model.startScan()
        model.handleTextUpdate(ocr: "License # C000186\nTHCA: 29.73%\nMyrcene 1.83%", qrCodes: [])
        model.confirmCapture()
        try await waitForPhase(model) { phase in
            if case .previewing = phase { return true }
            return false
        }
        model.rescan()
        guard case .scanning = model.phase else {
            Issue.record("expected .scanning after rescan, got \(model.phase)")
            return
        }
        // After rescan, the snapshot resets.
        #expect(model.lastSeenOcr.isEmpty)
        #expect(model.detectedFields.isEmpty)
    }

    @Test func handleTextUpdateIgnoredOutsideScanning() async throws {
        let model = ScanModel(
            extraction: MockExtractor(result: .success(Self.cleanFlowerLabel())),
            summary: MockSummarizer(result: .success(.ai(text: "ok.", regenerationsTried: 0))),
            availability: MockAvailability(value: .available)
        )
        // Model starts in .idle. Sending text updates should be ignored.
        model.handleTextUpdate(ocr: "License # C000186\nTHCA: 29.73%", qrCodes: [])
        #expect(model.lastSeenOcr.isEmpty)
    }

    // MARK: - Auto-capture

    /// OCR fixture that triggers all 5 DetectedField cases (license, Metrc,
    /// potency, terpenes, QR present).
    private static let allFieldsOcr = """
    License # C000186
    1A4110300003C8D000041730
    THCA: 29.73%
    Myrcene 1.83%
    """
    private static let allFieldsQRs = ["1A4110300003C8D000041730"]

    @Test func allFieldsDetectedSchedulesAutoCapture() async throws {
        let model = ScanModel(
            extraction: MockExtractor(result: .success(Self.cleanFlowerLabel())),
            summary: MockSummarizer(result: .success(.ai(text: "ok.", regenerationsTried: 0))),
            availability: MockAvailability(value: .available)
        )
        model.startScan()
        model.handleTextUpdate(ocr: Self.allFieldsOcr, qrCodes: Self.allFieldsQRs)
        #expect(model.allFieldsDetected)
        #expect(model.isAutoCapturePending)
    }

    @Test func autoCaptureFiresAfterDebounce() async throws {
        let model = ScanModel(
            extraction: MockExtractor(result: .success(Self.cleanFlowerLabel())),
            summary: MockSummarizer(result: .success(.ai(text: "ok.", regenerationsTried: 0))),
            availability: MockAvailability(value: .available)
        )
        model.startScan()
        model.handleTextUpdate(ocr: Self.allFieldsOcr, qrCodes: Self.allFieldsQRs)
        // Wait for the debounce timer to fire and the model to land in
        // .previewing. That's the auto-capture deliverable — the user-facing
        // confirm screen. From there a manual tap on Process would run the FM
        // pipeline; we verify that separately in the live-scan flow test.
        try await waitForPhase(model, predicate: { phase in
            if case .previewing = phase { return true }
            return false
        })
        guard case .previewing = model.phase else {
            Issue.record("expected .previewing after auto-capture, got \(model.phase)")
            return
        }
        #expect(!model.isAutoCapturePending)
    }

    @Test func fieldDropCancelsPendingAutoCapture() async throws {
        let model = ScanModel(
            extraction: MockExtractor(result: .success(Self.cleanFlowerLabel())),
            summary: MockSummarizer(result: .success(.ai(text: "ok.", regenerationsTried: 0))),
            availability: MockAvailability(value: .available)
        )
        model.startScan()
        model.handleTextUpdate(ocr: Self.allFieldsOcr, qrCodes: Self.allFieldsQRs)
        #expect(model.isAutoCapturePending)
        // Drop one field — only license + Metrc remain (no potency keyword).
        model.handleTextUpdate(ocr: "License # C000186\n1A4110300003C8D000041730", qrCodes: [])
        #expect(!model.isAutoCapturePending)
        // Wait past what would have been the auto-capture deadline and confirm
        // we're still in .scanning.
        try await Task.sleep(nanoseconds: UInt64((ScanModel.autoCaptureDebounceSeconds + 0.3) * 1_000_000_000))
        guard case .scanning = model.phase else {
            Issue.record("expected to remain .scanning, got \(model.phase)")
            return
        }
    }

    @Test func cancelScanCancelsPendingAutoCapture() async throws {
        let model = ScanModel(
            extraction: MockExtractor(result: .success(Self.cleanFlowerLabel())),
            summary: MockSummarizer(result: .success(.ai(text: "ok.", regenerationsTried: 0))),
            availability: MockAvailability(value: .available)
        )
        model.startScan()
        model.handleTextUpdate(ocr: Self.allFieldsOcr, qrCodes: Self.allFieldsQRs)
        #expect(model.isAutoCapturePending)
        model.cancel()
        #expect(!model.isAutoCapturePending)
        guard case .idle = model.phase else {
            Issue.record("expected .idle after cancel, got \(model.phase)")
            return
        }
    }

    @Test func manualTapDuringCountdownFiresImmediatelyAndClearsPending() async throws {
        let model = ScanModel(
            extraction: MockExtractor(result: .success(Self.cleanFlowerLabel())),
            summary: MockSummarizer(result: .success(.ai(text: "ok.", regenerationsTried: 0))),
            availability: MockAvailability(value: .available)
        )
        model.startScan()
        model.handleTextUpdate(ocr: Self.allFieldsOcr, qrCodes: Self.allFieldsQRs)
        #expect(model.isAutoCapturePending)
        // User taps shutter before the debounce expires.
        model.confirmCapture()
        // Pending auto-capture is cleared synchronously; the move to
        // .previewing is async (high-res capture → OCR / fallback).
        #expect(!model.isAutoCapturePending)
        try await waitForPhase(model) { phase in
            if case .previewing = phase { return true }
            return false
        }
        guard case .previewing = model.phase else {
            Issue.record("expected .previewing after manual fire, got \(model.phase)")
            return
        }
    }

    // MARK: - Strain classification corrections

    @Test func setStrainClassUpdatesReadyInsightAndPersists() async throws {
        let store = InMemoryStrainOverrideStore()
        let model = ScanModel(
            extraction: MockExtractor(result: .success(Self.cleanFlowerLabel())),
            summary: MockSummarizer(result: .success(.ai(text: "ok.", regenerationsTried: 0))),
            availability: MockAvailability(value: .available),
            strainOverrides: store
        )
        model.handleCapture(ocr: "fake ocr input", qrCodes: [])
        try await waitForPipeline(model)
        // cleanFlowerLabel strain is "Test Strain" — no marker, no lineage →
        // no insight initially.
        guard case .ready(_, _, _, let initialInsight) = model.phase else {
            Issue.record("expected .ready, got \(model.phase)")
            return
        }
        #expect(initialInsight == nil)

        model.setStrainClass(.indica)
        guard case .ready(_, _, _, let updated) = model.phase else {
            Issue.record("expected .ready after setStrainClass, got \(model.phase)")
            return
        }
        #expect(updated?.lean == .indica)
        #expect(updated?.source == .userOverride)
        // Persisted to the store.
        #expect(store.lean(forStrainName: "Test Strain") == .indica)
    }

    @Test func clearStrainClassRemovesOverride() async throws {
        let store = InMemoryStrainOverrideStore()
        store.setLean(.sativa, forStrainName: "Test Strain")
        let model = ScanModel(
            extraction: MockExtractor(result: .success(Self.cleanFlowerLabel())),
            summary: MockSummarizer(result: .success(.ai(text: "ok.", regenerationsTried: 0))),
            availability: MockAvailability(value: .available),
            strainOverrides: store
        )
        model.handleCapture(ocr: "fake ocr input", qrCodes: [])
        try await waitForPipeline(model)
        // Override applied → sativa insight.
        guard case .ready(_, _, _, let insight) = model.phase else {
            Issue.record("expected .ready, got \(model.phase)")
            return
        }
        #expect(insight?.lean == .sativa)

        model.clearStrainClass()
        #expect(store.lean(forStrainName: "Test Strain") == nil)
    }

    @Test func partialFieldDetectionDoesNotSchedule() async throws {
        let model = ScanModel(
            extraction: MockExtractor(result: .success(Self.cleanFlowerLabel())),
            summary: MockSummarizer(result: .success(.ai(text: "ok.", regenerationsTried: 0))),
            availability: MockAvailability(value: .available)
        )
        model.startScan()
        // 3 fields → meets manual capture threshold but NOT all-5 trigger.
        model.handleTextUpdate(
            ocr: "License # C000186\n1A4110300003C8D000041730\nTHCA: 29.73%",
            qrCodes: []
        )
        #expect(model.canCapture)
        #expect(!model.allFieldsDetected)
        #expect(!model.isAutoCapturePending)
    }

    // MARK: - Helpers

    /// Poll model.phase until it lands on a terminal state. Throws if it
    /// doesn't settle within 5 seconds.
    private func waitForPipeline(_ model: ScanModel) async throws {
        try await waitForPhase(model) { phase in
            switch phase {
            case .ready, .failed: return true
            default: return false
            }
        }
    }

    /// Generic phase poller. Times out after 5 seconds.
    private func waitForPhase(_ model: ScanModel, predicate: (ScanModel.Phase) -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if predicate(model.phase) { return }
            try await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }
        Issue.record("Phase did not satisfy predicate within 5s. Last phase: \(model.phase)")
    }
}

// MARK: - Mocks

actor MockExtractor: LabelExtracting {
    enum Outcome { case success(CannabisLabel); case failure(Error) }
    private let outcome: Outcome
    private(set) var callCount: Int = 0

    init(result: Outcome) { self.outcome = result }

    func extract(rawOcrText: String) async throws -> CannabisLabel {
        callCount += 1
        switch outcome {
        case .success(let label): return label
        case .failure(let err): throw err
        }
    }

    func warm() async {}
}

actor MockSummarizer: LabelSummarizing {
    enum Outcome { case success(SummaryOutcome); case failure(Error) }
    private let outcome: Outcome
    private(set) var callCount: Int = 0

    init(result: Outcome) { self.outcome = result }

    func summarize(_ label: CannabisLabel, strainInsight: StrainInsight?) async throws -> SummaryOutcome {
        callCount += 1
        switch outcome {
        case .success(let o): return o
        case .failure(let err): throw err
        }
    }

    func warm() async {}
}

struct MockAvailability: AvailabilityProviding {
    let value: FMAvailability
    func current() -> FMAvailability { value }
}
