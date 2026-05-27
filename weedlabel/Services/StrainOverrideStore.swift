import Foundation

// StrainOverrideStore — local, user-editable corrections to strain
// classification. When the app can't determine a strain's lean (no printed
// marker, no known lineage), the user can tag it once; the correction persists
// and applies to every future scan of that strain. User corrections also win
// over the built-in inference, so a wrong guess can be fixed.
//
// This is the seed of the "living DB" idea: a local store the user grows over
// time. Currently scoped to strain lean; the same pattern extends to per-Metrc
// product corrections later. Persisted as JSON in the app's Documents
// directory — migratable to SwiftData when the app adopts it.

struct StrainOverride: Codable, Equatable, Sendable {
    /// Normalized strain name (lowercased, trimmed) — the lookup key.
    var key: String
    /// Original strain name as scanned, for display.
    var displayName: String
    var lean: StrainLean
    var dateUpdated: Date
}

@MainActor
protocol StrainOverrideStoring: AnyObject {
    func lean(forStrainName name: String) -> StrainLean?
    func setLean(_ lean: StrainLean, forStrainName name: String)
    func removeOverride(forStrainName name: String)
    func allOverrides() -> [StrainOverride]
}

@MainActor
final class FileStrainOverrideStore: StrainOverrideStoring {
    private var overrides: [String: StrainOverride] = [:]
    private let fileURL: URL

    /// Defaults to `Documents/strain-overrides.json`. A custom URL can be
    /// injected for tests.
    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.fileURL = docs.appendingPathComponent("strain-overrides.json")
        }
        load()
    }

    func lean(forStrainName name: String) -> StrainLean? {
        overrides[StrainKnowledgeBase.normalizedKey(name)]?.lean
    }

    func setLean(_ lean: StrainLean, forStrainName name: String) {
        let key = StrainKnowledgeBase.normalizedKey(name)
        guard !key.isEmpty else { return }
        overrides[key] = StrainOverride(
            key: key,
            displayName: name.trimmingCharacters(in: .whitespacesAndNewlines),
            lean: lean,
            dateUpdated: Date()
        )
        save()
    }

    func removeOverride(forStrainName name: String) {
        overrides[StrainKnowledgeBase.normalizedKey(name)] = nil
        save()
    }

    func allOverrides() -> [StrainOverride] {
        overrides.values.sorted { $0.dateUpdated > $1.dateUpdated }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? JSONDecoder().decode([StrainOverride].self, from: data) else { return }
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
final class InMemoryStrainOverrideStore: StrainOverrideStoring {
    private var overrides: [String: StrainOverride] = [:]

    init() {}

    func lean(forStrainName name: String) -> StrainLean? {
        overrides[StrainKnowledgeBase.normalizedKey(name)]?.lean
    }

    func setLean(_ lean: StrainLean, forStrainName name: String) {
        let key = StrainKnowledgeBase.normalizedKey(name)
        guard !key.isEmpty else { return }
        overrides[key] = StrainOverride(key: key, displayName: name, lean: lean, dateUpdated: Date())
    }

    func removeOverride(forStrainName name: String) {
        overrides[StrainKnowledgeBase.normalizedKey(name)] = nil
    }

    func allOverrides() -> [StrainOverride] {
        overrides.values.sorted { $0.dateUpdated > $1.dateUpdated }
    }
}
