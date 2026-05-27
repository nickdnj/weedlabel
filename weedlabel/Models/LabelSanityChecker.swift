import Foundation

// LabelSanityChecker — productType-aware out-of-distribution checks per the v1
// engineering spec. Runs AFTER Generable extraction, BEFORE FM summary generation.
// On any failed rule, the AI summary is suppressed for this scan and a verify
// hint is surfaced instead.

struct LabelSanityChecker {
    enum Verdict: Sendable {
        case ok
        case verifyHint(reason: String)
    }

    static func check(_ label: CannabisLabel) -> Verdict {
        // Cannabinoid ceilings — productType-aware. Concentrates can legitimately
        // exceed 80%; flower above 40% total is OCR error territory.
        switch label.productType {
        case .flower, .preRoll:
            if let total = label.totalCannabinoids ?? label.computedTotalThc, total > 40 {
                return .verifyHint(reason: "flower total cannabinoids \(formatted(total))% exceeds typical 40% ceiling")
            }
            if let thca = label.thca, thca > 40 {
                return .verifyHint(reason: "THCA \(formatted(thca))% exceeds typical flower ceiling")
            }
        case .concentrate, .vape:
            if let total = label.totalCannabinoids ?? label.computedTotalThc, total > 99 {
                return .verifyHint(reason: "concentrate total cannabinoids \(formatted(total))% exceeds 99%")
            }
        case .edible:
            // Edibles often print mg-per-serving, not %. Skip percentage rules.
            break
        case .tincture, .topical, .other:
            break
        }

        // Total THC formula sanity (NJAC §17:30-16.3(b)(9)(ii)(1)):
        //   Total THC = (THCA × 0.877) + Δ9-THC, ±0.05% tolerance
        // Checked BEFORE the terpene sum rule because a Total THC mismatch is
        // the most diagnostic signal — it tells the user the headline THC
        // figure is suspect, which is what they care about most.
        if let printedTotal = label.totalThc, let computed = label.computedTotalThc {
            if abs(printedTotal - computed) > 0.05 {
                return .verifyHint(reason: "printed Total THC (\(formatted(printedTotal))%) does not match computed (\(formatted(computed))%) per NJAC §17:30-16.3(b)(9)(ii)")
            }
        }

        // Terpene rules apply across all productTypes.
        if let total = label.totalTerpenes, total > 8 {
            return .verifyHint(reason: "total terpenes \(formatted(total))% exceeds typical 8% ceiling")
        }
        let singles: [Double?] = [
            label.myrcene,
            label.limonene,
            label.linalool,
            label.betaCaryophyllene,
            label.pinene,
            label.humulene
        ]
        for value in singles.compactMap({ $0 }) {
            if value > 5 {
                return .verifyHint(reason: "single terpene \(formatted(value))% exceeds 5% ceiling")
            }
        }

        // Sum of named terpenes vs declared total: named must not exceed total.
        let namedSum: Double = singles.compactMap({ $0 }).reduce(0.0, +)
        if let total = label.totalTerpenes, namedSum > total + 0.5 { // 0.5% tolerance for rounding
            return .verifyHint(reason: "named terpenes sum (\(formatted(namedSum))%) exceeds declared total (\(formatted(total))%)")
        }

        // Date sanity
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        if let harvestStr = label.harvestDate, let expirationStr = label.expirationDate,
           let harvest = formatter.date(from: harvestStr),
           let expiration = formatter.date(from: expirationStr) {
            if expiration < harvest {
                return .verifyHint(reason: "expiration (\(expirationStr)) is before harvest (\(harvestStr))")
            }
            let twoYearsSeconds: TimeInterval = 60.0 * 60.0 * 24.0 * 365.0 * 2.0
            if expiration > Date().addingTimeInterval(twoYearsSeconds) {
                return .verifyHint(reason: "expiration (\(expirationStr)) is more than 2 years out")
            }
        }

        // Metrc tag format (best-effort): typically 24 chars starting with '1A4'.
        if let tag = label.metrcTag {
            let trimmed = tag.replacingOccurrences(of: " ", with: "").uppercased()
            if !trimmed.isEmpty && !trimmed.hasPrefix("1A4") {
                return .verifyHint(reason: "metrc tag '\(tag)' does not start with '1A4'")
            }
        }

        return .ok
    }

    private static func formatted(_ d: Double) -> String {
        String(format: "%.2f", d)
    }
}
