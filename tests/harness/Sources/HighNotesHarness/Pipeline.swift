import Foundation

// Pipeline — the deterministic, on-device post-processing the app applies AFTER
// Foundation Models extraction and BEFORE the summary. This is the HighNotes
// analogue of VinoLabel's `WineReference.applyStructuralCleanup` + `enrich`.
//
// It mirrors ScanModel.runPipeline step-for-step (see weedlabel/Views/
// ScanModel.swift) so the harness compares END-OF-PIPELINE output, not raw
// model output — and it's applied IDENTICALLY to both the Apple and Claude
// labels so the comparison is fair.
//
// Order (matches the app exactly):
//   1. merge VisionKit QR payloads into the label
//   2. fixSwappedThcFields()                       — Total-THC/Δ9 + THCA swaps
//   3. StrainNameFixer.fix(strain:ocrText:)        — recover chemical-name misreads
//   4. (name-override resolve — N/A in a batch eval, see note)
//   5. ProductTypeInference.infer(ocrText:)        — printed dosage form wins
//   6. (product-type override — N/A in a batch eval, see note)
//
// OVERRIDE STORES: the app also consults three user-correction stores (strain
// name, product type, strain lean). A batch eval starts from a clean install
// with zero saved corrections, so every override lookup is a guaranteed no-op
// and is omitted here — running with empty in-memory stores would produce
// byte-identical output. This is documented in the harness README.
//
// The strain insight (sativa/indica/hybrid + character) is computed exactly as
// the app does and fed into BOTH summary passes, so Apple and Claude get the
// same Classification/character lines in their user prompt.

enum Pipeline {

    /// Apply the app's deterministic post-extraction cleanup. `ocrText` is the
    /// RAW Vision OCR (not the preprocessed/clamped text) — ScanModel passes the
    /// raw capture text to these helpers. `qrCodes` are the VisionKit/MacImageOCR
    /// barcode payloads, merged in just like the app merges them.
    static func postProcess(_ label: CannabisLabel, ocrText: String, qrCodes: [String]) -> CannabisLabel {
        var l = label

        // 1. Merge in QR codes the OCR/barcode pass found (FM doesn't see them).
        l.qrCodes = dedupe(label.qrCodes + qrCodes)

        // 2. Total-THC/Δ9 and THCA/Total-THC swap correction, then null out
        //    impossible magnitudes (lot codes mis-parsed as cannabinoids).
        l.fixSwappedThcFields()
        l.clampImplausibleValues()
        // 2b. Re-read terpenes from the OCR (model mis-slots them; pinene is
        //     split across Alpha-/Beta-Pinene lines).
        l.reconcileTerpenes(ocrText: ocrText)

        // 3. Recover a real strain name when the model latched onto a chemical
        //    compound name (e.g. "Limonene"), a warning line, the cultivator, or
        //    an OCR fragment of one.
        let fixed = StrainNameFixer.fix(strain: l.strainName, cultivator: l.cultivator, ocrText: ocrText)
        if fixed.didFix { l.strainName = fixed.strain }

        // 4. (name-override resolve — no saved corrections in a batch eval)

        // 5. Deterministic product-type from explicit printed wording
        //    ("Inhalable Product" → flower), overriding a name-biased FM guess.
        if let inferred = ProductTypeInference.infer(ocrText: ocrText), inferred != l.productType {
            l.productType = inferred
        }

        // 6. (product-type override — no saved corrections in a batch eval)

        return l
    }

    /// Deterministic sativa/indica/hybrid insight, computed exactly as the app
    /// does (no saved override in a batch eval). Fed into both summary passes.
    static func strainInsight(for label: CannabisLabel, ocrText: String) -> StrainInsight? {
        StrainKnowledgeBase.insight(strainName: label.strainName, ocrText: ocrText, override: nil)
    }

    /// Product-type-aware sanity verdict → optional warning string, exactly as
    /// the app surfaces it. Does NOT block the summary (the %-hallucination guard
    /// in SummaryService is the real safety net), but is recorded in the report.
    static func sanityWarning(for label: CannabisLabel) -> String? {
        if case .verifyHint(let reason) = LabelSanityChecker.check(label) { return reason }
        return nil
    }

    /// Order-preserving de-dup of trimmed, non-empty strings (matches the app's
    /// private `Array.reduced` helper in ScanModel).
    private static func dedupe(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for s in items {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty && seen.insert(t).inserted { out.append(t) }
        }
        return out
    }
}
