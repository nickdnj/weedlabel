import Foundation
import FoundationModels

// CannabisLabel — the structured shape Foundation Models extracts from raw OCR text.
// Field set is grounded in NJAC §17:30-16.3 (NJ-CRC label requirements).
// Spike scope: cover what the Zips Blue Candy Rain canary contains plus a few
// commonly-required NJ fields. v1 will expand to all 16 NJAC §17:30-16.3(b) items.

@Generable
struct CannabisLabel: Sendable {
    @Guide(description: "Strain or cultivar name as printed on the label (e.g. 'Blue Candy Rain', 'Northern Lights'). Use the exact name printed.")
    var strainName: String

    @Guide(description: "Cultivator or manufacturer business name as printed on the label (e.g. 'Fresh Grow LLC').")
    var cultivator: String

    @Guide(description: "NJ-CRC license number, typically of the form 'C000###' or similar. Null if not visible.")
    var licenseNumber: String?

    @Guide(description: "Metrc seed-to-sale tracking tag, typically 24 characters starting with '1A4'. Null if not visible.")
    var metrcTag: String?

    @Guide(description: "Batch or lot number as printed. Null if not visible.")
    var batchOrLot: String?

    @Guide(description: "Net weight as printed including unit, e.g. '28.35g' or '1oz'. Null if not visible.")
    var netWeight: String?

    @Guide(description: "Production or harvest date in ISO format YYYY-MM-DD if discernible. Null if not visible.")
    var harvestDate: String?

    @Guide(description: "Expiration date in ISO format YYYY-MM-DD if discernible. Null if not visible.")
    var expirationDate: String?

    @Guide(description: "Product type: one of flower, vape, edible, concentrate, preRoll, tincture, topical, other.")
    var productType: ProductType

    @Guide(description: "Cannabinoid percentages as printed on the label.")
    var cannabinoids: Cannabinoids

    @Guide(description: "Terpene percentages as printed on the label.")
    var terpenes: Terpenes

    @Guide(description: "Growth method if specified on label (Indoor, Outdoor, SoilGrown, Hydroponic, Aquaponic). Null if not specified.")
    var growthMethod: GrowthMethod?

    @Guide(description: "QR code or barcode payloads detected on the label, raw strings. Empty array if none.")
    var qrCodes: [String]
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

@Generable
enum GrowthMethod: Sendable {
    case indoor
    case outdoor
    case soilGrown
    case hydroponic
    case aquaponic
}

@Generable
struct Cannabinoids: Sendable {
    @Guide(description: "THCA percentage by weight, number only (no '%' sign). Null if not printed.")
    var thca: Double?
    @Guide(description: "Δ9-THC (delta-9 THC) percentage by weight. Null if not printed.")
    var delta9thc: Double?
    @Guide(description: "CBD percentage by weight. Null if not printed.")
    var cbd: Double?
    @Guide(description: "CBDA percentage by weight. Null if not printed.")
    var cbda: Double?
    @Guide(description: "CBG percentage by weight. Null if not printed.")
    var cbg: Double?
    @Guide(description: "CBGA percentage by weight. Null if not printed.")
    var cbga: Double?
    @Guide(description: "Total cannabinoids percentage as printed on the label (do not compute).")
    var totalCannabinoids: Double?
    @Guide(description: "Total THC as printed on the label (do not compute). Null if not printed.")
    var totalThc: Double?
    @Guide(description: "Total CBD as printed on the label (do not compute). Null if not printed.")
    var totalCbd: Double?
}

@Generable
struct Terpenes: Sendable {
    @Guide(description: "Myrcene percentage by weight, number only. Null if not printed.")
    var myrcene: Double?
    @Guide(description: "Limonene percentage by weight. Null if not printed.")
    var limonene: Double?
    @Guide(description: "Linalool percentage by weight. Null if not printed.")
    var linalool: Double?
    @Guide(description: "Beta-caryophyllene percentage by weight. Null if not printed.")
    var betaCaryophyllene: Double?
    @Guide(description: "Pinene (alpha or beta) percentage by weight. Null if not printed.")
    var pinene: Double?
    @Guide(description: "Humulene percentage by weight. Null if not printed.")
    var humulene: Double?
    @Guide(description: "Other terpenes detected with their percentages. Empty array if none beyond the named six.")
    var other: [TerpeneEntry]
    @Guide(description: "Total terpenes percentage as printed on the label.")
    var total: Double?
}

@Generable
struct TerpeneEntry: Sendable {
    @Guide(description: "Terpene name as printed (e.g. 'farnesene', 'ocimene')")
    var name: String
    @Guide(description: "Percentage by weight, number only")
    var percent: Double
}

// MARK: - Regulatory derivations (NJAC §17:30-16.3)

extension CannabisLabel {
    /// Total THC per NJAC §17:30-16.3(b)(9)(ii)(1):
    ///   Total THC = (THCA × 0.877) + Δ9-THC
    var computedTotalThc: Double? {
        let thca = cannabinoids.thca ?? 0
        let d9 = cannabinoids.delta9thc ?? 0
        if cannabinoids.thca == nil && cannabinoids.delta9thc == nil { return nil }
        return (thca * 0.877) + d9
    }

    /// Total CBD per NJAC §17:30-16.3(b)(9)(ii)(2):
    ///   Total CBD = (CBDA × 0.877) + CBD
    var computedTotalCbd: Double? {
        let cbda = cannabinoids.cbda ?? 0
        let cbd = cannabinoids.cbd ?? 0
        if cannabinoids.cbda == nil && cannabinoids.cbd == nil { return nil }
        return (cbda * 0.877) + cbd
    }

    /// Chemotype classification per NJAC §17:30-16.3(b)(11).
    enum Chemotype {
        case highThcLowCbd        // ratio > 5:1 AND total THC ≥ 15%
        case moderateThcModerateCbd // ratio 5:1–1:5 AND total THC 5–15%
        case lowThcHighCbd        // ratio < 1:5 AND total THC ≤ 5%
    }

    var chemotype: Chemotype? {
        let thc = computedTotalThc ?? cannabinoids.totalThc
        let cbd = computedTotalCbd ?? cannabinoids.totalCbd ?? 0
        guard let thc else { return nil }
        let ratio: Double = cbd > 0 ? thc / cbd : Double.greatestFiniteMagnitude
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
        guard let thc = computedTotalThc ?? cannabinoids.totalThc else { return false }
        return thc > 40
    }
}
