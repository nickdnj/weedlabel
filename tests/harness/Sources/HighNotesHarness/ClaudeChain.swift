import Foundation

// Claude-side analogues of ExtractionService (Pass A) and SummaryService
// (Pass B). The whole point of the harness is comparison fairness: Claude must
// see the SAME instructions and the SAME user prompts we send to Foundation
// Models. So every string here is pulled directly from the shared production
// services — never re-typed.
//
// HighNotes extraction is TWO Foundation Models passes over smaller @Generable
// sub-schemas (LabelMetadata, then LabelChemistry), composed into a flat
// CannabisLabel. We mirror that exactly: two Claude calls, one per pass, each
// with the production per-pass instructions + the production per-pass user
// prompt + a JSON-schema appendix (the only Apple-vs-Claude divergence, since
// @Generable has no Claude analogue). The two JSON objects are merged and
// decoded straight into CannabisLabel — whose field values are identical to
// what the production `CannabisLabel(metadata:chemistry:)` composer produces.

enum ClaudeChain {

    // MARK: - Pass A — extraction (two sub-passes, mirroring ExtractionService)

    /// Schema appendix for the METADATA pass. Mirrors the @Guide descriptions on
    /// LabelMetadata so Claude sees the same field guidance the @Generable schema
    /// encodes for Foundation Models.
    static let metadataSchemaAppendix: String = """


    OUTPUT FORMAT — respond with valid JSON only, no preamble, no markdown fence. \
    The JSON object must match this schema exactly:
    {
      "strainName": string,        // full cultivar name only; strip brand + weight; reassemble names that wrap across two lines; NEVER a terpene, cannabinoid, or lot/batch-code line
      "cultivator": string,        // cultivator business name
      "licenseNumber": string | null,   // e.g. "C000186"
      "metrcTag": string | null,         // Metrc tag, ~24 chars starting "1A4"
      "netWeight": string | null,        // includes unit, e.g. "28g"
      "harvestDate": string | null,      // ISO YYYY-MM-DD
      "expirationDate": string | null,   // ISO YYYY-MM-DD
      "productType": one of "flower" | "vape" | "edible" | "concentrate" | "preRoll" | "tincture" | "topical" | "other",
      "qrCodes": [string]                // opaque barcode payloads only (e.g. Metrc tags); never readable text
    }
    Use null (not empty string) for fields that are not printed. qrCodes is [] \
    when none. Copy values verbatim. Do NOT include any other keys.
    """

    /// Schema appendix for the CHEMISTRY pass. Mirrors the @Guide descriptions on
    /// LabelChemistry.
    static let chemistrySchemaAppendix: String = """


    OUTPUT FORMAT — respond with valid JSON only, no preamble, no markdown fence. \
    The JSON object must match this schema exactly (every value a number or null):
    {
      "thca": number | null,
      "delta9thc": number | null,        // Δ9-THC percent; always small (<5% on flower); NOT a bare "THC:" total
      "cbd": number | null,
      "cbg": number | null,
      "totalCannabinoids": number | null,
      "totalThc": number | null,         // a bare "THC:" line in the totals area goes here
      "totalCbd": number | null,
      "myrcene": number | null,
      "limonene": number | null,
      "linalool": number | null,
      "betaCaryophyllene": number | null,
      "pinene": number | null,           // AlphaPinene and BetaPinene both contribute here
      "humulene": number | null,
      "totalTerpenes": number | null
    }
    All values are percentages as printed. Use null (not 0) for fields not \
    printed. Copy values verbatim — never compute or estimate. Do NOT include \
    any other keys.
    """

    /// Run BOTH Claude sub-passes and compose a CannabisLabel. `safeOcr` is the
    /// preprocessed+clamped OCR text — byte-identical to what ExtractionService
    /// feeds Foundation Models internally.
    static func extractViaClaude(safeOcr: String, client: ClaudeClient) async throws -> ClaudePassAResult {
        // Pass 1 — metadata. Verbatim production instructions + production prompt.
        let metaRaw = try await client.respond(
            system: ExtractionService.metadataInstructions + metadataSchemaAppendix,
            user: ExtractionService.metadataPrompt(safeOcr)
        )
        // Pass 2 — chemistry.
        let chemRaw = try await client.respond(
            system: ExtractionService.chemistryInstructions + chemistrySchemaAppendix,
            user: ExtractionService.chemistryPrompt(safeOcr)
        )

        guard let metaDict = jsonObject(from: metaRaw) else {
            return ClaudePassAResult(label: nil, metadataRaw: metaRaw, chemistryRaw: chemRaw,
                                     parseError: "metadata pass: no decodable JSON object found")
        }
        let chemDict = jsonObject(from: chemRaw) ?? [:]

        // Merge the two passes into one CannabisLabel-shaped dict, then decode
        // through the production Codable. Field values match exactly what
        // CannabisLabel(metadata:chemistry:) would compose.
        var merged = metaDict
        for (k, v) in chemDict { merged[k] = v }
        sanitize(&merged)

        guard let data = try? JSONSerialization.data(withJSONObject: merged),
              let label = try? JSONDecoder().decode(CannabisLabel.self, from: data) else {
            return ClaudePassAResult(label: nil, metadataRaw: metaRaw, chemistryRaw: chemRaw,
                                     parseError: "compose/decode failed (merged JSON did not match CannabisLabel)")
        }
        return ClaudePassAResult(label: label, metadataRaw: metaRaw, chemistryRaw: chemRaw, parseError: nil)
    }

