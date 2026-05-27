import Foundation

// ProductTypeInference — deterministic product-type signal from the explicit
// dosage-form wording printed on the label. The FM sometimes lets a
// sweet-sounding strain name (e.g. "…Candy") bias it toward .edible even when
// the label plainly says "Inhalable Product". This reads the authoritative
// printed text and returns a type ONLY when the signal is strong; nil means
// "no strong signal — defer to the model". Pure + unit-testable, no FM.
//
// Precedence in the pipeline: a saved user correction wins over this, which in
// turn wins over the raw FM guess.

enum ProductTypeInference {
    static func infer(ocrText: String) -> ProductType? {
        let lower = ocrText.lowercased()

        // Specific inhalables first (so "Inhalable Product" + "pre-roll" → preRoll).
        if lower.contains("pre-roll") || lower.contains("preroll") || lower.contains("pre roll") {
            return .preRoll
        }
        if lower.contains("vape") || lower.contains("cartridge")
            || lower.contains("disposable") || lower.contains("510 thread") {
            return .vape
        }
        // Generic inhalable wording — NJ-CRC labels print "Inhalable Product".
        // Defaults to flower, the dominant inhalable form.
        if lower.contains("inhalable") {
            return .flower
        }
        // Ingestible signals. Kept tight on purpose — no bare "candy"/"chocolate"
        // (those collide with strain names like Chocolope / Blue Candy Rain).
        if lower.contains("gummies") || lower.contains("gummy")
            || lower.contains("per serving") || lower.contains("servings per")
            || lower.contains("lozenge") {
            return .edible
        }
        if lower.contains("tincture") { return .tincture }
        if lower.contains("topical") || lower.contains("salve") || lower.contains("balm") {
            return .topical
        }
        return nil
    }
}
