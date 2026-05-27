import Foundation

// FieldDetector — pure helpers that scan in-flight OCR text for the presence
// of canonical NJ-CRC fields. Used by ScanModel to drive the live "fields
// detected" chip row and to gate the Capture button on a quality threshold.
//
// These are PRESENCE checks, not extraction. They don't pull the actual value
// — they just answer "did the live OCR pick up at least the signature of a
// license number / Metrc tag / potency block / terpene block?" The real
// extraction happens later through the Foundation Models @Generable step.

enum DetectedField: String, CaseIterable, Sendable {
    case license
    case metrcTag
    case potency
    case terpenes
    case qrCode

    var displayName: String {
        switch self {
        case .license: return "License"
        case .metrcTag: return "Metrc"
        case .potency: return "Potency"
        case .terpenes: return "Terpenes"
        case .qrCode: return "QR"
        }
    }
}

enum FieldDetector {
    /// Returns the set of canonical fields whose signature appears in `ocrText`
    /// plus whether `qrCodes` is non-empty.
    static func detect(ocrText: String, qrCodes: [String]) -> Set<DetectedField> {
        var found: Set<DetectedField> = []
        if !qrCodes.isEmpty {
            found.insert(.qrCode)
        }
        if hasLicense(ocrText) { found.insert(.license) }
        if hasMetrcTag(ocrText) { found.insert(.metrcTag) }
        if hasPotency(ocrText) { found.insert(.potency) }
        if hasTerpenes(ocrText) { found.insert(.terpenes) }
        return found
    }

    /// Quality threshold for enabling the Capture button. Three out of five
    /// fields gives a strong signal that we have a real label in frame, while
    /// remaining tolerant of common OCR-misses (e.g. QR not visible at this
    /// angle, terpene panel not yet in frame).
    static let captureThresholdFieldCount: Int = 3

    static func meetsCaptureThreshold(_ fields: Set<DetectedField>) -> Bool {
        fields.count >= captureThresholdFieldCount
    }

    // MARK: - Individual detectors

    /// NJ-CRC license numbers are typically "C######" (one letter + 6 digits).
    /// We accept 5–7 digits for robustness across municipalities and an
    /// optional leading word boundary token like "License #".
    static func hasLicense(_ text: String) -> Bool {
        contains(text, pattern: #"\bC\d{5,7}\b"#)
    }

    /// Metrc seed-to-sale tags are 24 characters beginning with "1A4". We allow
    /// 22–26 for OCR fuzz and require the "1A4" prefix.
    static func hasMetrcTag(_ text: String) -> Bool {
        contains(text, pattern: #"\b1A4[0-9A-Za-z]{19,23}\b"#)
    }

    /// Potency block signature: a cannabinoid acronym followed by a number,
    /// or any cannabinoid keyword + percent sign nearby on the same line.
    static func hasPotency(_ text: String) -> Bool {
        // Cheap first pass: keyword presence.
        let lower = text.lowercased()
        let keywords = ["thca", "thcv", "delta-9", "delta9", "δ9-thc", "cbg", "cbc"]
        if keywords.contains(where: { lower.contains($0) }) {
            return true
        }
        // Bare "thc" / "cbd" are common false-positive substrings (e.g. inside
        // longer words), so require a colon, percent sign, or digit nearby.
        return contains(text, pattern: #"(?i)\b(thc|cbd)\b[\s:]+\d"#)
    }

    /// Terpene block signature: any named terpene we know about.
    static func hasTerpenes(_ text: String) -> Bool {
        let lower = text.lowercased()
        let terpenes = [
            "myrcene", "limonene", "linalool", "caryophyllene", "pinene",
            "humulene", "bisabolol", "terpinolene", "ocimene", "farnesene",
            "terpene"
        ]
        return terpenes.contains(where: { lower.contains($0) })
    }

    private static func contains(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
}
