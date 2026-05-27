import Foundation

// StrainNameOverrideStore — local, user-editable corrections to the extracted
// strain NAME. Worst-case OCR (a name split across non-adjacent lines, or a
// lot-code line mistaken for the name) can defeat the model entirely; the user
// fixes it once and the correction sticks for future scans of that product.
//
// Keyed by the normalized *extracted* (wrong) name → corrected name, so the
// fix applies the next time the model produces the same wrong name. Applied
// FIRST in the pipeline, so the corrected name then drives the product-type and
// strain-lean lookups (which are keyed by strain name). Mirrors
// StrainOverrideStore / ProductTypeOverrideStore: JSON in Documents.

struct StrainNameOverride: Codable, Equatable, Sendable {
    /// Normalized extracted (wrong) name — the lookup key.
    var key: String
    /// The extracted name as scanned, for display.
    var extractedName: String
    /// The user's corrected name.
    var correctedName: String
    var dateUpdated: Date
}

@MainActor
protocol StrainNameOverrideStoring: AnyObject {
    func correctedName(forExtractedName name: String) -> String?
    func setCorrectedName(_ corrected: String, forExtractedName name: String)
    func removeOverride(forExtractedName name: String)
    func removeAll()
    func allOverrides() -> [StrainNameOverride]
}

extension StrainNameOverrideStoring {
    /// Follow the correction chain (a → b → c) so successive re-edits compose,
    /// with a cycle guard. Returns the final corrected name, or the input when
    /// there's no override.
    func resolve(extractedName name: String) -> String {
        var current = name
        var seen = Set<String>()
        while true {
            let key = StrainKnowledgeBase.normalizedKey(current)
            if key.isEmpty || seen.contains(key) { break }
            seen.insert(key)
            guard let next = correctedName(forExtractedName: current),
                  StrainKnowledgeBase.normalizedKey(next) != key else { break }
            current = next
        }
        return current
    }
}

@MainActor
final class FileStrainNameOverrideStore: StrainNameOverrideStoring {
    private var overrides: [String: StrainNameOverride] = [:]
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.fileURL = docs.appendingPathComponent("strain-name-overrides.json")
        }
        load()
    }

    func correctedName(forExtractedName name: String) -> String? {
        overrides[StrainKnowledgeBase.normalizedKey(name)]?.correctedName
    }

    func setCorrectedName(_ corrected: String, forExtractedName name: String) {
        let key = StrainKnowledgeBase.normalizedKey(name)
        let trimmed = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !trimmed.isEmpty else { return }
        // A no-op correction (same as the extracted name) drops any mapping.
        if StrainKnowledgeBase.normalizedKey(trimmed) == key {
            overrides[key] = nil
            save()
            return
        }
        overrides[key] = StrainNameOverride(
            key: key,
            extractedName: name.trimmingCharacters(in: .whitespacesAndNewlines),
            correctedName: trimmed,
            dateUpdated: Date()
        )
        save()
    }

    func removeOverride(forExtractedName name: String) {
        overrides[StrainKnowledgeBase.normalizedKey(name)] = nil
        save()
    }

    func removeAll() {
        overrides.removeAll()
        save()
    }

    func allOverrides() -> [StrainNameOverride] {
        overrides.values.sorted { $0.dateUpdated > $1.dateUpdated }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? JSONDecoder().decode([StrainNameOverride].self, from: data) else { return }
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
final class InMemoryStrainNameOverrideStore: StrainNameOverrideStoring {
    private var overrides: [String: StrainNameOverride] = [:]

    init() {}

    func correctedName(forExtractedName name: String) -> String? {
        overrides[StrainKnowledgeBase.normalizedKey(name)]?.correctedName
    }

    func setCorrectedName(_ corrected: String, forExtractedName name: String) {
        let key = StrainKnowledgeBase.normalizedKey(name)
        let trimmed = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !trimmed.isEmpty else { return }
        if StrainKnowledgeBase.normalizedKey(trimmed) == key {
            overrides[key] = nil
            return
        }
        overrides[key] = StrainNameOverride(key: key, extractedName: name, correctedName: trimmed, dateUpdated: Date())
    }

    func removeOverride(forExtractedName name: String) {
        overrides[StrainKnowledgeBase.normalizedKey(name)] = nil
    }

    func removeAll() {
        overrides.removeAll()
    }

    func allOverrides() -> [StrainNameOverride] {
        overrides.values.sorted { $0.dateUpdated > $1.dateUpdated }
    }
}
