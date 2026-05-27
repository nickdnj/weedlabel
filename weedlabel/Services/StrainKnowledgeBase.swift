import Foundation

// StrainKnowledgeBase — on-device, deterministic strain interpretation. The
// reliable signal we GET from a scan is the strain name (+ sometimes an
// explicit S/I/H marker printed on the label). This maps that to a
// sativa/indica/hybrid lean and qualitative effect language WITHOUT any model
// generation — so there's zero hallucination risk and no network dependency.
//
// Resolution priority:
//   1. Explicit printed marker on the label ((S)/(I)/(H) or the words) — the
//      cultivator's own classification, authoritative.
//   2. Lineage inference from the strain name (Kush→indica, Haze→sativa, etc.).
//   3. Unknown — we say so rather than guessing.
//
// This is editorial knowledge, intentionally conservative. The phrasing avoids
// medical claims to stay within the same NJAC §17:30-16.3 guardrails as the
// FM summary (no "treats", "helps", dosing, etc.).

enum StrainLean: String, Sendable, Equatable, Codable, CaseIterable {
    case sativa
    case indica
    case hybrid
    case hybridSativa   // balanced hybrid, sativa-dominant
    case hybridIndica   // balanced hybrid, indica-dominant

    var displayName: String {
        switch self {
        case .sativa: return "Sativa-leaning"
        case .indica: return "Indica-leaning"
        case .hybrid: return "Hybrid"
        case .hybridSativa: return "Hybrid · Sativa-leaning"
        case .hybridIndica: return "Hybrid · Indica-leaning"
        }
    }

    /// Concise label for compact UI (e.g. picker rows).
    var shortLabel: String {
        switch self {
        case .sativa: return "Sativa"
        case .indica: return "Indica"
        case .hybrid: return "Hybrid (balanced)"
        case .hybridSativa: return "Hybrid, Sativa-leaning"
        case .hybridIndica: return "Hybrid, Indica-leaning"
        }
    }

    /// Factual, third-person effect-direction language. Deliberately hedged
    /// ("commonly associated with") and non-medical.
    var effectLanguage: String {
        switch self {
        case .sativa: return "commonly associated with energizing, uplifting effects"
        case .indica: return "commonly associated with relaxing, calming effects"
        case .hybrid: return "a balanced profile blending sativa and indica traits"
        case .hybridSativa: return "a balanced hybrid leaning toward energizing sativa traits"
        case .hybridIndica: return "a balanced hybrid leaning toward relaxing indica traits"
        }
    }

    var timeOfDay: String {
        switch self {
        case .sativa: return "daytime"
        case .indica: return "evening"
        case .hybrid: return "any time of day"
        case .hybridSativa: return "daytime to evening"
        case .hybridIndica: return "afternoon to evening"
        }
    }

    /// Generic aroma/character note used when no specific lineage character is
    /// known — keyed off the lean alone. A reasonable backstop so we can always
    /// say something evocative about the product.
    var generalCharacter: String {
        switch self {
        case .sativa: return "typically bright and aromatic"
        case .indica: return "typically rich and earthy"
        case .hybrid, .hybridSativa, .hybridIndica: return "a blended, layered character"
        }
    }
}

/// How we arrived at a lean — surfaced to the UI so the user knows whether it
/// came from the label itself, from name-based inference, or from a correction
/// the user saved locally.
enum StrainLeanSource: Sendable, Equatable {
    case userOverride           // user saved a local correction for this strain
    case printedMarker          // (S)/(I)/(H) or word printed on the label
    case lineage(String)        // inferred from a name fragment, e.g. "kush"
}

struct StrainInsight: Sendable, Equatable {
    let lean: StrainLean
    let source: StrainLeanSource

    /// One-line deterministic summary, e.g.
    /// "Hybrid · a balanced profile blending sativa and indica traits · any time of day".
    var headline: String {
        "\(lean.displayName) · \(lean.effectLanguage) · \(lean.timeOfDay)"
    }

    /// Short provenance note for the UI ("from label" vs "from name").
    var sourceNote: String {
        switch source {
        case .userOverride: return "your correction"
        case .printedMarker: return "from label marking"
        case .lineage(let fragment): return "inferred from name (\(fragment))"
        }
    }

    var isUserOverride: Bool {
        if case .userOverride = source { return true }
        return false
    }

    /// A flavor/character note for the strain. Uses the specific lineage
    /// character when we matched a known fragment; otherwise the lean's
    /// general character. Always non-nil so the summary can lean on it even
    /// when chemistry extraction comes back empty.
    var characterNote: String {
        if case .lineage(let fragment) = source,
           let specific = StrainKnowledgeBase.character(forFragment: fragment) {
            return specific
        }
        return lean.generalCharacter
    }
}

enum StrainKnowledgeBase {

    /// Compute the best available insight for a strain. Precedence:
    ///   1. A user-saved override (most intentional — the user looked at the
    ///      actual label and corrected us).
    ///   2. The printed label marker.
    ///   3. Name-based lineage inference.
    /// Returns nil when none apply.
    static func insight(strainName: String, ocrText: String, override: StrainLean? = nil) -> StrainInsight? {
        if let override {
            return StrainInsight(lean: override, source: .userOverride)
        }
        if let printed = detectPrintedClass(in: ocrText) {
            return StrainInsight(lean: printed, source: .printedMarker)
        }
        if let match = classify(strainName: strainName) {
            return StrainInsight(lean: match.lean, source: .lineage(match.fragment))
        }
        return nil
    }

