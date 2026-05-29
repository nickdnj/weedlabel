import Foundation

// OCRPreprocessor — conservative deterministic cleanup of NJ-CRC label OCR text
// before it reaches the Foundation Models @Generable extractor. Each rule fixes
// a noise pattern observed in the canary set (`assets/validation/`) and is
// applied only where the substitution is unambiguous.
//
// Categories:
//   1. Terpene name OCR errors: well-known character substitutions (label
//      substitutions, always safe).
//   2. Cannabinoid name OCR errors: G↔O letter substitutions, etc. (always
//      safe — substitutions are anchored to colon-suffixed acronyms).
//   3. Percent-glyph mis-reads: "X.XX 90" / " 00" / " 06" / " 0%" / " %%"
//      → "X.XX%". SCOPED per-line: only applied to lines containing a known
//      cannabinoid/terpene keyword or that are pure "<value> <noise>" lines.
//      This avoids corrupting non-cannabis numeric text like "Batch 12 96".
//
// We do NOT attempt name↔value re-pairing for two-column layouts — that's
// genuinely ambiguous and left to the FM step.

enum OCRPreprocessor {
    static func clean(_ raw: String) -> String {
        // Step 1 — name fixes. Apply to the whole text since these
        // substitutions are anchored (e.g. "CBO:" with the colon) and the
        // terpene/cannabinoid name strings don't collide with other content.
        var text = applyNameFixes(raw)

        // Step 2 — strip regulatory boilerplate. NJ-CRC labels carry standard
        // FDA disclaimer paragraphs, warnings, dosing directions, addresses,
        // and phone numbers — none of which the @Generable schema cares about.
        // Removing them keeps us under the FM 4096-token context window on
        // chatty labels (Kynd-style packages with full inserts).
        text = stripBoilerplate(text)

        // Step 3 — percent fixes, scoped per-line. We do this AFTER name fixes
        // so that lines that previously held an OCR-mangled keyword (e.g.
        // "Betataryophyllene: 0.44 %") are now in-scope by their fixed name.
        let lines = text.components(separatedBy: .newlines)
        let cleanedLines = lines.map { line -> String in
            if shouldApplyPercentFixes(to: line) {
                return applyPercentFixes(to: line)
            }
            return line
        }
        text = cleanedLines.joined(separator: "\n")

        // Step 4 — line dedup. Some labels print the same string twice
        // (e.g. Kynd labels show the strain name on the package then again
        // on the inventory tag, and ship multiple Metrc tags). Keep only the
        // first occurrence; we save tokens with no information loss.
        text = dedupLines(text)
        return text
    }

