import Foundation

// Field-by-field CannabisLabel diff. Distinguishes per field:
//   - bothNull    (neither side emitted a value)
//   - agree       (both emitted equivalent values, within tolerance)
//   - disagree    (both emitted values, but different beyond tolerance)
//   - onlyApple / onlyClaude (one side has a value, the other is null)
//
// Comparison is type-aware, NOT string equality:
//   - strings (strainName, cultivator, …): case/diacritic/whitespace-folded
//   - productType: exact enum match (storageKey)
//   - cannabinoid numerics: ±0.5 absolute (labels round; OCR drops a digit)
//   - terpene numerics: ±0.1 absolute
//   - qrCodes: set equality (order-insensitive)

enum FieldStatus: String, Sendable {
    case bothNull
    case agree
    case disagree
    case onlyApple
    case onlyClaude
}

struct FieldDiff: Sendable {
    let name: String
    let apple: String?
    let claude: String?
    let status: FieldStatus
}

struct LabelDiff: Sendable {
    let fields: [FieldDiff]

    var disagreements: [FieldDiff] {
        fields.filter { $0.status == .disagree || $0.status == .onlyApple || $0.status == .onlyClaude }
    }

    var hasAnyDisagreement: Bool { !disagreements.isEmpty }
}

enum LabelComparator {
    /// Tolerances per the ground-truth conventions: cannabinoids ±0.5, terpenes ±0.1.
    static let cannabinoidTolerance = 0.5
    static let terpeneTolerance = 0.1

    /// Stable field order used by both the per-label table and the roll-up.
    static let scalarKeys = [
        // metadata
        "strainName", "cultivator", "productType", "netWeight",
        "licenseNumber", "metrcTag", "harvestDate", "expirationDate",
        // cannabinoids
        "thca", "delta9thc", "cbd", "cbg", "totalCannabinoids", "totalThc", "totalCbd",
        // terpenes
        "myrcene", "limonene", "linalool", "betaCaryophyllene", "pinene", "humulene", "totalTerpenes",
        // barcodes
        "qrCodes",
    ]

