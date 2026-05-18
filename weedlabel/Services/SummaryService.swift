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

    func summarize(_ label: CannabisLabel) async throws -> SummaryOutcome {
        if session == nil {
            session = LanguageModelSession(instructions: SummaryService.systemInstructions)
        }
        guard let session else { throw SummaryError.noSession }

        let promptText = Self.buildUserPrompt(label)

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
            return .deterministicFallback(text: Self.buildFallback(label), regenerationsTried: attempts)
        }

        return .ai(text: responseText, regenerationsTried: attempts)
    }

    // MARK: - System instructions

    private static let systemInstructions: String = """
    You write short informational summaries about NJ-CRC cannabis product labels \
    based on parsed cannabinoid and terpene data. You are a knowledgeable friend \
    describing chemistry, not a clinician. Rules:

    1. Ground every claim strictly in the parsed fields you are given.
    2. No medical claims (no "treats," "cures," "heals," "relieves," "prevents," \
       "reduces pain/anxiety/insomnia/nausea/symptoms").
    3. No helping-claim phrases ("will help," "helps with," "good for," "useful \
       for," "may help/relieve/reduce/treat").
    4. No second-person directives ("you should," "you'll feel," "you can take," \
       "take this when/if/for").
    5. No dosing language ("recommended dose," milligram dosing, "prescription").
    6. You may state effect direction in factual third-person terms based on \
       terpene profile: sedative-leaning, energizing-leaning, relaxing-leaning.
    7. Keep responses to 2-3 sentences total. Plain prose, no markdown.
    """

    // MARK: - User prompt

    private static func buildUserPrompt(_ label: CannabisLabel) -> String {
        var lines: [String] = []
        lines.append("Strain: \(label.strainName)")
        lines.append("Cultivator: \(label.cultivator)")
        lines.append("Product type: \(String(describing: label.productType))")

        let c = label.cannabinoids
        var cannas: [String] = []
        if let v = c.thca { cannas.append("THCA \(format(v))%") }
        if let v = c.delta9thc { cannas.append("Δ9-THC \(format(v))%") }
        if let v = c.cbd { cannas.append("CBD \(format(v))%") }
        if let v = c.cbda { cannas.append("CBDA \(format(v))%") }
        if let v = c.cbg { cannas.append("CBG \(format(v))%") }
        if let v = c.cbga { cannas.append("CBGA \(format(v))%") }
        if let v = c.totalCannabinoids { cannas.append("total cannabinoids \(format(v))%") }
        if let v = label.computedTotalThc { cannas.append("computed Total THC \(format(v))%") }
        lines.append("Cannabinoids: \(cannas.joined(separator: ", "))")

        let t = label.terpenes
        var terps: [String] = []
        if let v = t.myrcene { terps.append("myrcene \(format(v))%") }
        if let v = t.limonene { terps.append("limonene \(format(v))%") }
        if let v = t.linalool { terps.append("linalool \(format(v))%") }
        if let v = t.betaCaryophyllene { terps.append("β-caryophyllene \(format(v))%") }
        if let v = t.pinene { terps.append("pinene \(format(v))%") }
        if let v = t.humulene { terps.append("humulene \(format(v))%") }
        for entry in t.other {
            terps.append("\(entry.name) \(format(entry.percent))%")
        }
        if let v = t.total { terps.append("total \(format(v))%") }
        lines.append("Terpenes: \(terps.joined(separator: ", "))")

        if let chemo = label.chemotype {
            lines.append("Chemotype (per NJAC §17:30-16.3(b)(11)): \(chemo)")
        }

        let body = lines.joined(separator: "\n")
        return """
        Write a 2-3 sentence informational summary about this product's chemistry. \
        Apply the rules in your instructions strictly.

        Parsed label:
        \(body)
        """
    }

    private static func format(_ d: Double) -> String {
        String(format: "%.2f", d)
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

    static func buildFallback(_ label: CannabisLabel) -> String {
        var pieces: [String] = []

        // Top 2 cannabinoids by percentage
        let allCannas: [(String, Double)] = [
            ("THCA", label.cannabinoids.thca ?? 0),
            ("Δ9-THC", label.cannabinoids.delta9thc ?? 0),
            ("CBG", label.cannabinoids.cbg ?? 0),
            ("CBD", label.cannabinoids.cbd ?? 0),
            ("CBDA", label.cannabinoids.cbda ?? 0),
            ("CBGA", label.cannabinoids.cbga ?? 0)
        ]
        let nonZero: [(String, Double)] = allCannas.filter { $0.1 > 0 }
        let cannaPairs: [(String, Double)] = nonZero.sorted { $0.1 > $1.1 }

        let topCannas: [String] = cannaPairs.prefix(2).map { pair in
            "\(pair.0) \(format(pair.1))%"
        }
        if !topCannas.isEmpty {
            pieces.append(topCannas.joined(separator: ", "))
        }

        // Effect-direction lookup based on dominant terpenes
        let terpEntries: [(String, Double)] = {
            var arr: [(String, Double)] = []
            if let v = label.terpenes.myrcene { arr.append(("myrcene", v)) }
            if let v = label.terpenes.limonene { arr.append(("limonene", v)) }
            if let v = label.terpenes.linalool { arr.append(("linalool", v)) }
            if let v = label.terpenes.betaCaryophyllene { arr.append(("β-caryophyllene", v)) }
            if let v = label.terpenes.pinene { arr.append(("pinene", v)) }
            if let v = label.terpenes.humulene { arr.append(("humulene", v)) }
            return arr.sorted { $0.1 > $1.1 }
        }()

        if let top = terpEntries.first {
            let direction = effectDirection(for: top.0)
            pieces.append("\(direction)-leaning terpene profile dominated by \(top.0)")
        }

        if pieces.isEmpty {
            return "Numbers look unusual — verify against the printed label."
        }
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
