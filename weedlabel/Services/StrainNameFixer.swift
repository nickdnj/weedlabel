import Foundation

// StrainNameFixer — pure helper that post-corrects the FM's extracted
// strainName when it's obviously wrong. The observed failure mode: the model
// picks a chemical compound name (e.g. "Limonene") instead of the actual
// strain name because the strain name is unfamiliar but the compound name is
// well-known. We detect this and substitute the first plausible label-text
// line from the OCR.
//
// Pure — takes the FM-extracted strain + the raw OCR text, returns a
// (possibly replaced) strain name plus a flag indicating whether a fix was
// applied. Lives outside CannabisLabel so it can be unit-tested without FM.

enum StrainNameFixer {
    /// Names the FM should NEVER use as strainName. All matched
    /// case-insensitively.
    static let forbiddenNames: Set<String> = [
        // Cannabinoids
        "thc", "thca", "thcv", "cbd", "cbda", "cbg", "cbga", "cbc", "cbn",
        "delta-9-thc", "delta9-thc", "delta-9", "delta9", "δ9-thc",
        // Terpenes
        "myrcene", "beta-myrcene", "betamyrcene",
        "limonene", "linalool",
        "caryophyllene", "beta-caryophyllene", "betacaryophyllene",
        "pinene", "alpha-pinene", "beta-pinene", "alphapinene", "betapinene",
        "humulene", "bisabolol", "terpinolene", "ocimene", "farnesene",
        "caryophyllene oxide", "caryophylleneoxide",
        // Section headers
        "potency analysis", "terpene contents",
        "total cannabinoids", "total terpenes", "total thc", "total cbd"
    ]

    /// Returns true if `name` is a known chemical-compound or section-header
    /// label that shouldn't appear as a strain.
    static func isSuspicious(_ name: String) -> Bool {
        let normalized = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return forbiddenNames.contains(normalized)
    }

    /// Try to extract a better strain name from the raw OCR. Heuristic: find
    /// the first non-empty line that:
    ///   - isn't a Metrc tag, license number, date, or barcode
    ///   - isn't a known forbidden name
    ///   - isn't all-numeric / mostly punctuation
    ///   - has at least one letter
    /// Most NJ-CRC labels print the product name in the top 1-3 lines.
    static func candidateFromOCR(_ ocrText: String) -> String? {
        let lines = ocrText.components(separatedBy: .newlines)
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if isMetrcTagLine(line) { continue }
            if isLicenseLine(line) { continue }
            if isDateLine(line) { continue }
            if isAddressLikeLine(line) { continue }
            if !containsLetter(line) { continue }
            if isSuspicious(line) { continue }
            // Strip trailing weight/format markers like " - 28g" or " Flower 3.5g"
            // to leave a cleaner strain name.
            let cleaned = stripTrailingFormatMarkers(line)
            if !cleaned.isEmpty {
                return cleaned
            }
        }
        return nil
    }

    /// If the FM-extracted strain looks suspicious, try to replace it from
    /// OCR. "Suspicious" means either:
    ///   1. It matches a known terpene/cannabinoid/section-header name.
    ///   2. It appears in the OCR text adjacent to a percent value — almost
    ///      always a sign the model latched onto a chemical-compound name or
    ///      OCR fragment of one (e.g. "Beicaropa" near "0.64%").
    static func fix(strain: String, ocrText: String) -> (strain: String, didFix: Bool) {
        let badName = isSuspicious(strain) || looksLikeChemicalFragment(strain, in: ocrText)
        guard badName else { return (strain, false) }
        if let candidate = candidateFromOCR(ocrText) {
            return (candidate, true)
        }
        return (strain, false)
    }

    /// True when `name` appears in the OCR on a line that also contains a
    /// percent value. Real strain names live in the header; chemical names
    /// and their OCR-mangled fragments live next to numbers.
    ///
    /// Bounded to short names (<= 18 chars) so we don't accidentally
    /// flag a real multi-word strain that happens to share a line with a value.
    static func looksLikeChemicalFragment(_ name: String, in ocrText: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 18, !trimmed.isEmpty else { return false }
        let percentRegex = try? NSRegularExpression(pattern: #"\d+(?:\.\d+)?\s*%"#)
        guard let percentRegex else { return false }
        for line in ocrText.components(separatedBy: .newlines) {
            // Need a case-sensitive match to avoid false positives on common
            // words. Model usually preserves capitalization.
            guard line.contains(trimmed) else { continue }
            let range = NSRange(line.startIndex..., in: line)
            if percentRegex.firstMatch(in: line, options: [], range: range) != nil {
                return true
            }
        }
        return false
    }

    // MARK: - Line classifiers

    private static func isMetrcTagLine(_ line: String) -> Bool {
        // Metrc tags are 24-ish chars starting with 1A4, all alphanumeric.
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 16, compact.hasPrefix("1A4") else { return false }
        return compact.allSatisfy { $0.isLetter || $0.isNumber }
    }

    private static func isLicenseLine(_ line: String) -> Bool {
        // "License # C000186" or "Lic Number: C000067" or just "C000186".
        let lower = line.lowercased()
        if lower.contains("license") || lower.contains("lic number") || lower.contains("lic #") {
            return true
        }
        if let regex = try? NSRegularExpression(pattern: #"^\s*C\d{5,7}\s*$"#) {
            let range = NSRange(line.startIndex..., in: line)
            if regex.firstMatch(in: line, options: [], range: range) != nil { return true }
        }
        return false
    }

    private static func isDateLine(_ line: String) -> Bool {
        // MM/DD/YYYY or YYYY-MM-DD or "Harvest Date: ..."
        let lower = line.lowercased()
        if lower.contains("date:") || lower.contains("date :") { return true }
        if let regex = try? NSRegularExpression(pattern: #"^\s*\d{1,2}/\d{1,2}/\d{2,4}\s*$"#) {
            let range = NSRange(line.startIndex..., in: line)
            if regex.firstMatch(in: line, options: [], range: range) != nil { return true }
        }
        return false
    }

    private static func isAddressLikeLine(_ line: String) -> Bool {
        // Stripping addresses out of strain consideration (these usually
        // already got removed by the boilerplate stripper, but be safe).
        let lower = line.lowercased()
        return lower.contains("highway") || lower.contains("dispensary")
            || lower.contains("street") || lower.contains("road")
            || lower.contains("avenue") || lower.contains("drive")
    }

    private static func containsLetter(_ line: String) -> Bool {
        line.contains(where: { $0.isLetter })
    }

    /// Drop trailing format/weight markers like " Flower 3.5g" or " - 28g".
    private static func stripTrailingFormatMarkers(_ line: String) -> String {
        let patterns = [
            #"\s+(Flower|Vape|Edible|Concentrate|Pre-?Roll|Tincture)\s+\d+(\.\d+)?\s*(g|oz)\b.*$"#,
            #"\s+-\s+\d+(\.\d+)?\s*(g|oz)\b.*$"#,
            #"\s+\d+(\.\d+)?\s*(g|oz)\b.*$"#
        ]
        var out = line
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p, options: .caseInsensitive) {
                let range = NSRange(out.startIndex..., in: out)
                out = regex.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: "")
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
