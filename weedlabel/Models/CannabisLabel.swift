import Foundation
import FoundationModels

// CannabisLabel — the composed, consumer-facing label model. It is NOT itself
// @Generable: extraction happens in TWO smaller Foundation Models passes
// (LabelMetadata + LabelChemistry), each of which fits the 4096-token context
// comfortably where a single combined schema kept blowing past it. The two
// results compose into this flat struct, so every downstream consumer
// (SummaryService, LabelSanityChecker, UI) is unchanged.
//
// Dropped from the spike v0: terpenesOther (dynamic array, very expensive),
// growthMethod, batchOrLot, cbga, cbda. Add back when an edible canary needs them.

struct CannabisLabel: Sendable {
    // MARK: - Metadata
    var strainName: String
    var cultivator: String
    var licenseNumber: String?
    var metrcTag: String?
    var netWeight: String?
    var harvestDate: String?
    var expirationDate: String?
    var productType: ProductType

    // MARK: - Cannabinoids
    var thca: Double?
    var delta9thc: Double?
    var cbd: Double?
    var cbg: Double?
    var totalCannabinoids: Double?
    var totalThc: Double?
    var totalCbd: Double?

    // MARK: - Terpenes
    var myrcene: Double?
    var limonene: Double?
    var linalool: Double?
    var betaCaryophyllene: Double?
    var pinene: Double?
    var humulene: Double?
    var totalTerpenes: Double?

    // MARK: - Barcodes
    var qrCodes: [String]
}

// Codable + Equatable for Log Book persistence. Synthesis works because every
// stored property already conforms (ProductType is Codable; the composing
// `init(metadata:chemistry:)` lives in an extension, so the memberwise and
// Codable inits still synthesize). Computed properties aren't encoded.
extension CannabisLabel: Codable, Equatable {}

// MARK: - FM extraction passes
//
// Each is a focused @Generable schema. Keeping them separate halves the
// per-call schema reflection + output reservation, which is what keeps us
// under the on-device context window.

@Generable
struct LabelMetadata: Sendable {
    @Guide(description: "Full strain/product name. May wrap across two lines or sit between the brand and the weight — reassemble it (e.g. \"Blue Candy\" + \"Rain\" → \"Blue Candy Rain\"). NEVER a terpene, cannabinoid, or lot-code line.")
    var strainName: String
    @Guide(description: "Cultivator business name")
    var cultivator: String
    @Guide(description: "License number (e.g. C000186)")
    var licenseNumber: String?
    @Guide(description: "Metrc tag, ~24 chars starting 1A4")
    var metrcTag: String?
    @Guide(description: "Net weight with unit, e.g. 28g")
    var netWeight: String?
    @Guide(description: "Harvest date, ISO YYYY-MM-DD")
    var harvestDate: String?
    @Guide(description: "Expiration date, ISO YYYY-MM-DD")
    var expirationDate: String?
    @Guide(description: "Product type from the printed dosage form. \"Inhalable Product\" or a gram weight (e.g. 28g) = flower/vape/pre-roll, never edible; milligram dosing or gummies/chocolate = edible.")
    var productType: ProductType
    @Guide(description: "Barcode payloads (e.g. Metrc tag). Never readable text.")
    var qrCodes: [String]
}

@Generable
struct LabelChemistry: Sendable {
    @Guide(description: "THCA percent")
    var thca: Double?
    @Guide(description: "Δ9-THC percent. Always small (<5% on flower). NOT a bare 'THC:' label.")
    var delta9thc: Double?
    @Guide(description: "CBD percent")
    var cbd: Double?
    @Guide(description: "CBG percent")
    var cbg: Double?
    @Guide(description: "Total cannabinoids as printed")
    var totalCannabinoids: Double?
    @Guide(description: "Total THC as printed. A bare 'THC:' line in the totals area goes here.")
    var totalThc: Double?
    @Guide(description: "Total CBD as printed")
    var totalCbd: Double?
    @Guide(description: "Myrcene percent")
    var myrcene: Double?
    @Guide(description: "Limonene percent")
    var limonene: Double?
    @Guide(description: "Linalool percent")
    var linalool: Double?
    @Guide(description: "Beta-caryophyllene percent")
    var betaCaryophyllene: Double?
    @Guide(description: "Total pinene percent. Labels print Alpha-Pinene and Beta-Pinene as two separate lines — pinene is their SUM. If only one is printed, use it.")
    var pinene: Double?
    @Guide(description: "Humulene percent")
    var humulene: Double?
    @Guide(description: "Total terpenes as printed")
    var totalTerpenes: Double?
}

