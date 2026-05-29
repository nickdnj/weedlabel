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
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":-.")))
            .lowercased()
        return forbiddenNames.contains(normalized)
    }

    /// Boilerplate the model occasionally grabs as a strain when the real name
    /// is scrambled away from the top — warnings, directions, regulatory text.
    /// These appear on every NJ-CRC label and are never a strain name.
    static func isBoilerplateLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        let markers = [
            "psychosis", "high potency", "intoxicating effects", "poison control",
            "keep out of the reach", "out of reach of children", "not for resale",
            "contains cannabis", "health risk", "do not drive", "heavy machinery",
            "operate heavy", "food and drug", "fda", "pregnant", "breastfeeding",
            "store in a cool", "directions", "active ingredient", "other ingredient",
            "net wt", "net weight", "using this product", "this product", "while using",
            // Lines seen grabbed off real labels (some via OCR typos, so match
            // short fragments): "Pesticides used: None", the warning paragraph's
            // "National Poison Control Center", FDA/age boilerplate.
            "pesticides", "national", "control center", "poison", "drug administ",
            "21 years", "do not", "grow method", "lic number", "license",
            "potential allergen", "requires refriger", "inactive ingredient",
            "this statement", "evaluated", "food and", "pkg date", "exp date",
            "storage", "serving size", "servings per",
        ]
        return markers.contains { lower.contains($0) }
    }

    /// Try to extract a better strain name from the raw OCR. Heuristic: find
    /// the first non-empty line that:
    ///   - isn't a Metrc tag, license number, date, or barcode
    ///   - isn't a known forbidden name
    ///   - isn't all-numeric / mostly punctuation
    ///   - has at least one letter
    /// Most NJ-CRC labels print the product name in the top 1-3 lines.
    static func candidateFromOCR(_ ocrText: String, cultivator: String? = nil) -> String? {
        let cult = cultivator?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
            if isChemotypeLine(line) { continue }     // "High THC, Low CBD" etc.
            if isBoilerplateLine(line) { continue }   // warnings, directions, FDA text
            if isLabeledValueLine(line) { continue }  // "Limonene: 1.08 %", "THCa: 28.73"
            // Skip the cultivator/brand line — it's provenance, not the strain.
            if let cult, !cult.isEmpty, line.lowercased().contains(cult) { continue }
            // Strip trailing weight/format markers like " - 28g" or " Flower 3.5g"
            // to leave a cleaner strain name.
            let cleaned = stripTrailingFormatMarkers(line)
            if cleaned.isEmpty { continue }
            if isFormOnlyLine(cleaned) { continue }   // "Gummies", "Inhalable Product"
            // A strain name is short; long lines are warning paragraphs / merged
            // OCR rows. Check AFTER stripping the weight so a normal title like
            // "Kynd Permanent Gas #15 (S) Flower 3.5g" isn't rejected for length.
            if cleaned.split(whereSeparator: { $0 == " " }).count > 6 || cleaned.count > 48 { continue }
            return cleaned
        }
        return nil
    }

    /// If the FM-extracted strain looks suspicious, try to replace it from
    /// OCR. "Suspicious" means either:
    ///   1. It matches a known terpene/cannabinoid/section-header name.
    ///   2. It appears in the OCR text adjacent to a percent value — almost
    ///      always a sign the model latched onto a chemical-compound name or
    ///      OCR fragment of one (e.g. "Beicaropa" near "0.64%").
    static func fix(strain: String, cultivator: String? = nil, ocrText: String) -> (strain: String, didFix: Bool) {
        let cult = cultivator?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let s = strain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matchesCultivator: Bool = {
            guard let cult, cult.count >= 4, s.count >= 4 else { return false }
            // Contains-match both ways: the model often emits the cultivator
            // verbatim ("Pine Barrens") or a superset ("Pine Barrens Cannabis Co").
            return s == cult || s.contains(cult) || cult.contains(s)
        }()
        // A real strain name is short. Warning-paragraph fragments the model
        // sometimes grabs ("using this product. National Poison Control…") are
        // long — reject anything with too many words or characters. This catches
        // OCR-mangled boilerplate that the marker list misses ("tnis"/"poisoa").
        let wordCount = strain.split(whereSeparator: { $0 == " " }).count
        let tooLong = wordCount > 6 || strain.count > 48
        let badName = isSuspicious(strain)
            || isBoilerplateLine(strain)
            || isLabeledValueLine(strain)                          // "Limonene: 1.08 %"
            || isAddressLikeLine(strain)                           // "Woodbridge NJ, 07095"
            || tooLong
            || isFormOnlyLine(stripTrailingFormatMarkers(strain))  // "Live Resin Cartridge"
            || matchesCultivator
            || looksLikeChemicalFragment(strain, in: ocrText)
            || isAbsentFromOCR(strain, in: ocrText)
        guard badName else { return (strain, false) }
        if let candidate = candidateFromOCR(ocrText, cultivator: cultivator) {
            return (candidate, true)
        }
        return (strain, false)
    }

    /// True when NONE of the strain name's significant words appear in the OCR
    /// text — a near-certain sign the model invented the name rather than read
    /// it. The dominant failure mode this catches: the model regurgitating the
    /// "Blue Candy Rain" example baked into the @Guide schema description when it
    /// can't read the real name, stamping it onto unrelated products.
    ///
    /// Token-based on purpose: a real name often wraps across OCR lines (e.g.
    /// "Zips - Blue Candy" / "Rain - 28g"), so a contiguous substring test would
    /// wrongly reject it. Requiring that not even ONE significant word is present
    /// keeps the false-positive rate near zero — a name with any word on the
    /// label is left alone.
    static func isAbsentFromOCR(_ name: String, in ocrText: String) -> Bool {
        let tokens = significantTokens(name)
        guard !tokens.isEmpty else { return false }   // nothing to judge → don't flag
        let hay = ocrText.lowercased()
        return !tokens.contains { hay.contains($0) }
    }

    /// Words worth matching against the label: ≥3 chars, lowercased, with
    /// product-form / dosage words stripped (those appear on every label and
    /// would mask a hallucinated name).
    static func significantTokens(_ name: String) -> [String] {
        let formWords: Set<String> = [
            "flower", "vape", "vapes", "edible", "edibles", "concentrate",
            "preroll", "prerolls", "roll", "rolls", "tincture", "topical",
            "gummy", "gummies", "disposable", "cartridge", "cart", "inhalable",
            "product", "the", "and"
        ]
        let parts = name.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        return parts.filter { $0.count >= 3 && !formWords.contains($0) }
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
        let words = ["highway", "dispensary", "street", "road", "avenue", "drive",
                     "north", "south", "blvd", "suite", "route", "lane"]
        if words.contains(where: { lower.contains($0) }) { return true }
        // "City ST, ZIP" e.g. "Woodbridge NJ, 07095" — state abbrev + 5-digit zip.
        if let re = try? NSRegularExpression(pattern: #"\b[a-z]{2},?\s*\d{5}\b"#),
           re.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil {
            return true
        }
        return false
    }

    private static func containsLetter(_ line: String) -> Bool {
        line.contains(where: { $0.isLetter })
    }

    /// A "Label: value" data line (e.g. "Limonene: 1.08 %", "THCa: 28.73", "CBG:
    /// 0.59 %") — a colon followed by a number. After row-grouped OCR these are
    /// common, and they are never a strain name.
    private static func isLabeledValueLine(_ line: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #":\s*\d"#) else { return false }
        return regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    /// A potency/chemotype descriptor line like "High THC, Low CBD" or
    /// "Moderate THC, Moderate CBG" — never a strain name. Recovered by the
    /// hallucination fallback otherwise (observed on the Garden Society tin).
    private static func isChemotypeLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.contains("potency analysis") || lower.contains("terpene content") { return true }
        guard let regex = try? NSRegularExpression(
            pattern: #"\b(high|low|moderate)\b.{0,20}\b(thc|thca|cbd|cbg|cbn|cbc)\b"#,
            options: .caseInsensitive
        ) else { return false }
        return regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)) != nil
    }

    /// A line that is only product-form / dosage wording once weight markers are
    /// stripped — e.g. "Gummies", "Inhalable Product", "Pre-Roll". Not a strain.
    private static func isFormOnlyLine(_ line: String) -> Bool {
        let tokens = line.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
        guard !tokens.isEmpty else { return true }
        let formWords: Set<String> = [
            "flower", "vape", "vapes", "edible", "edibles", "concentrate",
            "preroll", "prerolls", "pre", "roll", "rolls", "tincture", "topical",
            "gummy", "gummies", "disposable", "cartridge", "cart", "inhalable",
            "product", "smokable", "smokeable",
            "live", "resin", "rosin", "badder", "balm", "salve", "cannabis", "infused"
        ]
        return tokens.allSatisfy { formWords.contains($0) }
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