    // MARK: - Pass B — summary (mirror of SummaryService)

    /// System prompt is SummaryService.systemInstructions; user prompt is exactly
    /// SummaryService.buildUserPrompt(label, strainInsight:) — the SAME text the
    /// app sends Foundation Models. We then run BOTH production guards on the
    /// result (the P6 denylist AND the %-hallucination guard) for parity — Claude
    /// is flagged, not mutated (it has no on-device regenerate/fallback loop).
    static func summarizeViaClaude(
        label: CannabisLabel,
        strainInsight: StrainInsight?,
        client: ClaudeClient
    ) async throws -> ClaudePassBResult {
        let system = SummaryService.systemInstructions
        let user = SummaryService.buildUserPrompt(label, strainInsight: strainInsight)
        let raw = try await client.respond(system: system, user: user)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        let denylistViolation = SummaryService.firstViolation(in: trimmed)
        let hallucinated = SummaryService.summaryMentionsHallucinatedPercentages(trimmed, against: label)
        var notes: [String] = []
        if let v = denylistViolation { notes.append(v) }
        if hallucinated { notes.append("hallucinated percentage(s)") }
        let violation = notes.isEmpty ? nil : notes.joined(separator: " + ")
        return ClaudePassBResult(text: trimmed, violation: violation, userPrompt: user)
    }

    // MARK: - JSON helpers

    /// Coerce the merged dict into something CannabisLabel's Codable accepts:
    /// fill required fields, normalize productType to a storageKey, and turn
    /// numeric-looking strings into numbers.
    private static func sanitize(_ dict: inout [String: Any]) {
        // Required non-optionals.
        if !(dict["strainName"] is String) { dict["strainName"] = "" }
        if !(dict["cultivator"] is String) { dict["cultivator"] = "" }
        if !(dict["qrCodes"] is [Any]) { dict["qrCodes"] = [] }

        // productType → stable storageKey string (CannabisLabel decodes it via
        // ProductType(storageKey:)). Normalize common spellings; default .other.
        let known: Set<String> = ["flower", "vape", "edible", "concentrate", "preRoll", "tincture", "topical", "other"]
        if let raw = dict["productType"] as? String {
            dict["productType"] = normalizeProductType(raw, known: known)
        } else {
            dict["productType"] = "other"
        }

        // Numeric fields: coerce "29.73" → 29.73; drop NSNull / unparseable.
        let numericKeys = [
            "thca", "delta9thc", "cbd", "cbg", "totalCannabinoids", "totalThc", "totalCbd",
            "myrcene", "limonene", "linalool", "betaCaryophyllene", "pinene", "humulene", "totalTerpenes"
        ]
        for k in numericKeys {
            guard let v = dict[k] else { continue }
            if v is NSNull { dict[k] = nil; continue }
            if v is NSNumber { continue }
            if let s = v as? String {
                let cleaned = s.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
                if let d = Double(cleaned) { dict[k] = d } else { dict[k] = nil }
            }
        }
    }

    private static func normalizeProductType(_ raw: String, known: Set<String>) -> String {
        if known.contains(raw) { return raw }
        let lower = raw.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        switch lower {
        case "flower": return "flower"
        case "vape", "cartridge", "vapecartridge", "disposable": return "vape"
        case "edible", "gummy", "gummies": return "edible"
        case "concentrate", "extract", "rosin", "resin": return "concentrate"
        case "preroll", "prerolls", "joint": return "preRoll"
        case "tincture": return "tincture"
        case "topical", "salve", "balm": return "topical"
        default: return "other"
        }
    }

    /// Tolerate the model wrapping JSON in ```json fences or stray prose by
    /// extracting the first balanced {...} block and parsing it.
    static func jsonObject(from text: String) -> [String: Any]? {
        guard let json = extractJSONObject(from: text),
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    private static func extractJSONObject(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") { return trimmed }
        guard let start = trimmed.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escape = false
        var end: String.Index?
        var i = start
        while i < trimmed.endIndex {
            let c = trimmed[i]
            if escape { escape = false }
            else if c == "\\" { escape = true }
            else if c == "\"" { inString.toggle() }
            else if !inString {
                if c == "{" { depth += 1 }
                else if c == "}" {
                    depth -= 1
                    if depth == 0 { end = i; break }
                }
            }
            i = trimmed.index(after: i)
        }
        guard let end else { return nil }
        return String(trimmed[start...end])
    }
}

struct ClaudePassAResult: Sendable {
    let label: CannabisLabel?
    let metadataRaw: String
    let chemistryRaw: String
    let parseError: String?
}

struct ClaudePassBResult: Sendable {
    let text: String
    /// Set when the production P6 denylist OR the %-hallucination guard would
    /// trip on Claude's output (parity check; Claude is flagged, not mutated).
    let violation: String?
    let userPrompt: String
}