@Generable
enum ProductType: Sendable {
    case flower
    case vape
    case edible
    case concentrate
    case preRoll
    case tincture
    case topical
    case other
}

// MARK: - Composition

extension CannabisLabel {
    /// Compose the consumer-facing label from the two extraction passes.
    init(metadata m: LabelMetadata, chemistry c: LabelChemistry) {
        strainName = m.strainName
        cultivator = m.cultivator
        licenseNumber = m.licenseNumber
        metrcTag = m.metrcTag
        netWeight = m.netWeight
        harvestDate = m.harvestDate
        expirationDate = m.expirationDate
        productType = m.productType
        qrCodes = m.qrCodes

        thca = c.thca
        delta9thc = c.delta9thc
        cbd = c.cbd
        cbg = c.cbg
        totalCannabinoids = c.totalCannabinoids
        totalThc = c.totalThc
        totalCbd = c.totalCbd
        myrcene = c.myrcene
        limonene = c.limonene
        linalool = c.linalool
        betaCaryophyllene = c.betaCaryophyllene
        pinene = c.pinene
        humulene = c.humulene
        totalTerpenes = c.totalTerpenes
    }
}

// MARK: - Regulatory derivations (NJAC §17:30-16.3)

extension CannabisLabel {
    /// Total THC per NJAC §17:30-16.3(b)(9)(ii)(1):
    ///   Total THC = (THCA × 0.877) + Δ9-THC
    var computedTotalThc: Double? {
        let thca = self.thca ?? 0
        let d9 = self.delta9thc ?? 0
        if self.thca == nil && self.delta9thc == nil { return nil }
        return (thca * 0.877) + d9
    }

    /// Total CBD per NJAC §17:30-16.3(b)(9)(ii)(2):
    ///   Total CBD = (CBDA × 0.877) + CBD
    /// CBDA is no longer in the trimmed schema, so this just falls back to CBD.
    var computedTotalCbd: Double? {
        cbd
    }

    /// Chemotype classification per NJAC §17:30-16.3(b)(11).
    enum Chemotype {
        case highThcLowCbd        // ratio > 5:1 AND total THC ≥ 15%
        case moderateThcModerateCbd // ratio 5:1–1:5 AND total THC 5–15%
        case lowThcHighCbd        // ratio < 1:5 AND total THC ≤ 5%
    }

    var chemotype: Chemotype? {
        let thc = computedTotalThc ?? totalThc
        let cbdVal = computedTotalCbd ?? totalCbd ?? 0
        guard let thc else { return nil }
        let ratio: Double = cbdVal > 0 ? thc / cbdVal : Double.greatestFiniteMagnitude
        if ratio > 5 && thc >= 15 { return .highThcLowCbd }
        if ratio < (1.0/5.0) && thc <= 5 { return .lowThcHighCbd }
        if ratio >= (1.0/5.0) && ratio <= 5 && thc >= 5 && thc <= 15 { return .moderateThcModerateCbd }
        // Closest of the three by mathematical analysis (rule fallback)
        if thc >= 12 || ratio > 3 { return .highThcLowCbd }
        if thc <= 8 || ratio < 0.33 { return .lowThcHighCbd }
        return .moderateThcModerateCbd
    }

    /// Whether NJAC §17:30-16.3(c)(2) high-potency warning applies.
    /// "This is a high potency product and may increase your risk for psychosis"
    var isHighPotency: Bool {
        guard let thc = computedTotalThc ?? totalThc else { return false }
        return thc > 40
    }

    // MARK: - Post-extraction normalization

