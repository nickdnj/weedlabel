import Foundation

// Protocol seams that let ScanModel be unit-tested without invoking
// Foundation Models. Production code uses the real ExtractionService /
// SummaryService / AvailabilityGate; tests inject mock conformers that
// produce deterministic results for the post-extraction forks (sanity
// check → summary vs verifyHint vs availability gate vs failure).

protocol LabelExtracting: Sendable {
    func extract(rawOcrText: String) async throws -> CannabisLabel
    func warm() async
}

protocol LabelSummarizing: Sendable {
    func summarize(_ label: CannabisLabel, strainInsight: StrainInsight?) async throws -> SummaryOutcome
    func warm() async
}

protocol AvailabilityProviding: Sendable {
    func current() -> FMAvailability
}

extension ExtractionService: LabelExtracting {}
extension SummaryService: LabelSummarizing {}

/// Production availability provider — wraps the static AvailabilityGate.
struct DefaultAvailabilityProvider: AvailabilityProviding {
    func current() -> FMAvailability { AvailabilityGate.current() }
}