    /// Normalize a strain name into a stable key for the override store.
    static func normalizedKey(_ strainName: String) -> String {
        strainName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    // MARK: - Printed marker detection

    /// Detect an explicit sativa/indica/hybrid marker in the OCR text. NJ-CRC
    /// labels commonly print "(S)", "(I)", "(H)" after the product name, or the
    /// spelled-out word. Word forms win over single-letter parenthetical forms
    /// when both somehow appear.
    static func detectPrintedClass(in ocrText: String) -> StrainLean? {
        let lower = ocrText.lowercased()
        // Spelled-out words first (most explicit).
        if lower.contains("hybrid") { return .hybrid }
        if lower.contains("sativa") { return .sativa }
        if lower.contains("indica") { return .indica }
        // Parenthetical single-letter markers: "(h)", "(s)", "(i)".
        // Require the parens to avoid matching stray letters.
        if matches(ocrText, pattern: #"\([Hh]\)"#) { return .hybrid }
        if matches(ocrText, pattern: #"\([Ss]\)"#) { return .sativa }
        if matches(ocrText, pattern: #"\([Ii]\)"#) { return .indica }
        return nil
    }

    // MARK: - Lineage character (flavor/aroma signal from the name)

    /// Flavor/character descriptors keyed by lineage fragment. These let the
    /// summary say something evocative purely from the strain name, even when
    /// chemistry extraction fails. Factual flavor descriptors only — no effect
    /// or medical claims.
    private static let lineageCharacter: [String: String] = [
        // Sativa-leaning
        "sour diesel": "pungent, diesel-and-citrus",
        "diesel": "pungent, fuel-forward",
        "haze": "spicy, citrus-and-incense",
        "jack herer": "piney, peppery",
        "jack": "piney, peppery",
        "durban": "sweet, anise-like",
        "green crack": "sharp, mango-citrus",
        "tangie": "bright tangerine",
        "lemon": "zesty lemon",
        "super silver": "spicy, citrus-skunk",
        "maui": "sweet pineapple",
        "trainwreck": "lemon-and-pine, peppery",
        // Indica-leaning
        "granddaddy purple": "sweet grape-and-berry",
        "grand daddy": "sweet grape-and-berry",
        "northern lights": "sweet, earthy-pine",
        "bubba": "earthy coffee-and-chocolate",
        "afghan": "rich, hashy-earth",
        "hindu": "spicy, sandalwood-earth",
        "purple punch": "grape-and-blueberry candy",
        "blueberry": "sweet ripe berry",
        "gorilla glue": "earthy, pungent pine",
        "kush": "earthy, pine-and-hash",
        "og": "earthy, pine-and-citrus-fuel",
        "grape": "sweet grape candy",
        "purple": "sweet, berry-forward",
        // Hybrid
        "girl scout cookies": "sweet, doughy-mint",
        "wedding cake": "sweet, vanilla-and-pepper",
        "gelato": "sweet, creamy dessert",
        "runtz": "fruity candy-sweet",
        "sherbet": "sweet, fruity-and-creamy",
        "sherbert": "sweet, fruity-and-creamy",
        "cookies": "sweet, doughy-vanilla",
        "cake": "sweet, rich vanilla",
        "zkittlez": "tropical fruit candy",
        "zkittles": "tropical fruit candy",
        "gushers": "tropical fruit-and-cream",
        "candy": "sweet, candy-like",
        "rainbow": "sweet, mixed-fruit",
        "mintz": "cool mint-and-cream",
        "mint": "cool, minty-herbal"
    ]

    /// Character note for a matched lineage fragment, if we have one.
    static func character(forFragment fragment: String) -> String? {
        lineageCharacter[fragment.lowercased()]
    }

    // MARK: - Lineage inference

    struct LineageMatch: Equatable {
        let lean: StrainLean
        let fragment: String
    }

    /// Lineage fragments → lean. Ordered most-specific first so multi-word
    /// fragments win over single tokens (e.g. "girl scout cookies" before
    /// "cookies"). Matched case-insensitively as substrings of the name.
    static let lineageTable: [(String, StrainLean)] = [
        // Sativa-leaning lineages
        ("sour diesel", .sativa),
        ("durban", .sativa),
        ("jack herer", .sativa),
        ("green crack", .sativa),
        ("maui", .sativa),
        ("tangie", .sativa),
        ("haze", .sativa),
        ("diesel", .sativa),
        ("jack", .sativa),
        ("trainwreck", .sativa),
        ("lemon", .sativa),       // lemon-forward cuts skew sativa/energetic
        ("super silver", .sativa),

        // Indica-leaning lineages
        ("granddaddy purple", .indica),
        ("grand daddy", .indica),
        ("northern lights", .indica),
        ("bubba", .indica),
        ("afghan", .indica),
        ("hindu", .indica),
        ("purple punch", .indica),
        ("blueberry", .indica),
        ("gorilla glue", .indica),
        ("og", .indica),          // OG Kush family
        ("kush", .indica),
        ("purple", .indica),
        ("grape", .indica),

        // Hybrid lineages
        ("girl scout cookies", .hybrid),
        ("wedding cake", .hybrid),
        ("gelato", .hybrid),
        ("runtz", .hybrid),
        ("sherbet", .hybrid),
        ("sherbert", .hybrid),
        ("cookies", .hybrid),
        ("cake", .hybrid),
        ("zkittlez", .hybrid),
        ("zkittles", .hybrid),
        ("gushers", .hybrid),
        ("mac", .hybrid),
        ("gmo", .hybrid),
        ("candy", .hybrid),
        ("rainbow", .hybrid),
        ("mintz", .hybrid),
        ("mint", .hybrid)
    ]

    /// Find the first lineage fragment that appears in the strain name.
    static func classify(strainName: String) -> LineageMatch? {
        let lower = strainName.lowercased()
        for (fragment, lean) in lineageTable where lower.contains(fragment) {
            return LineageMatch(lean: lean, fragment: fragment)
        }
        return nil
    }

    // MARK: - Helpers

    private static func matches(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
}
