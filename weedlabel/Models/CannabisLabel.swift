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
    @Guide(description: "Pinene percent")
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
        // Swap #1: delta9thc populated with what should be Total THC.
        if let d9 = delta9thc, d9 > 10 {
            // Only swap if totalThc isn't already set higher than delta9thc.
            if totalThc == nil || (totalThc ?? 0) < d9 {
                totalThc = d9
                delta9thc = nil
            }
        }

        // Swap #2: THCA and Total THC reversed. Apply only on flower-like
        // products where THCA being smaller than Total THC is implausible.
        if [.flower, .preRoll, .vape].contains(productType),
           let thcaVal = thca, let totalThcVal = totalThc,
           totalThcVal > thcaVal * 1.1 {
            self.thca = totalThcVal
            self.totalThc = thcaVal
        }
    }
}
