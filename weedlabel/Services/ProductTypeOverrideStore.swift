import Foundation

// ProductTypeOverrideStore — local, user-editable corrections to the inferred
// product type. The FM occasionally mis-reads it (e.g. a flower package as an
// edible); the user fixes it once and the correction persists to every future
// scan of that strain. Mirrors StrainOverrideStore exactly — same normalized
// strain-name key, same JSON-in-Documents persistence (migratable to SwiftData
// later). Keyed by strain name, so the rare same-strain/different-form case
// (flower vs pre-roll) takes the most recent correction.

struct ProductTypeOverride: Codable, Equatable, Sendable {
    /// Normalized strain name (lowercased, trimmed) — the lookup key.
    var key: String
    /// Original strain name as scanned, for display.
    var displayName: String
    var productType: ProductType
    var dateUpdated: Date
}

@MainActor
protocol ProductTypeOverrideStoring: AnyObject {
    func productType(forStrainName name: String) -> ProductType?
    func setProductType(_ type: ProductType, forStrainName name: String)
    func removeOverride(forStrainName name: String)
    func removeAll()
    func allOverrides() -> [ProductTypeOverride]
}

@MainActor
final class FileProductTypeOverrideStore: ProductTypeOverrideStoring {
    private var overrides: [String: ProductTypeOverride] = [:]
    private let fileURL: URL

    /// Defaults to `Documents/product-type-overrides.json`. A custom URL can be
    /// injected for tests.
    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.fileURL = docs.appendingPathComponent("product-type-overrides.json")
        }
        load()
    }

    func productType(forStrainName name: String) -> ProductType? {
        overrides[StrainKnowledgeBase.normalizedKey(name)]?.productType
    }

    func setProductType(_ type: ProductType, forStrainName name: String) {
        let key = StrainKnowledgeBase.normalizedKey(name)
        guard !key.isEmpty else { return }
        overrides[key] = ProductTypeOverride(
            key: key,
            displayName: name.trimmingCharacters(in: .whitespacesAndNewlines),
            productType: type,
            dateUpdated: Date()
        )
        save()
    }

    func removeOverride(forStrainName name: String) {
        overrides[StrainKnowledgeBase.normalizedKey(name)] = nil
        save()
    }

    func removeAll() {
        overrides.removeAll()
        save()
    }

    func allOverrides() -> [ProductTypeOverride] {
        overrides.values.sorted { $0.dateUpdated > $1.dateUpdated }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? JSONDecoder().decode([ProductTypeOverride].self, from: data) else { return }
        overrides = Dictionary(uniqueKeysWithValues: decoded.map { ($0.key, $0) })
    }

    private func save() {
        let list = Array(overrides.values)
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}

/// In-memory store for tests and SwiftUI previews — no disk I/O.
@MainActor
final class InMemoryProductTypeOverrideStore: ProductTypeOverrideStoring {
    private var overrides: [String: ProductTypeOverride] = [:]

    init() {}

    func productType(forStrainName name: String) -> ProductType? {
        overrides[StrainKnowledgeBase.normalizedKey(name)]?.productType
    }

    func setProductType(_ type: ProductType, forStrainName name: String) {
        let key = StrainKnowledgeBase.normalizedKey(name)
        guard !key.isEmpty else { return }
        overrides[key] = ProductTypeOverride(key: key, displayName: name, productType: type, dateUpdated: Date())
    }

    func removeOverride(forStrainName name: String) {
        overrides[StrainKnowledgeBase.normalizedKey(name)] = nil
    }

    func removeAll() {
        overrides.removeAll()
    }

    func allOverrides() -> [ProductTypeOverride] {
        overrides.values.sorted { $0.dateUpdated > $1.dateUpdated }
    }
}