    /// Deterministic post-fix for common FM mis-assignments on labels where
    /// the Potency Analysis section has THCA, Δ9-THC, and Total THC sitting
    /// adjacent in OCR. Two swap patterns observed:
    ///
    /// 1. Total THC value (typically 15-35%) put into `delta9thc` (which is
    ///    almost always < 5%).
    /// 2. THCA value and Total THC value swapped — but Total THC = 0.877×THCA
    ///    + Δ9-THC, so THCA is almost always ≥ Total THC. When totalThc > thca
    ///    by more than 10%, they're likely swapped.
    ///
    /// Both swaps only run on flower/preRoll/vape product types — concentrates
    /// can have decarboxylated profiles where Total THC genuinely exceeds THCA.
    mutating func fixSwappedThcFields() {
        // These corrections encode FLOWER assumptions — Δ9-THC < ~5% and
        // THCA ≥ Total THC. They are FALSE for vapes and concentrates:
        // distillate carts have Δ9-THC and Total THC of 60-90% with near-zero
        // THCA, so applying either swap there would corrupt a correctly-read
        // label (observed: distillate vapes scoring 0% on totalThc/thca).
        // Restrict to flower/pre-roll; trust the model + instructions elsewhere.
        guard [.flower, .preRoll].contains(productType) else { return }

        // Swap #1: delta9thc populated with what should be Total THC.
        if let d9 = delta9thc, d9 > 10 {
            // Only swap if totalThc isn't already set higher than delta9thc.
            if totalThc == nil || (totalThc ?? 0) < d9 {
                totalThc = d9
                delta9thc = nil
            }
        }

        // Swap #2: THCA and Total THC reversed — on flower THCA is ≥ Total THC,
        // so totalThc materially exceeding thca means they're flipped.
        if let thcaVal = thca, let totalThcVal = totalThc,
           totalThcVal > thcaVal * 1.1 {
            self.thca = totalThcVal
            self.totalThc = thcaVal
        }
    }

    /// Terpene reconciliation. NJ-CRC labels print each terpene on its own
    /// "Name: value%" line, but the model mis-assigns values to the wrong slot
    /// under dense or scrambled panels (observed: myrcene's value landing in the
    /// caryophyllene slot, and pinene — split across Alpha-/Beta-Pinene lines —
    /// at ~50%). The values are unambiguous in the OCR, so we re-read each named
    /// terpene straight from the text and trust that over the model's slotting.
    ///
    /// Conservative by construction: a slot is overwritten ONLY when a line that
    /// names that terpene AND carries a plausible percent on the SAME line is
    /// found. Heavily scrambled OCR (name and value on different lines) yields no
    /// match, so the model's value is left untouched. Run AFTER
    /// clampImplausibleValues so it has the last word.
    mutating func reconcileTerpenes(ocrText: String) {
        let lines = ocrText.components(separatedBy: .newlines).map(Self.normalizeOCRLine)
        func read(_ tokens: [String], exclude: [String] = []) -> Double? {
            for line in lines {
                if exclude.contains(where: { line.contains($0) }) { continue }
                for t in tokens {
                    if let v = Self.valueAfter(token: t, in: line, minV: 0.01, maxV: 30) { return v }
                }
            }
            return nil
        }
        // Pinene = Alpha-Pinene + Beta-Pinene (printed as two lines, summed).
        let alpha = read(["alphapinene", "alphapin"])
        let beta = read(["betapinene", "betapin"])
        if alpha != nil || beta != nil {
            pinene = (((alpha ?? 0) + (beta ?? 0)) * 100).rounded() / 100
        }
        if let v = read(["myrcene", "myrcen"]) { myrcene = v }
        if let v = read(["limonene", "limonen"]) { limonene = v }
        if let v = read(["linalool", "linaool", "linalol"]) { linalool = v }
        if let v = read(["caryophyllene", "caryophylene", "caryophyllen"], exclude: ["oxide"]) { betaCaryophyllene = v }
        if let v = read(["humulene", "humulen", "humuiene"]) { humulene = v }
    }

