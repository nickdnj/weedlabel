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
        // Collapse runs of whitespace so OCR double-spacing ("THIS  PRODUCT IS
        // NOT INTEN") still matches a marker ("this product").
        let lower = line.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
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
            // The FDA disclaimer "...diagnose, treat, cure, or prevent any
            // disease." — the model grabbed "DISEASE. T" off the end of it.
            "disease", "diagnose", "prevent any",
            // The bold child-safety warning. Its own line on every NJ label, with
            // no chemistry/percent nearby, so none of the other classifiers catch
            // it — the model grabbed it as the strain on a cluttered top-row scan.
            "safe for kids", "not safe", "keep away from children",
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
            if isGibberish(line) { continue }         // OCR of a stylized logo
            if isSuspicious(line) { continue }
            if isChemotypeLine(line) { continue }     // "High THC, Low CBD" etc.
            if isBoilerplateLine(line) { continue }   // warnings, directions, FDA text
            if isLabeledValueLine(line) { continue }  // "Limonene: 1.08 %", "THCa: 28.73"
            // Skip a line that's essentially just the cultivator/brand (provenance,
            // not the strain) — but keep a brand+strain line like "Kynd Lollipopz".
            if let cult, !cult.isEmpty, isMostlyCultivator(line, cult: cult) { continue }
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
        // Salvage pass: row-grouped OCR can merge the strain name into a cluttered
        // top row (Metrc tag + name + "Total THC: 25.74%" + terpenes on one line),
        // so every line is skipped above and the only "clean" line left is the
        // child-safety warning. Recover the name from the LEADING segment of a top
        // row — the part before the chemistry block begins.
        return salvageLeadingName(lines, cultivator: cult)
    }

    /// Tokens marking where the chemistry/potency block starts on a row. The
    /// strain name, when merged into a cluttered top row, sits BEFORE the first
    /// of these. Ordered so "total thc"/"total cbd" cut earlier than bare "thc".
    private static let chemistryCutMarkers = [
        "total thc", "total cbd", "total cannabinoid", "thca", "thc", "cbd", "cbg",
        "cbn", "terpinolene", "myrcene", "marcene", "limonene", "linalool",
        "caryophyllene", "pinene", "humulene", "bisabolol", "ocimene", "%"
    ]

    /// Recover a strain name from the leading part of one of the top rows: cut the
    /// row at the first chemistry marker, strip a leading Metrc tag / license /
    /// long digit run, drop trailing weight markers, and accept the remainder if
    /// it reads like a name. Only reached when the normal line scan finds nothing.
    private static func salvageLeadingName(_ lines: [String], cultivator cult: String?) -> String? {
        for raw in lines.prefix(4) {
            let lower = raw.lowercased()
            // Earliest chemistry marker = where the name segment ends.
            var cutDistance = lower.count
            for m in chemistryCutMarkers {
                if let r = lower.range(of: m) {
                    cutDistance = min(cutDistance, lower.distance(from: lower.startIndex, to: r.lowerBound))
                }
            }
            let head = String(raw.prefix(cutDistance))
            let stripped = stripLeadingTagNoise(head)
            let cleaned = stripTrailingFormatMarkers(stripped.trimmingCharacters(in: .whitespacesAndNewlines))
            if cleaned.isEmpty || !containsLetter(cleaned) { continue }
            if isGibberish(cleaned) { continue }
            if isSuspicious(cleaned) || isBoilerplateLine(cleaned) || isChemotypeLine(cleaned) { continue }
            if isFormOnlyLine(stripTrailingFormatMarkers(cleaned)) { continue }
            if isAddressLikeLine(cleaned) { continue }
            // Skip only if the candidate is ESSENTIALLY just the brand. A
            // brand+strain line ("Kynd Lollipopz") keeps its strain — dropping it
            // would lose the name and let a hallucination survive.
            if let cult, !cult.isEmpty, isMostlyCultivator(cleaned, cult: cult) { continue }
            let letters = cleaned.filter { $0.isLetter }.count
            if letters < 3 { continue }
            if cleaned.split(whereSeparator: { $0 == " " }).count > 7 || cleaned.count > 48 { continue }
            return cleaned
        }
        return nil
    }

    /// OCR garbage from stylized logos / artwork — e.g. "BLO НАЧАААААААА…" off the
    /// WARHEADZ wordmark. Two signals: a run of 4+ identical letters (no real
    /// strain has that), or mostly non-Latin letters (these labels are English).
    static func isGibberish(_ s: String) -> Bool {
        if s.range(of: #"([a-zA-Zа-яА-Я])\1{3,}"#, options: .regularExpression) != nil { return true }
        let letters = s.filter { $0.isLetter }
        guard !letters.isEmpty else { return false }
        let nonLatin = letters.filter { !$0.isASCII }.count
        return Double(nonLatin) / Double(letters.count) > 0.4
    }

    /// A bare potency-descriptor fragment ("High", "Low", "High THC", "Low CBD")
    /// the model sometimes grabs off the chemotype line "High THC, Low CBD". Never
    /// a strain name. (isChemotypeLine needs both qualifier AND cannabinoid on the
    /// line; this catches the lone leftover word.)
    static func isChemotypeQualifierOnly(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,:")))
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return ["high", "low", "moderate",
                "high thc", "low thc", "high cbd", "low cbd",
                "moderate thc", "moderate cbd"].contains(n)
    }

    /// True when `text` is essentially just the cultivator/brand — i.e. removing
    /// the cultivator substring leaves fewer than 3 letters. "Garden State
    /// Dispensary" → true; "Kynd Lollipopz" (cult "Kynd") → false (keeps the
    /// strain). Used so brand+strain lines survive name recovery.
    private static func isMostlyCultivator(_ text: String, cult: String) -> Bool {
        let lower = text.lowercased()
        guard lower.contains(cult) else { return false }
        let remainder = lower.replacingOccurrences(of: cult, with: "")
        return remainder.filter { $0.isLetter }.count < 3
    }

    /// Strip leading Metrc-tag / license / number fragments off the front of a
    /// name or row. Token-based so it survives however OCR mangles the tag —
    /// contiguous ("1841103000003E9000067952", where 1A4 read as 184), split into
    /// pieces ("1A411 03000003E9 000064 032"), or a leftover fragment
    /// ("E9000067952"). Drops leading tokens that are digit-dominant; stops at the
    /// first wordy token so real names (incl. "9 Pound Hammer") are preserved.
    static func stripLeadingTagNoise(_ s: String) -> String {
        var tokens = s.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        while let first = tokens.first {
            let digits = first.filter { $0.isNumber }.count
            let letters = first.filter { $0.isLetter }.count
            let isTagNoise = (digits >= 4 && digits > letters && letters <= 4 && first.count >= 5)  // tag/license fragment
                          || (digits >= 3 && letters == 0)                                          // pure number run
            if isTagNoise { tokens.removeFirst() } else { break }
        }
        return tokens.joined(separator: " ")
    }

    /// If the FM-extracted strain looks suspicious, try to replace it from
    /// OCR. "Suspicious" means either:
    ///   1. It matches a known terpene/cannabinoid/section-header name.
    ///   2. It appears in the OCR text adjacent to a percent value — almost
    ///      always a sign the model latched onto a chemical-compound name or
    ///      OCR fragment of one (e.g. "Beicaropa" near "0.64%").
    static func fix(strain rawStrain: String, cultivator: String? = nil, ocrText: String) -> (strain: String, didFix: Bool) {
        // Sanitize a leading Metrc-tag / license fragment off the FM name first
        // ("E9000067952  Kynd Jet Fuel (S)" -> "Kynd Jet Fuel (S)"); OCR splits
        // tags unpredictably and the fragment otherwise rides along as the name.
        let trimmedRaw = rawStrain.trimmingCharacters(in: .whitespacesAndNewlines)
        let strain = stripLeadingTagNoise(trimmedRaw)
        let didStrip = strain != trimmedRaw
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
            || isChemotypeQualifierOnly(strain)                    // bare "High" / "Low CBD"
            || isLabeledValueLine(strain)                          // "Limonene: 1.08 %"
            || isAddressLikeLine(strain)                           // "Woodbridge NJ, 07095"
            || tooLong
            || isFormOnlyLine(stripTrailingFormatMarkers(strain))  // "Live Resin Cartridge"
            || matchesCultivator
            || looksLikeChemicalFragment(strain, in: ocrText)
            || isAbsentFromOCR(strain, in: ocrText)
        guard badName else { return (strain, didStrip) }
        if let candidate = candidateFromOCR(ocrText, cultivator: cultivator) {
            return (candidate, true)
        }
        return (strain, didStrip)
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
        // Allow a period for the comma (OCR reads "NJ," as "NJ.").
        if let re = try? NSRegularExpression(pattern: #"\b[a-z]{2}[.,]?\s*\d{5}\b"#),
           re.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil {
            return true
        }
        // A phone number "(848) 999-2005" — provenance, never a strain.
        if let re = try? NSRegularExpression(pattern: #"\(?\d{3}\)?\s*-?\s*\d{3}\s*-\s*\d{4}"#),
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
