import Foundation
import FoundationModels

// ExtractionService — wraps the Foundation Models extraction.
//
// TWO-PASS design: a single combined @Generable schema for the whole
// CannabisLabel kept overrunning the on-device 4096-token context (schema
// reflection + output reservation alone ran ~4000-4900 tokens). We split into
// two focused passes — metadata and chemistry — each with roughly half the
// schema, so each call lands comfortably under the limit. The two results
// compose into the flat CannabisLabel the rest of the app consumes.

actor ExtractionService {
    private var metadataSession: LanguageModelSession?
    private var chemistrySession: LanguageModelSession?

    func warm() {
        if metadataSession == nil {
            metadataSession = LanguageModelSession(instructions: Self.metadataInstructions)
        }
        if chemistrySession == nil {
            chemistrySession = LanguageModelSession(instructions: Self.chemistryInstructions)
        }
    }

    func extract(rawOcrText: String) async throws -> CannabisLabel {
        let safeOcr = Self.preprocessedOCR(rawOcrText, logPrefix: true)

        let metadataSession = self.metadataSession ?? {
            let s = LanguageModelSession(instructions: Self.metadataInstructions)
            self.metadataSession = s
            return s
        }()
        let chemistrySession = self.chemistrySession ?? {
            let s = LanguageModelSession(instructions: Self.chemistryInstructions)
            self.chemistrySession = s
            return s
        }()

        // Pass 1 — metadata.
        let metadata = try await metadataSession.respond(
            to: Prompt(Self.metadataPrompt(safeOcr)),
            generating: LabelMetadata.self
        ).content

        // Pass 2 — chemistry.
        let chemistry = try await chemistrySession.respond(
            to: Prompt(Self.chemistryPrompt(safeOcr)),
            generating: LabelChemistry.self
        ).content

        return CannabisLabel(metadata: metadata, chemistry: chemistry)
    }

    // MARK: - OCR prep

    private static func preprocessedOCR(_ raw: String, logPrefix: Bool) -> String {
        let cleaned = OCRPreprocessor.clean(raw)
        #if DEBUG
        if logPrefix {
            print("[CANARY] OCR preprocessor delta: \(raw.count) → \(cleaned.count) chars")
            if cleaned != raw {
                print("[CANARY] Cleaned OCR begin ===\n\(cleaned)\n=== Cleaned OCR end")
            }
        }
        #endif
        // Each pass sees the same OCR; cap for safety though the boilerplate
        // stripper keeps real labels well under this.
        if cleaned.count > 2000 { return String(cleaned.prefix(2000)) }
        return cleaned
    }

    private static func metadataPrompt(_ ocr: String) -> String {
        """
        Extract the product metadata fields from this NJ-CRC cannabis label OCR \
        text. Apply the rules in your instructions strictly.

        OCR text:
        \(ocr)
        """
    }

    private static func chemistryPrompt(_ ocr: String) -> String {
        """
        Extract the cannabinoid and terpene percentages from this NJ-CRC cannabis \
        label OCR text. Apply the rules in your instructions strictly.

        OCR text:
        \(ocr)
        """
    }

    // MARK: - Instructions (split per pass; each kept short to save tokens)

    static let metadataInstructions: String = """
    Extract NJ-CRC cannabis label metadata from OCR text. Rules:
    1. Dates → ISO YYYY-MM-DD format.
    2. Strain: the full cultivar name only — strip the brand prefix and the weight. The name may wrap across two lines (e.g. "Blue Candy" then "Rain" → "Blue Candy Rain"); reassemble it into the complete name. NEVER a terpene or cannabinoid name, and never a lot/batch-code line.
    3. productType: use the dosage form printed on the label. "Inhalable Product", or a net weight in grams (e.g. 28g, 3.5g), means an inhalable type — flower unless it explicitly says pre-roll or vape — and is NEVER an edible. Milligram dosing or words like gummies/chocolate/lozenge mean edible.
    4. Net weight includes the unit, e.g. "28g".
    5. qrCodes: include only opaque barcode payloads such as Metrc seed-to-sale tags. Do not include phone numbers, addresses, license numbers, or other readable text. Do not invent or echo example values.
    6. Null when not printed. Copy values verbatim.
    """

    static let chemistryInstructions: String = """
    Extract cannabinoid and terpene percentages from NJ-CRC cannabis label OCR text. Rules:
    1. Cannabinoid mapping: THCA→thca, Δ9-THC or Delta-9-THC→delta9thc, CBG→cbg, CBD→cbd. A bare "THC:" in the totals area is Total THC→totalThc, not delta9thc.
    2. Δ9-THC is always small (under ~5% on flower); a large value near "THC" is Total THC.
    3. Terpenes go in their named slots: myrcene, limonene, linalool, betaCaryophyllene, pinene, humulene. AlphaPinene and BetaPinene both contribute to pinene.
    4. Null when not printed. Copy values verbatim — never compute or estimate.
    """

#if DEBUG
    /// Default text the Prompt Lab seeds its editable instructions with — the
    /// two per-pass instruction sets combined, since the lab applies one prompt
    /// to both passes.
    static var promptLabDefaultInstructions: String {
        """
        \(metadataInstructions)

        \(chemistryInstructions)
        """
    }

    /// Debug-only: run BOTH passes with a one-shot custom system-instructions
    /// override applied to each. Throwaway sessions so the override doesn't
    /// pollute the actor's reusable sessions. Used by the in-app Prompt Lab.
    struct CustomRunResult: Sendable {
        let label: CannabisLabel
        let rawOcr: String
        let cleanedOcr: String
        let promptSent: String

        var preprocessorChangedInput: Bool { rawOcr != cleanedOcr }
    }

    func extractWithCustomInstructions(
        rawOcrText: String,
        instructions: String,
        applyPreprocessor: Bool = true
    ) async throws -> CustomRunResult {
        let cleaned = applyPreprocessor ? OCRPreprocessor.clean(rawOcrText) : rawOcrText
        let safeOcr: String = cleaned.count > 2000 ? String(cleaned.prefix(2000)) : cleaned

        // The custom instructions govern both passes — the Prompt Lab edits a
        // single prompt that we apply to metadata and chemistry alike.
        let metaSession = LanguageModelSession(instructions: instructions)
        let metadata = try await metaSession.respond(
            to: Prompt(Self.metadataPrompt(safeOcr)),
            generating: LabelMetadata.self
        ).content

        let chemSession = LanguageModelSession(instructions: instructions)
        let chemistry = try await chemSession.respond(
            to: Prompt(Self.chemistryPrompt(safeOcr)),
            generating: LabelChemistry.self
        ).content

        let label = CannabisLabel(metadata: metadata, chemistry: chemistry)
        return CustomRunResult(
            label: label,
            rawOcr: rawOcrText,
            cleanedOcr: cleaned,
            promptSent: "METADATA:\n\(Self.metadataPrompt(safeOcr))\n\nCHEMISTRY:\n\(Self.chemistryPrompt(safeOcr))"
        )
    }
#endif
}
