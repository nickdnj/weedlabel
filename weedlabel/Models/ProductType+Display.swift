import Foundation

// Display + iteration helpers for ProductType. Kept out of CannabisLabel.swift
// so the model file stays focused on the @Generable schema. `allCases` is
// provided manually because CaseIterable synthesis only happens in the type's
// own source file, not in an extension elsewhere.

extension ProductType: CaseIterable {
    /// Ordered most-common first, so the correction picker reads naturally.
    static var allCases: [ProductType] {
        [.flower, .preRoll, .vape, .concentrate, .edible, .tincture, .topical, .other]
    }

    var displayName: String {
        switch self {
        case .flower: "Flower"
        case .vape: "Vape"
        case .edible: "Edible"
        case .concentrate: "Concentrate"
        case .preRoll: "Pre-roll"
        case .tincture: "Tincture"
        case .topical: "Topical"
        case .other: "Other"
        }
    }

    var iconName: String {
        switch self {
        case .flower: "leaf.fill"
        case .vape: "wind"
        case .edible: "fork.knife"
        case .concentrate: "drop.fill"
        case .preRoll: "flame.fill"
        case .tincture: "eyedropper.halffull"
        case .topical: "hand.raised.fill"
        case .other: "tag.fill"
        }
    }

    /// Stable string identifier for on-disk persistence — independent of
    /// `displayName` (which is UI copy and may change).
    var storageKey: String {
        switch self {
        case .flower: "flower"
        case .vape: "vape"
        case .edible: "edible"
        case .concentrate: "concentrate"
        case .preRoll: "preRoll"
        case .tincture: "tincture"
        case .topical: "topical"
        case .other: "other"
        }
    }

    init?(storageKey: String) {
        switch storageKey {
        case "flower": self = .flower
        case "vape": self = .vape
        case "edible": self = .edible
        case "concentrate": self = .concentrate
        case "preRoll": self = .preRoll
        case "tincture": self = .tincture
        case "topical": self = .topical
        case "other": self = .other
        default: return nil
        }
    }
}

// Codable via the stable storageKey, so ProductType can ride inside persisted
// override records. Implemented manually (no raw type on a @Generable enum).
extension ProductType: Codable {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ProductType(storageKey: raw) ?? .other
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storageKey)
    }
}
