import Foundation
import FoundationModels

// SummaryService — wraps the Foundation Models AI summary call with the P6
// validator pipeline:
//   1. Generate summary, grounded in parsed CannabisLabel fields.
//   2. Validate against regex denylist (medical claims, second-person directives,
//      dosing language).
//   3. If violation, regenerate up to 2 times with conditioning prompt.
//   4. If still violating, fall back to deterministic field-only summary.
// Per the eng spec, the regex is a floor; the system prompt is the primary
// enforcement.

actor SummaryService {
    private var session: LanguageModelSession?

    func warm() {
        if session == nil {
            session = LanguageModelSession(
                instructions: SummaryService.systemInstructions
            )
        }
    }

    func summarize(_ label: CannabisLabel, strainInsight: StrainInsight? = nil) async throws -> SummaryOutcome {
        // FRESH session per call (see ExtractionService): a reused session
        // accumulates context across scans and degrades output. The regenerate
        // loop below intentionally reuses THIS call's session — its conditioning
        // prompt refers to "your previous response".
        let session = LanguageModelSession(instructions: SummaryService.systemInstructions)

        let promptText = Self.buildUserPrompt(label, strainInsight: strainInsight)

        // First attempt
        var responseText = try await session.respond(to: Prompt(promptText)).content

        var attempts = 0
        while let violation = Self.firstViolation(in: responseText), attempts < 2 {
            attempts += 1
            let conditioned = """
            Your previous response contained a policy violation: \(violation). \
            Rewrite the summary about this product's chemistry without medical \
            claims, second-person directives, or dose language. Keep it grounded \
            in the parsed fields.
            """
            responseText = try await session.respond(to: Prompt(conditioned)).content
        }

        if Self.firstViolation(in: responseText) != nil {
            return .deterministicFallback(text: Self.buildFallback(label, strainInsight: strainInsight), regenerationsTried: attempts)
        }

        // Hallucination guard: every "NN.N%" figure the summary mentions must
        // appear in the parsed label (within ±0.5% rounding tolerance).
        // Otherwise the model has invented numbers, and we fall back to the
        // deterministic summary that's grounded in real data only.
        if Self.summaryMentionsHallucinatedPercentages(responseText, against: label) {
            return .deterministicFallback(text: Self.buildFallback(label, strainInsight: strainInsight), regenerationsTried: attempts)
        }

        return .ai(text: responseText, regenerationsTried: attempts)
    }

#if DEBUG
    /// Debug-only: run summarization with custom system instructions. Returns
    /// the raw model response plus the violation outcome from the P6 validator.
    /// Used by the in-app Prompt Lab.
    struct CustomRunResult: Sendable {
        let rawResponse: String
        let violation: String?
        let outcome: SummaryOutcome
        let promptSent: String
    }

    func summarizeWithCustomInstructions(
        _ label: CannabisLabel,
        instructions: String
    ) async throws -> CustomRunResult {
        let promptText = Self.buildUserPrompt(label)
        let oneShot = LanguageModelSession(instructions: instructions)
        let response = try await oneShot.respond(to: Prompt(promptText)).content
        let violation = Self.firstViolation(in: response)
        let hallucinated = Self.summaryMentionsHallucinatedPercentages(response, against: label)
        let outcome: SummaryOutcome
        let combinedReason: String?
        if let v = violation {
            outcome = .deterministicFallback(text: Self.buildFallback(label), regenerationsTried: 0)
            combinedReason = v
        } else if hallucinated {
            outcome = .deterministicFallback(text: Self.buildFallback(label), regenerationsTried: 0)
            combinedReason = "hallucinated percentage(s)"
        } else {
            outcome = .ai(text: response, regenerationsTried: 0)
            combinedReason = nil
        }
        return CustomRunResult(rawResponse: response, violation: combinedReason, outcome: outcome, promptSent: promptText)
    }
#endif

    // MARK: - System instructions

    static let systemInstructions: String = """
    You write a short, factual reference description of a cannabis product's \
    aroma and chemistry for an informational catalog. Neutral and descriptive — \
    not promotional, not advice. Describe; do not recommend or encourage use. \
    Rules:

    1. Ground every statement strictly in the parsed fields provided. If aroma \
       notes are given for a terpene, describe them factually (e.g. bright \
       citrus, earthy musk, peppery spice, soft floral, fresh pine).
    2. Open with the dominant aroma or the strain's chemotype, then note the \
       significant figures present. Keep it plain and informative.
    3. If chemistry data is sparse, describe the terpene/aroma profile and the \
       sativa/indica/hybrid classification factually. NEVER invent or estimate \
       percentages that weren't provided.
    4. No medical claims ("treats," "cures," "heals," "relieves," "prevents," \
       "reduces pain/anxiety/insomnia/nausea/symptoms").
    5. No helping-claim phrases ("will help," "helps with," "good for," "useful \
       for," "may help/relieve/reduce/treat").
    6. No second-person directives. Describe in neutral third person.
    7. No dosing language ("recommended dose," milligram dosing, "prescription").
    8. You may note effect direction in factual third-person terms from the \
       terpene profile or the Classification line (sativa/indica/hybrid, \
       energizing/relaxing/balanced, daytime/evening).
    9. Keep it to 2-3 plain sentences. No markdown, no emoji.
    """

    // MARK: - User prompt

    // `internal` (not `private`) so the eval harness's Claude side can send the
    // byte-identical user prompt — comparison fairness depends on Apple and
    // Claude seeing the exact same parsed-label text. See tests/harness/.
    static func buildUserPrompt(_ label: CannabisLabel, strainInsight: StrainInsight? = nil) -> String {
        var lines: [String] = []
        lines.append("Strain: \(label.strainName)")
        lines.append("Cultivator: \(label.cultivator)")
        lines.append("Product type: \(String(describing: label.productType))")
        if let strainInsight {
            // Deterministic, trustworthy classification + flavor character. Fed
            // as grounded facts the summary may reference (qualitative, so they
            // pass the percentage-based hallucination guard untouched).
            lines.append("Classification: \(strainInsight.lean.displayName), \(strainInsight.lean.effectLanguage), suited to \(strainInsight.lean.timeOfDay)")
            lines.append("Typical character: \(strainInsight.characterNote)")
        }

        var cannas: [String] = []
        if let v = label.thca { cannas.append("THCA \(format(v))%") }
        if let v = label.delta9thc { cannas.append("Δ9-THC \(format(v))%") }
        if let v = label.cbd { cannas.append("CBD \(format(v))%") }
        if let v = label.cbg { cannas.append("CBG \(format(v))%") }
        if let v = label.totalCannabinoids { cannas.append("total cannabinoids \(format(v))%") }
        if let v = label.computedTotalThc { cannas.append("computed Total THC \(format(v))%") }
        if !cannas.isEmpty {
            lines.append("Cannabinoids: \(cannas.joined(separator: ", "))")
        }

        var terps: [String] = []
        if let v = label.myrcene { terps.append("myrcene \(format(v))% (\(aroma("myrcene")))") }
        if let v = label.limonene { terps.append("limonene \(format(v))% (\(aroma("limonene")))") }
        if let v = label.linalool { terps.append("linalool \(format(v))% (\(aroma("linalool")))") }
        if let v = label.betaCaryophyllene { terps.append("β-caryophyllene \(format(v))% (\(aroma("caryophyllene")))") }
        if let v = label.pinene { terps.append("pinene \(format(v))% (\(aroma("pinene")))") }
        if let v = label.humulene { terps.append("humulene \(format(v))% (\(aroma("humulene")))") }
        if let v = label.totalTerpenes { terps.append("total \(format(v))%") }
        if !terps.isEmpty {
            lines.append("Terpenes: \(terps.joined(separator: ", "))")
        }

        if let chemo = label.chemotype {
            lines.append("Chemotype (per NJAC §17:30-16.3(b)(11)): \(chemo)")
        }

        let body = lines.joined(separator: "\n")
        return """
        Write a 2-3 sentence factual description of this product's aroma and \
        chemistry. Lead with the aroma or chemotype, then note the significant \
        figures. Apply the rules in your instructions strictly.

        Parsed label:
        \(body)
        """
    }

    private static func format(_ d: Double) -> String {
        String(format: "%.2f", d)
    }

    /// Factual aroma/flavor notes per terpene. Fed into the prompt so the
    /// summary's sensory language stays grounded rather than invented. These
    /// are well-established descriptors, not effect/medical claims.
    static func aroma(_ terpene: String) -> String {
        switch terpene.lowercased() {
        case "myrcene": return "earthy, musky, herbal"
        case "limonene": return "bright citrus"
        case "linalool": return "soft floral, lavender"
        case "caryophyllene", "betacaryophyllene", "beta-caryophyllene": return "peppery, spicy, woody"
        case "pinene": return "fresh pine, herbal"
        case "humulene": return "hoppy, earthy, woody"
        case "terpinolene": return "fruity, piney"
        default: return "subtle herbal"
        }
    }

    // MARK: - Hallucination guard

    /// True if the summary mentions any "NN.N%" figure that isn't present
    /// (within ±0.5% rounding tolerance) in the parsed label's numeric
    /// fields. Used to reject summaries that invent percentages on labels
    /// where FM extraction returned mostly nulls.
    ///
    /// Tolerates the model rounding 27.52 → "27.5" or "28" but rejects
    /// completely fabricated figures like "18.3% THC" when the label has
    /// no cannabinoid data at all.
    static func summaryMentionsHallucinatedPercentages(
        _ summary: String,
        against label: CannabisLabel
    ) -> Bool {
        let summaryPercents = extractPercentages(from: summary)
        if summaryPercents.isEmpty { return false } // no claims to verify
        let labelPercents = collectAllPercentages(from: label)
        for sp in summaryPercents {
            // Allow ±0.5% rounding tolerance.
            let found = labelPercents.contains { abs($0 - sp) <= 0.5 }
            if !found { return true }
        }
        return false
    }

    /// Pull every "NN" / "NN.N" / "NN.NN" number that appears immediately
    /// before a percent sign in the text. Tolerates an optional space.
    static func extractPercentages(from text: String) -> [Double] {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*%"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        return matches.compactMap { m in
            Range(m.range(at: 1), in: text).flatMap { Double(text[$0]) }
        }
    }

    /// Every numeric percent-bearing field on the label. Used as the
    /// "ground truth" set the summary's percent claims are checked against.
    static func collectAllPercentages(from label: CannabisLabel) -> [Double] {
        let fields: [Double?] = [
            label.thca, label.delta9thc, label.cbd, label.cbg,
            label.totalCannabinoids, label.totalThc, label.totalCbd,
            label.myrcene, label.limonene, label.linalool,
            label.betaCaryophyllene, label.pinene, label.humulene,
            label.totalTerpenes,
            label.computedTotalThc, label.computedTotalCbd
        ]
        return fields.compactMap { $0 }
    }

    // MARK: - Validator (P6 regex denylist)

    /// Returns a short label naming the first detected violation, or nil if clean.
    static func firstViolation(in text: String) -> String? {
        let lower = text.lowercased()
        for (pattern, label) in Self.denylist {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(lower.startIndex..., in: lower)
                if regex.firstMatch(in: lower, options: [], range: range) != nil {
                    return label
                }
            }
        }
        return nil
    }

    /// Pattern → human label. Each pattern is a small group; keep them composable
    /// so unit tests can target individual classes.
    static let denylist: [(String, String)] = [
        // Medical-claim verbs
        (#"\b(treats?|cures?|heals?|prevents?|relieves?)\b"#, "medical claim verb"),
        (#"\breduces?\s+(pain|anxiety|stress|insomnia|nausea|symptoms?)\b"#, "reduces-symptom claim"),
        // Helping-claim phrases
        (#"\b(will help|helps with|good for|useful for)\b"#, "helping-claim phrase"),
        (#"\bmay\s+(help|relieve|reduce|treat)\b"#, "may-help phrase"),
        // Second-person directives
        (#"\byou\s+(should|will|can take|need)\b"#, "second-person directive"),
        (#"\byou'll\s+(feel|experience|notice)\b"#, "second-person directive"),
        (#"\btake this\s+(when|if|for|before|after)\b"#, "imperative dosing"),
        // Dosing language
        (#"\brecommended dose\b"#, "dose recommendation"),
        (#"\b\d+\s?mg\b"#, "explicit milligram dose"),
        (#"\bprescription\b"#, "prescription"),
        (#"\bdiagnose[ds]?\b"#, "diagnosis"),
        (#"\bmedical advice\b"#, "medical advice")
    ]

    // MARK: - Deterministic fallback (P6)
    //
    // Used when the FM summary is unavailable, trips a guardrail, hits a P6
    // violation, or hallucinates. Composed entirely from trustworthy parsed
    // data — no generation, no hallucination risk. Leads with the strain's
    // character/classification (which we can infer from the name even with zero
    // chemistry) so the result screen stays compelling rather than going blank.

    static func buildFallback(_ label: CannabisLabel, strainInsight: StrainInsight? = nil) -> String {
        var sentences: [String] = []
        let name = label.strainName.trimmingCharacters(in: .whitespacesAndNewlines)
        let strainLabel = name.isEmpty ? "This product" : name

        // Sentence 1 — strain character + classification (always available when
        // we have an insight; this is the "infer from the name" win).
        if let insight = strainInsight {
            sentences.append(
                "\(strainLabel) is \(insight.lean.displayName.lowercased()) — "
                + "\(insight.characterNote) in character, "
                + "\(insight.lean.effectLanguage), suited to \(insight.lean.timeOfDay)."
            )
        }

        // Sentence 2 — chemistry highlights, if any were extracted.
        let chemistryPiece = chemistryHighlights(label)
        if let chemistryPiece {
            sentences.append(chemistryPiece)
        }

        // Sentence 3 — honest note when the lab figures weren't legible.
        if chemistryPiece == nil {
            if sentences.isEmpty {
                // No insight and no chemistry — last resort, but still name the product.
                sentences.append(
                    "\(strainLabel): the lab figures and strain type weren't legible in this scan. "
                    + "Check the printed label for exact percentages."
                )
            } else {
                sentences.append("The lab figures weren't legible in this scan — check the printed label for exact percentages.")
            }
        }

        return sentences.joined(separator: " ")
    }

    /// One clause describing the standout cannabinoids + dominant terpene, or
    /// nil if no chemistry was extracted.
    private static func chemistryHighlights(_ label: CannabisLabel) -> String? {
        var pieces: [String] = []

        let allCannas: [(String, Double)] = [
            ("THCA", label.thca ?? 0),
            ("Δ9-THC", label.delta9thc ?? 0),
            ("CBG", label.cbg ?? 0),
            ("CBD", label.cbd ?? 0)
        ]
        let cannaPairs = allCannas.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
        let topCannas = cannaPairs.prefix(2).map { "\($0.0) \(format($0.1))%" }
        if !topCannas.isEmpty {
            pieces.append("Standout cannabinoids: \(topCannas.joined(separator: ", "))")
        }

        let terpEntries: [(String, Double)] = {
            var arr: [(String, Double)] = []
            if let v = label.myrcene { arr.append(("myrcene", v)) }
            if let v = label.limonene { arr.append(("limonene", v)) }
            if let v = label.linalool { arr.append(("linalool", v)) }
            if let v = label.betaCaryophyllene { arr.append(("β-caryophyllene", v)) }
            if let v = label.pinene { arr.append(("pinene", v)) }
            if let v = label.humulene { arr.append(("humulene", v)) }
            return arr.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
        }()

        if let top = terpEntries.first {
            pieces.append("a \(effectDirection(for: top.0))-leaning profile led by \(top.0) (\(aroma(top.0)))")
        }

        guard !pieces.isEmpty else { return nil }
        return pieces.joined(separator: "; ") + "."
    }

    /// Effect-direction lookup table — used by the deterministic fallback.
    private static func effectDirection(for terpene: String) -> String {
        switch terpene.lowercased() {
        case "myrcene", "linalool":
            return "sedative"
        case "limonene", "pinene":
            return "energizing"
        case "β-caryophyllene", "beta-caryophyllene", "caryophyllene", "humulene":
            return "relaxing"
        default:
            return "balanced"
        }
    }
}

// MARK: - Outcome

enum SummaryOutcome: Sendable {
    case ai(text: String, regenerationsTried: Int)
    case deterministicFallback(text: String, regenerationsTried: Int)

    var text: String {
        switch self {
        case .ai(let t, _), .deterministicFallback(let t, _): return t
        }
    }

    var didFallback: Bool {
        if case .deterministicFallback = self { return true }
        return false
    }
}

enum SummaryError: Error, Sendable {
    case noSession
}