    static func diff(apple: CannabisLabel?, claude: CannabisLabel?) -> LabelDiff {
        let bothMissing = apple == nil && claude == nil
        let onlyAppleLabel = apple != nil && claude == nil
        let onlyClaudeLabel = apple == nil && claude != nil

        if bothMissing {
            return LabelDiff(fields: scalarKeys.map {
                FieldDiff(name: $0, apple: nil, claude: nil, status: .bothNull)
            })
        }

        var out: [FieldDiff] = []

        func statusFor(aPresent: Bool, cPresent: Bool, equal: @autoclosure () -> Bool) -> FieldStatus {
            if onlyAppleLabel { return aPresent ? .onlyApple : .bothNull }
            if onlyClaudeLabel { return cPresent ? .onlyClaude : .bothNull }
            if !aPresent && !cPresent { return .bothNull }
            if aPresent && !cPresent { return .onlyApple }
            if !aPresent && cPresent { return .onlyClaude }
            return equal() ? .agree : .disagree
        }

        func cmpStr(_ name: String, _ av: String?, _ cv: String?) {
            let an = av?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            let cn = cv?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            let status = statusFor(aPresent: an != nil, cPresent: cn != nil, equal: foldedEqual(an ?? "", cn ?? ""))
            out.append(FieldDiff(name: name, apple: an, claude: cn, status: status))
        }

        func cmpDouble(_ name: String, _ av: Double?, _ cv: Double?, tolerance: Double) {
            let status = statusFor(aPresent: av != nil, cPresent: cv != nil,
                                   equal: { if let a = av, let c = cv { return abs(a - c) <= tolerance }; return false }())
            out.append(FieldDiff(name: name, apple: av.map(fmt), claude: cv.map(fmt), status: status))
        }

        func cmpEnum(_ name: String, _ av: ProductType?, _ cv: ProductType?) {
            // productType is always present on a parsed label (defaults .other),
            // so treat it as present on whichever side produced a label.
            let aPresent = apple != nil
            let cPresent = claude != nil
            let status = statusFor(aPresent: aPresent, cPresent: cPresent, equal: (av == cv))
            out.append(FieldDiff(name: name, apple: av?.storageKey, claude: cv?.storageKey, status: status))
        }

        func cmpStrArr(_ name: String, _ av: [String], _ cv: [String]) {
            let an = Set(av.map { normalize($0) }.filter { !$0.isEmpty })
            let cn = Set(cv.map { normalize($0) }.filter { !$0.isEmpty })
            let status = statusFor(aPresent: !an.isEmpty, cPresent: !cn.isEmpty, equal: (an == cn))
            out.append(FieldDiff(name: name,
                                 apple: av.isEmpty ? nil : av.joined(separator: ", "),
                                 claude: cv.isEmpty ? nil : cv.joined(separator: ", "),
                                 status: status))
        }

        // metadata
        cmpStr("strainName", apple?.strainName, claude?.strainName)
        cmpStr("cultivator", apple?.cultivator, claude?.cultivator)
        cmpEnum("productType", apple?.productType, claude?.productType)
        cmpStr("netWeight", apple?.netWeight, claude?.netWeight)
        cmpStr("licenseNumber", apple?.licenseNumber, claude?.licenseNumber)
        cmpStr("metrcTag", apple?.metrcTag, claude?.metrcTag)
        cmpStr("harvestDate", apple?.harvestDate, claude?.harvestDate)
        cmpStr("expirationDate", apple?.expirationDate, claude?.expirationDate)
        // cannabinoids (±0.5)
        cmpDouble("thca", apple?.thca, claude?.thca, tolerance: cannabinoidTolerance)
        cmpDouble("delta9thc", apple?.delta9thc, claude?.delta9thc, tolerance: cannabinoidTolerance)
        cmpDouble("cbd", apple?.cbd, claude?.cbd, tolerance: cannabinoidTolerance)
        cmpDouble("cbg", apple?.cbg, claude?.cbg, tolerance: cannabinoidTolerance)
        cmpDouble("totalCannabinoids", apple?.totalCannabinoids, claude?.totalCannabinoids, tolerance: cannabinoidTolerance)
        cmpDouble("totalThc", apple?.totalThc, claude?.totalThc, tolerance: cannabinoidTolerance)
        cmpDouble("totalCbd", apple?.totalCbd, claude?.totalCbd, tolerance: cannabinoidTolerance)
        // terpenes (±0.1)
        cmpDouble("myrcene", apple?.myrcene, claude?.myrcene, tolerance: terpeneTolerance)
        cmpDouble("limonene", apple?.limonene, claude?.limonene, tolerance: terpeneTolerance)
        cmpDouble("linalool", apple?.linalool, claude?.linalool, tolerance: terpeneTolerance)
        cmpDouble("betaCaryophyllene", apple?.betaCaryophyllene, claude?.betaCaryophyllene, tolerance: terpeneTolerance)
        cmpDouble("pinene", apple?.pinene, claude?.pinene, tolerance: terpeneTolerance)
        cmpDouble("humulene", apple?.humulene, claude?.humulene, tolerance: terpeneTolerance)
        cmpDouble("totalTerpenes", apple?.totalTerpenes, claude?.totalTerpenes, tolerance: terpeneTolerance)
        // barcodes
        cmpStrArr("qrCodes", apple?.qrCodes ?? [], claude?.qrCodes ?? [])

        return LabelDiff(fields: out)
    }

    private static func fmt(_ d: Double) -> String { String(format: "%.2f", d) }

    private static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func foldedEqual(_ a: String, _ b: String) -> Bool {
        normalize(a) == normalize(b)
    }
}

extension String {
    /// nil when the string is empty after no further trimming; used to fold
    /// "" into the both-null bucket.
    var nonEmpty: String? { isEmpty ? nil : self }
}
