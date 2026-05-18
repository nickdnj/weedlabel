import Foundation
import FoundationModels

// AvailabilityGate — wraps SystemLanguageModel availability and surfaces a
// product-shaped state for the UI. Per /autoplan eng review:
// - .available           → continue with FM
// - .deviceNotEligible   → fields-only (older hardware)
// - .appleIntelligenceNotEnabled → Settings deep-link + fields-only
// - .modelNotReady       → "AI isn't ready yet" + fields-only, retry next scan
// "Downloading" is not a distinct API state; it lives inside .modelNotReady.

enum FMAvailability: Sendable, Equatable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unsupported(reason: String)

    var copy: String {
        switch self {
        case .available:
            return ""
        case .deviceNotEligible:
            return "AI summaries require iPhone 15 Pro or later. Scanning still works without AI."
        case .appleIntelligenceNotEnabled:
            return "AI summaries require Apple Intelligence. Enable it in Settings → Apple Intelligence & Siri. Scanning still works without AI."
        case .modelNotReady:
            return "AI isn't ready yet. Apple Intelligence may still be downloading. AI summaries will appear automatically when ready."
        case .unsupported(let reason):
            return "AI summaries are unavailable: \(reason). Scanning still works without AI."
        }
    }
}

enum AvailabilityGate {
    /// Probe Foundation Models availability. Per the eng spec, call on `.onAppear`
    /// of the scan view AND before each FM request — the user can toggle Apple
    /// Intelligence on without backgrounding the app.
    static func current() -> FMAvailability {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .deviceNotEligible
            case .appleIntelligenceNotEnabled:
                return .appleIntelligenceNotEnabled
            case .modelNotReady:
                return .modelNotReady
            @unknown default:
                return .unsupported(reason: String(describing: reason))
            }
        }
    }
}
