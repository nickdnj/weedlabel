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
}
