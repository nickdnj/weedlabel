import Foundation

// LogStore — the Log Book ("your HighNotes"). Persists scanned labels the user
// chose to save, plus a personal note + star rating they can edit anytime.
//
// Local JSON in Documents, behind a @MainActor protocol with File + InMemory
// impls — the same pattern as the override stores (StrainOverrideStore et al.).
// SwiftData remains the documented later migration if volume / iCloud sync ever
// demand it; for a personal log this is plenty and stays consistent.

struct LogEntry: Codable, Identifiable, Sendable, Equatable {
    var id: UUID
    var dateScanned: Date
    /// The scanned label, exactly as shown on the result screen.
    var label: CannabisLabel
    /// The OCR text this label was read from — powers the "pick the strain name
    /// from the label" correction list in the entry detail. Optional so older
    /// logbook.json decodes unchanged (nil for entries saved before this field).
    var ocrText: String?
    /// Flattened from SummaryOutcome (a non-Codable enum): the text shown, and
    /// whether it was the deterministic fallback rather than an AI summary.
    var summaryText: String
    var summaryDidFallback: Bool
    /// Flattened from StrainInsight (its source carries a non-Codable value).
    var strainLean: StrainLean?
    var strainSourceNote: String?
    /// The user's own journaling: a free-text note and a 0–5 rating (0 = unrated).
    var note: String
    var rating: Int
    /// Primary saved image in `LogImageStore` (Documents/images/) — the isolated,
    /// deskewed label crop when one was found, else the full capture. Nil for
    /// entries saved before image capture / live-only scans. Optional so old
    /// logbook.json decodes unchanged.
    var imageFilename: String?
    /// The full original photo, kept alongside the crop for context/debugging.
    /// Nil when no separate crop was made (then `imageFilename` IS the original).
    var originalImageFilename: String?

    init(
        id: UUID = UUID(),
        dateScanned: Date = Date(),
        label: CannabisLabel,
        ocrText: String? = nil,
        summaryText: String,
        summaryDidFallback: Bool,
        strainLean: StrainLean? = nil,
        strainSourceNote: String? = nil,
        note: String = "",
        rating: Int = 0,
        imageFilename: String? = nil,
        originalImageFilename: String? = nil
    ) {
        self.id = id
        self.dateScanned = dateScanned
        self.label = label
        self.ocrText = ocrText
        self.summaryText = summaryText
        self.summaryDidFallback = summaryDidFallback
        self.strainLean = strainLean
        self.strainSourceNote = strainSourceNote
        self.note = note
        self.rating = rating
        self.imageFilename = imageFilename
        self.originalImageFilename = originalImageFilename
    }
}

@MainActor
protocol LogStoring: AnyObject {
    /// All saved entries, newest first.
    func entries() -> [LogEntry]
    func add(_ entry: LogEntry)
    /// Persist edits to an existing entry (matched by id) — e.g. note / rating.
    func update(_ entry: LogEntry)
    func delete(id: UUID)
    func removeAll()
}

@MainActor
final class FileLogStore: LogStoring {
    private var byID: [UUID: LogEntry] = [:]
    private let fileURL: URL

    /// Defaults to `Documents/logbook.json`. A custom URL can be injected for tests.
    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.fileURL = docs.appendingPathComponent("logbook.json")
        }
        load()
    }

    func entries() -> [LogEntry] {
        byID.values.sorted { $0.dateScanned > $1.dateScanned }
    }

    func add(_ entry: LogEntry) {
        byID[entry.id] = entry
        save()
    }

    func update(_ entry: LogEntry) {
        guard byID[entry.id] != nil else { return }
        byID[entry.id] = entry
        save()
    }

    func delete(id: UUID) {
        if let entry = byID[id] {
            entry.imageFilename.map(LogImageStore.delete)
            entry.originalImageFilename.map(LogImageStore.delete)
        }
        byID[id] = nil
        save()
    }

    func removeAll() {
        for entry in byID.values {
            entry.imageFilename.map(LogImageStore.delete)
            entry.originalImageFilename.map(LogImageStore.delete)
        }
        byID.removeAll()
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? JSONDecoder().decode([LogEntry].self, from: data) else { return }
        byID = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
    }

    private func save() {
        let list = Array(byID.values)
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}

/// In-memory store for tests and SwiftUI previews — no disk I/O.
@MainActor
final class InMemoryLogStore: LogStoring {
    private var byID: [UUID: LogEntry] = [:]

    init(_ seed: [LogEntry] = []) {
        for entry in seed { byID[entry.id] = entry }
    }

    func entries() -> [LogEntry] {
        byID.values.sorted { $0.dateScanned > $1.dateScanned }
    }

    func add(_ entry: LogEntry) { byID[entry.id] = entry }

    func update(_ entry: LogEntry) {
        guard byID[entry.id] != nil else { return }
        byID[entry.id] = entry
    }

    func delete(id: UUID) { byID[id] = nil }

    func removeAll() { byID.removeAll() }
}