    /// Cannabinoid reconciliation. The model mis-maps the cannabinoid column on
    /// dense labels even when OCR reads it perfectly (observed: it put CBG's 0.36
    /// into `thca` and missed Total THC 25.90 on a crisp crop). Each value is
    /// printed next to an unambiguous label, so we re-read them by name — the
    /// authoritative source — overriding the model. Run AFTER
    /// fixSwappedThcFields/clamp so it has the last word. `0.00` is a legit value.
    mutating func reconcileCannabinoids(ocrText: String) {
        let lines = ocrText.components(separatedBy: .newlines).map(Self.normalizeOCRLine)
        func read(_ tokens: [String], exclude: [String] = []) -> Double? {
            for line in lines {
                if exclude.contains(where: { line.contains($0) }) { continue }
                for t in tokens {
                    if let v = Self.valueAfter(token: t, in: line, minV: 0, maxV: 100) { return v }
                }
            }
            return nil
        }
        // Distinct substrings: "totalthc"/"thca"/"d9thc" don't collide. CBD/CBG
        // exclude their acids; the chemotype line ("…low cbd", no number) is
        // skipped because no value follows the token.
        if let v = read(["totalcannabinoid", "totalcannab"]) { totalCannabinoids = v }
        if let v = read(["totalthc"]) { totalThc = v }
        if let v = read(["thca"]) { thca = v }
        if let v = read(["d9thc", "delta9thc", "delta9", "δ9thc", "δ9"]) { delta9thc = v }
        // Exclude the chemotype line ("High THC, Low CBD") — when row-grouping
        // merges it with an adjacent value column, a bare "cbd" would otherwise
        // capture the wrong number.
        if let v = read(["cbd"], exclude: ["cbda", "lowcbd", "highcbd", "moderatecbd"]) { cbd = v }
        if let v = read(["cbg"], exclude: ["cbga", "lowcbg", "highcbg", "moderatecbg"]) { cbg = v }
    }

    /// Lowercase + strip spaces and hyphens, so a label split across columns by
    /// OCR ("Total THC" / "D9-THC") matches a single token and the value parses
    /// cleanly regardless of spacing.
    private static func normalizeOCRLine(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    /// First number appearing AFTER `token` in the normalized `line`, within
    /// [minV, maxV] — but only within a short WINDOW right after the label. A
    /// real value sits immediately after the colon ("d9thc:1.13"); capping the
    /// window stops the parser from walking down a row-grouped line into an
    /// unrelated number (observed: "d9thc: … licnumber:c000067" → grabbing 67
    /// when OCR failed to read the value column). Handles labels with digits
    /// ("d9thc") and merged multi-column rows ("thca:28.73limonene:0.68").
    private static func valueAfter(token: String, in line: String, minV: Double, maxV: Double) -> Double? {
        guard let r = line.range(of: token) else { return nil }
        // Only the first ~10 chars after the token — enough for ":25.90%", not
        // enough to reach a license/Metrc number further down a merged row.
        let tail = line[r.upperBound...]
        let window = String(tail.prefix(10))
        guard let re = try? NSRegularExpression(pattern: #"\d+(?:\.\d+)?"#) else { return nil }
        let ns = window as NSString
        for m in re.matches(in: window, range: NSRange(location: 0, length: ns.length)) {
            if let v = Double(ns.substring(with: m.range)), v >= minV, v <= maxV { return v }
        }
        return nil
    }

    /// Null out physically-impossible magnitudes — almost always OCR/lot-code
    /// noise the model mis-parsed (observed: a batch line "9 - 120925- …" pulled
    /// into totalCannabinoids as 120925). A single cannabinoid percent cannot
    /// exceed 100; a single terpene percent realistically cannot exceed ~30.
    /// Defense-in-depth behind the OCRPreprocessor lot-line stripper — better to
    /// show "not legible" than "120925% THC". Run AFTER fixSwappedThcFields so a
    /// promoted-then-absurd value is also caught.
    mutating func clampImplausibleValues() {
        // Cannabinoids: only out-of-range values are noise. A printed 0.00% (e.g.
        // "CBD 0.00%") is legitimate and kept.
        func clampCannabinoid(_ v: inout Double?) {
            if let x = v, x > 100 || x < 0 { v = nil }
        }
        // Terpenes: out-of-range OR exactly 0. A terpene that isn't detected is
        // absent, not "0.00%" — guided generation defaults these Double fields to
        // 0, which otherwise litters the result screen with seven "0.00%" rows on
        // edibles and labels with no terpene panel. Ground truth never asserts a
        // 0.0 terpene, so dropping them is purely a cleanup.
        func clampTerpene(_ v: inout Double?) {
            if let x = v, x > 30 || x <= 0 { v = nil }
        }
        clampCannabinoid(&thca); clampCannabinoid(&delta9thc); clampCannabinoid(&cbd)
        clampCannabinoid(&cbg); clampCannabinoid(&totalCannabinoids)
        clampCannabinoid(&totalThc); clampCannabinoid(&totalCbd)
        clampTerpene(&myrcene); clampTerpene(&limonene); clampTerpene(&linalool)
        clampTerpene(&betaCaryophyllene); clampTerpene(&pinene)
        clampTerpene(&humulene); clampTerpene(&totalTerpenes)
    }
}