    /// Drop duplicate lines, preserving order. Case-insensitive,
    /// whitespace-trimmed equality. Empty lines are not deduped — they're
    /// preserved as separators.
    static func dedupLines(_ text: String) -> String {
        var seen = Set<String>()
        var out: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let key = line.trimmingCharacters(in: .whitespaces).lowercased()
            if key.isEmpty {
                out.append(line)
                continue
            }
            if seen.insert(key).inserted {
                out.append(line)
            }
        }
        return out.joined(separator: "\n")
    }

    // MARK: - Boilerplate stripping

    /// Phrases (case-insensitive substring match) that mark a line as
    /// regulatory boilerplate to drop. Designed to be OCR-resilient — short,
    /// distinctive fragments that survive common character substitutions
    /// (h→n, b→D, v→y) and missing letters. Each phrase should be unique
    /// enough to regulatory text that legitimate cannabis fields never hit.
    private static let boilerplatePhrases: [String] = [
        // FDA disclaimer fragments
        "food and drug",
        "evaluated",         // "has not been evaluated" / OCR variants
        "diagnose",          // distinctive — only appears in disclaimer
        "diagnose, treat, cure",
        "cure, or prevent",
        // Age restriction fragments
        "adults 21",
        "21 years",
        "age or older",
        "for resale",
        // Children warning fragments
        "keep out of",       // "reach of children" / OCR "the reach of cailanen"
        "out of reach",
        "reach of",
        "safe for kids",
        // Pregnancy warning fragments — bare "breast" catches breasteeding too
        "pregnant",
        "breast",
        "becoming pregnant",
        // Operate warnings
        "motor vehicle",
        "motor venicle",     // OCR: v→n
        "heavy machinery",
        "neavy macninery",   // OCR variant
        "machinery",         // bare — distinctive in label context
        // Poison control fragments
        "poison",            // bare — distinctive ("National Poison Control" / OCR "poison contol")
        "1-800-222-1222",
        "222-1222",
        "222 - 1222",
        // Generic boilerplate markers
        "consumption of this product",
        "health risk",
        "nealth risk",       // OCR variant
        "not intended",
        "potential allergens",
        "inactive ingredient",
        "pesticides used",
        "requires refrigeration",
        "requires retrigeration",
        "directions:",
        "irections:",        // OCR drops leading 'd'
        "tiractione",        // observed OCR variant of "Directions"
        "inhale",            // "Light and inhale" — distinctive in cannabis label context
        "serving size",
        "servings per",
        "se ving size",      // OCR variant
        "serings per",       // OCR variant
        "per unit",
        // Storage instructions
        "storage:",
        "store in a cool",
        "store in cool",
        // Other intended-use boilerplate
        "this product is intended",
        "product is intended t",  // catches "intended to" / "intended 1ol" OCR variants
        "this product contains cannabis",
        "contains cannabis"
    ]

    /// Patterns (regex) that mark a line as boilerplate.
    private static let boilerplatePatterns: [String] = [
        // US phone numbers in various formats. Both parens are optional to
        // tolerate OCR dropping one (observed: "848) 999-2005" — opening paren
        // missing).
        #"\(?\d{3}\)?\s*\d{3}\s*-\s*\d{4}"#,
        #"\b\d{3}\.\d{3}\.\d{4}\b"#,
        // ZIP-with-state-and-comma patterns common in addresses.
        #"\b[A-Z]{2}[,.]\s*\d{5}\b"#,
        // Street addresses starting with a number then street type word.
        #"^\s*\d+\s+\w+.*\b(street|st\.?|road|rd\.?|drive|dr\.?|highway|hwy\.?|avenue|ave\.?|lane|ln\.?|boulevard|blvd\.?)\b"#,
        // Batch/lot identifier lines like "9 - 120925- Blueberry Caviar" — a
        // small index, a long date-or-lot number, then a batch name. The FM
        // otherwise pulls "9" and "120925" into totalThc / totalCannabinoids
        // (observed on the Zips canary: totalCannabinoids = 120925). These
        // carry no schema field, so dropping the whole line is safe.
        #"^\s*\d{1,3}\s*-\s*\d{5,}\s*-"#
    ]

    static func stripBoilerplate(_ text: String) -> String {
        let lower = text.lowercased()
        // First, fast substring scan to avoid building regexes when nothing
        // boilerplate-shaped is present.
        let hasAnyPhrase = boilerplatePhrases.contains { lower.contains($0) }
        // .anchorsMatchLines so a `^`-anchored pattern (street address, lot
        // code) is detected anywhere in the multi-line text, not only at the
        // very start — the precheck below runs against the whole text.
        let hasAnyPattern = boilerplatePatterns.contains { pattern in
            (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines]))
                .flatMap { regex in
                    regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text))
                } != nil
        }
        if !hasAnyPhrase && !hasAnyPattern { return text }

        let compiledPatterns: [NSRegularExpression] = boilerplatePatterns.compactMap {
            try? NSRegularExpression(pattern: $0, options: [.caseInsensitive, .anchorsMatchLines])
        }

        let lines = text.components(separatedBy: .newlines)
        let kept = lines.filter { line in
            let lower = line.lowercased()
            if boilerplatePhrases.contains(where: { lower.contains($0) }) {
                return false
            }
            let range = NSRange(line.startIndex..., in: line)
            for regex in compiledPatterns {
                if regex.firstMatch(in: line, options: [], range: range) != nil {
                    return false
                }
            }
            return true
        }
        return kept.joined(separator: "\n")
    }

    // MARK: - Name fixes

    private static func applyNameFixes(_ text: String) -> String {
        var out = text
        let terpeneFixes: [(String, String)] = [
            ("Betataryophyllene", "BetaCaryophyllene"),
            ("Beta-taryophyllene", "Beta-Caryophyllene"),
            ("Betacanopnyllene", "BetaCaryophyllene"),
            ("Betacanophyllene", "BetaCaryophyllene"),
            ("setacanophymene", "BetaCaryophyllene"),
            ("setacanopnyllene", "BetaCaryophyllene"),
            ("canophylleneoxide", "CaryophylleneOxide"),
            ("canophyllenexide", "CaryophylleneOxide"),
            ("CaryoptylleneOxide", "CaryophylleneOxide"),
            ("Bisabolot", "Bisabolol"),
            ("Bisa Dolol", "Bisabolol"),
            ("Bisa Doto1", "Bisabolol"),
            ("Bisa DolOl", "Bisabolol"),
            ("Lim onene", "Limonene"),
            ("Linaool", "Linalool"),
            ("Lina1o0i", "Linalool"),
            ("Lina1oi", "Linalool"),
            ("BetaMyrcene", "Beta-Myrcene"),
            ("Beta Myrcene", "Beta-Myrcene"),
            ("BetaMycene", "Beta-Myrcene"),
            ("Beta Mycene", "Beta-Myrcene"),
            ("AlphaPinene", "Alpha-Pinene"),
            ("ipraPinene", "Alpha-Pinene"),
            ("BetaPinene", "Beta-Pinene"),
            ("Beta Pinene", "Beta-Pinene"),
            ("Teroinsiene", "Terpinolene"),
            ("Terpinglene", "Terpinolene"),
            // "Betainene" is the OCR rendering of "BetaPinene" on cylindrical
            // labels where the 'p' loses to image curvature. The 'n'
            // substitution looks unique enough to be safe.
            ("Betainene", "Beta-Pinene")
        ]
        for (from, to) in terpeneFixes {
            out = out.replacingOccurrences(of: from, with: to)
        }
        let cannabinoidFixes: [(String, String)] = [
            // OCR G↔O substitution on CBG/CBGA — colon-anchored to avoid
            // rewriting unrelated acronyms.
            ("CBO:", "CBG:"),
            ("CBOA:", "CBGA:"),
            // THC9 is a common OCR rendering of "Δ9-THC".
            ("THC9:", "Delta-9-THC:"),
            // Observed: "09THC:" for "Δ9-THC:" (number 0 substituted for delta glyph).
            ("09THC:", "Delta-9-THC:"),
            // "CED:" rendering of "CBD:" (E for B character substitution
            // observed on cylindrical labels with curved text).
            ("CED:", "CBD:"),
            // Observed: "TH Ca:" / "THCa:" with lowercase 'a' rendering.
            ("THCa:", "THCA:"),
            ("TH Ca:", "THCA:"),
            // Observed: "Lie Number:" / "Lic Number:" → normalize to "License #".
            ("Lie Number:", "License #"),
            ("Lic Number:", "License #")
        ]
        for (from, to) in cannabinoidFixes {
            out = out.replacingOccurrences(of: from, with: to)
        }
        return out
    }

    // MARK: - Percent fixes (scoped per-line)

    /// Keywords that mark a line as in-scope for percent-noise replacement.
    /// All compared case-insensitively against the line content. Phrases used
    /// instead of bare "total" / "potency" to avoid over-matching non-cannabis
    /// text like "Total memory: 4 96 GB".
    private static let inScopeKeywords: [String] = [
        // Cannabinoids
        "thc", "thca", "thcv", "cbd", "cbg", "cbc",
        "delta-9", "delta9", "δ9", "cannabinoid",
        // Terpenes
        "myrcene", "limonene", "linalool", "caryophyllene", "pinene",
        "humulene", "bisabolol", "terpinolene", "ocimene", "farnesene",
        "terpene", "terpenes", "bisabolene",
        // Section/total markers — full phrases only, not bare "total".
        "potency analysis", "terpene contents",
        "total cannabinoids", "total terpenes", "total thc", "total cbd"
    ]

    /// A line is in-scope when it contains a cannabinoid/terpene keyword, OR
    /// it consists solely of a numeric value plus a known percent-noise suffix
    /// (a "standalone value line" in the two-column layout).
    private static func shouldApplyPercentFixes(to line: String) -> Bool {
        let lower = line.lowercased()
        for keyword in inScopeKeywords where lower.contains(keyword) {
            return true
        }
        // Standalone-value pattern: optional whitespace + decimal + space +
        // noise suffix + optional whitespace.
        let standalonePattern = #"^\s*\d+(?:\.\d+)?(\s+(90|96|00|06|0%|9%|%%)|%0)\s*$"#
        if let regex = try? NSRegularExpression(pattern: standalonePattern) {
            let range = NSRange(line.startIndex..., in: line)
            if regex.firstMatch(in: line, options: [], range: range) != nil {
                return true
            }
        }
        return false
    }

    private static let percentNoisePatterns: [String] = [
        #"(\d+(?:\.\d+)?)\s+90\b"#,
        #"(\d+(?:\.\d+)?)\s+96\b"#,
        #"(\d+(?:\.\d+)?)\s+40\b"#,
        #"(\d+(?:\.\d+)?)\s+46\b"#,
        #"(\d+(?:\.\d+)?)\s+00\b"#,
        #"(\d+(?:\.\d+)?)\s+06\b"#,
        #"(\d+(?:\.\d+)?)\s+0%"#,
        #"(\d+(?:\.\d+)?)\s+9%"#,
        #"(\d+(?:\.\d+)?)\s+%%"#,
        #"(\d+(?:\.\d+)?)%0\b"#,
        // Trailing "ge" / "4e" / "9e" — observed on the Kynd label where the
        // percent glyph reads as italicised "e"-like characters.
        #"(\d+(?:\.\d+)?)\s+ge\b"#,
        #"(\d+(?:\.\d+)?)\s+4e\b"#,
        #"(\d+(?:\.\d+)?)\s+9e\b"#,
        // Korean/CJK character substitutions for "%" observed on real device.
        #"(\d+(?:\.\d+)?)\s+9신\b"#,
        #"(\d+(?:\.\d+)?)\s+신\b"#,
        // Cyrillic Ф / phi-like substitution.
        #"(\d+(?:\.\d+)?)\s+Ф"#,
        // Forward-slash as percent (observed: "35.45 /" meaning 35.45%).
        #"(\d+(?:\.\d+)?)\s+/(?!\d)"#
    ]

    private static func applyPercentFixes(to line: String) -> String {
        var line = line
        for pattern in percentNoisePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(line.startIndex..., in: line)
                line = regex.stringByReplacingMatches(
                    in: line,
                    options: [],
                    range: range,
                    withTemplate: "$1%"
                )
            }
        }
        return line
    }
}
