import Foundation
import SwiftUI

// ScanModel — the spike's state machine. Drives the single-screen flow:
//   idle → scanning → parsing → sanity → summarizing → complete
//                                ↘ verifyHint (suppress AI)
//   Any error → failed
// The pipeline is sequential per the v1 eng spec.

@Observable
@MainActor
final class ScanModel {
    enum Phase {
        case idle(availability: FMAvailability)
        case scanning
        case parsing(rawOcrText: String)
        case sanityChecking(label: CannabisLabel)
        case summarizing(label: CannabisLabel)
        case ready(label: CannabisLabel, summary: SummaryOutcome?)
        case verifyHint(label: CannabisLabel, reason: String)
        case failed(message: String)
    }

    var phase: Phase = .idle(availability: AvailabilityGate.current())

    private let extraction = ExtractionService()
    private let summary = SummaryService()
    private var pipelineTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func refreshAvailability() {
        if case .idle = phase {
            phase = .idle(availability: AvailabilityGate.current())
        }
    }

    func startScan() {
        phase = .scanning
        Task.detached(priority: .userInitiated) { [extraction, summary] in
            await extraction.warm()
            await summary.warm()
        }
    }

    func cancel() {
        pipelineTask?.cancel()
        phase = .idle(availability: AvailabilityGate.current())
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
                let extracted = try await self.extraction.extract(rawOcrText: ocr)
                // Merge in QR codes captured by VisionKit (FM doesn't see them)
                var withQRs = extracted
                withQRs.qrCodes = (extracted.qrCodes + qrCodes).reduced
                label = withQRs
            } catch is CancellationError {
                return
            } catch {
                self.phase = .failed(message: "Couldn't read this label. \(error.localizedDescription)")
                return
            }
            if Task.isCancelled { return }

            self.phase = .sanityChecking(label: label)

            // 2. Sanity check
            let verdict = LabelSanityChecker.check(label)
            if case .verifyHint(let reason) = verdict {
                self.phase = .verifyHint(label: label, reason: reason)
                return
            }
            if Task.isCancelled { return }

            // 3. Summarize via FM, IF availability is OK
            let availability = AvailabilityGate.current()
            guard availability == .available else {
                self.phase = .ready(label: label, summary: nil)
                return
            }

            self.phase = .summarizing(label: label)
            do {
                let outcome = try await self.summary.summarize(label)
                if Task.isCancelled { return }
                self.phase = .ready(label: label, summary: outcome)
            } catch is CancellationError {
                return
            } catch {
                // Summary failed — still surface the parsed label
                self.phase = .ready(label: label, summary: nil)
            }
        }
    }
}

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
